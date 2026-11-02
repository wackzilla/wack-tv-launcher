/*
 * Wack XP Launcher (FLauncher fork)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Wikimedia asks for a way to reach whoever runs a client.
const _userAgent = "WackTVLauncher/1.0 (https://github.com/wackzilla/wack-tv-launcher)";
const _feedUrl = "https://www.reddit.com/r/EarthPorn/top.rss?t=all&limit=100";
const _bingUrl = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8";

// Community-chosen photos on Wikimedia Commons. A photo in two of these is only downloaded once.
const _wikimediaCategories = [
  "landscapes",
  "mountains",
  "lakes",
  "sunsets",
  "beaches",
  "waterfalls",
  "forests",
  "coasts",
  "islands",
];
const _wikimediaPageSize = "50";
const _wikimediaPagePause = Duration(seconds: 5);
const _wikimediaRateLimitPause = Duration(minutes: 5);
// Narrower or wider than this and the screen would crop away too much of the photo.
const _wikimediaMinRatio = 1.3;
const _wikimediaMaxRatio = 2.1;

// Reddit answers 429 to a second feed request straight after the first, so pages are far apart.
const _pagePause = Duration(minutes: 3);
const _imagePause = Duration(seconds: 2);
const _failurePause = Duration(minutes: 30);
const _maxRateLimitPause = Duration(hours: 1);
const _maxImageBytes = 40 * 1024 * 1024;
// Photos stop here, so they can't crowd out apps on a device with little storage.
const _minFreeBytes = 1024 * 1024 * 1024;

const _minWidth = 1600;
const _minHeight = 900;

final _entryPattern = RegExp(r"<entry>(.*?)</entry>", dotAll: true);
final _postIdPattern = RegExp(r"<id>t3_([a-z0-9]+)</id>");
final _titlePattern = RegExp(r"<title>(.*?)</title>", dotAll: true);
final _imagePattern = RegExp(r"https://i\.redd\.it/[A-Za-z0-9_-]+\.(?:jpe?g|png)");
final _sizePattern = RegExp(r"(\d{3,5})\s*(?:x|X|×|&#215;)\s*(\d{3,5})");

/// The Scenic theme's backgrounds: downloads [targetCount] photos from r/EarthPorn and the
/// featured photos on Wikimedia Commons once, then never touches the network again. The two run
/// side by side, so Reddit's rate limits don't hold up Wikimedia. Survives restarts by remembering
/// its place in each. Stops early if storage runs low, and tries again on the next start.
class PhotoService extends ChangeNotifier
{
  static const targetCount = 1000;

  final FLauncherChannel _channel;
  final HttpClient _client = HttpClient()
    ..userAgent = _userAgent
    ..connectionTimeout = const Duration(seconds: 30);

  final List<File> _photos = [];
  late Directory _directory;
  late File _stateFile;
  late File _wikimediaStateFile;

  String? _after;
  bool _complete = false;
  int _wikimediaCategory = 0;
  Map<String, String>? _wikimediaContinue;
  bool _wikimediaComplete = false;
  bool _started = false;
  bool _storageFull = false;

  List<File> get photos => List.unmodifiable(_photos);

  bool get complete => _complete && _wikimediaComplete;

  /// Downloading stopped to leave [_minFreeBytes] free.
  bool get storageFull => _storageFull;

  int get redditPhotoCount => _photos.where(_isRedditPhoto).length;

  PhotoService(this._channel);

  /// Safe to call repeatedly; only the first call does anything.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    final support = await getApplicationSupportDirectory();
    _directory = Directory("${support.path}/photos");
    await _directory.create(recursive: true);
    _stateFile = File("${_directory.path}/state.json");
    _wikimediaStateFile = File("${_directory.path}/wikimedia.json");

    await _loadState();
    await _loadWikimediaState();
    await _loadPhotos();
    notifyListeners();

    await Future.wait([
      if (!_complete) _download(),
      if (!_wikimediaComplete) _downloadWikimedia(),
    ]);
  }

  Future<void> _loadState() async {
    if (await _stateFile.exists()) {
      try {
        final Map<String, dynamic> state = jsonDecode(await _stateFile.readAsString());
        // A new target restarts from the top of the feed, since the page that reached the old
        // one was left part way through. Photos already downloaded are skipped.
        final bool sameTarget = state["target"] == targetCount;
        _after = sameTarget ? state["after"] : null;
        _complete = sameTarget && (state["complete"] ?? false);
      }
      on FormatException {
        await _stateFile.delete();
      }
    }
  }

  Future<void> _saveState() =>
      _stateFile.writeAsString(jsonEncode({"after": _after, "complete": _complete, "target": targetCount}));

  Future<void> _loadWikimediaState() async {
    if (await _wikimediaStateFile.exists()) {
      try {
        final Map<String, dynamic> state = jsonDecode(await _wikimediaStateFile.readAsString());
        final Map<String, dynamic>? next = state["continue"];
        _wikimediaCategory = state["category"] ?? 0;
        _wikimediaContinue = next == null ? null : Map<String, String>.from(next);
        _wikimediaComplete = state["complete"] ?? false;
      }
      on FormatException {
        await _wikimediaStateFile.delete();
      }
    }
  }

  Future<void> _saveWikimediaState() => _wikimediaStateFile.writeAsString(jsonEncode({
    "category": _wikimediaCategory,
    "continue": _wikimediaContinue,
    "complete": _wikimediaComplete,
  }));

  Future<void> _loadPhotos() async {
    final files = await _directory.list().where((entity) => entity is File && entity.path.endsWith(".jpg")).toList();
    _photos
      ..clear()
      ..addAll(files.cast<File>());
  }

  bool _isRedditPhoto(File file) => file.uri.pathSegments.last.startsWith("r_");

  /// False once storage is low. Callers return without saving, so they pick up from the same
  /// place on the next start if there's room by then.
  Future<bool> _hasRoom() async {
    if (_storageFull) {
      return false;
    }
    try {
      if (await _channel.getFreeSpace() >= _minFreeBytes) {
        return true;
      }
    }
    on Exception catch (error) {
      debugPrint("Free space check failed: $error");
      return true;
    }
    _storageFull = true;
    notifyListeners();
    await _fetchBingIfEmpty();
    return false;
  }

  Future<void> _download() async {
    Duration rateLimitPause = _pagePause;

    while (redditPhotoCount < targetCount) {
      if (!await _hasRoom()) {
        return;
      }

      final _FeedPage page;
      try {
        page = await _fetchFeedPage();
      }
      on _RateLimited catch (limited) {
        rateLimitPause = limited.retryAfter ?? _doubled(rateLimitPause);
        await _fetchBingIfEmpty();
        await Future.delayed(rateLimitPause);
        continue;
      }
      on Exception catch (error) {
        debugPrint("Photo feed failed: $error");
        await _fetchBingIfEmpty();
        await Future.delayed(_failurePause);
        continue;
      }
      rateLimitPause = _pagePause;

      if (page.lastPostId == null && redditPhotoCount == 0) {
        // An empty feed with nothing downloaded is a failure, not the end of the list.
        await _fetchBingIfEmpty();
        await Future.delayed(_failurePause);
        continue;
      }

      for (final post in page.posts) {
        if (redditPhotoCount >= targetCount) {
          break;
        }
        if (!await _hasRoom()) {
          return;
        }
        await _downloadPost(post);
      }

      _after = page.lastPostId == null ? null : "t3_${page.lastPostId}";
      if (page.lastPostId == null) {
        // Reddit has no more pages, so what we've got is what we keep.
        break;
      }
      await _saveState();

      if (redditPhotoCount < targetCount) {
        await Future.delayed(_pagePause);
      }
    }

    await _finish();
  }

  Duration _doubled(Duration pause) {
    final doubled = pause * 2;
    return doubled > _maxRateLimitPause ? _maxRateLimitPause : doubled;
  }

  Future<void> _finish() async {
    _complete = true;
    await _saveState();
    await _removeBingPhotos();
    notifyListeners();
  }

  /// Bing's photos only fill in until the real ones arrive.
  Future<void> _removeBingPhotos() async {
    final bingPhotos = _photos.where((photo) => photo.uri.pathSegments.last.startsWith("b_")).toList();
    if (bingPhotos.length == _photos.length) {
      return;
    }
    for (final photo in bingPhotos) {
      await photo.delete();
      _photos.remove(photo);
    }
  }

  Future<void> _downloadWikimedia() async {
    while (_wikimediaCategory < _wikimediaCategories.length) {
      if (!await _hasRoom()) {
        return;
      }

      final _WikimediaPage page;
      try {
        page = await _fetchWikimediaPage();
      }
      on _RateLimited catch (limited) {
        await Future.delayed(limited.retryAfter ?? _wikimediaRateLimitPause);
        continue;
      }
      on Exception catch (error) {
        debugPrint("Wikimedia failed: $error");
        await _fetchBingIfEmpty();
        await Future.delayed(_failurePause);
        continue;
      }

      for (final file in page.files) {
        if (!await _hasRoom()) {
          return;
        }
        await _downloadWikimediaFile(file);
      }

      if (page.next == null) {
        _wikimediaCategory++;
      }
      _wikimediaContinue = page.next;
      await _saveWikimediaState();
      await Future.delayed(_wikimediaPagePause);
    }

    _wikimediaComplete = true;
    await _saveWikimediaState();
    await _removeBingPhotos();
    notifyListeners();
  }

  Future<_WikimediaPage> _fetchWikimediaPage() async {
    final request = await _client.getUrl(Uri.https("commons.wikimedia.org", "/w/api.php", {
      "action": "query",
      "format": "json",
      "generator": "categorymembers",
      "gcmtitle": "Category:Featured pictures of ${_wikimediaCategories[_wikimediaCategory]}",
      "gcmtype": "file",
      "gcmlimit": _wikimediaPageSize,
      "prop": "imageinfo",
      "iiprop": "url|size|mime",
      "iiurlwidth": "1920",
      ...?_wikimediaContinue,
    }));
    final response = await request.close();

    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw await _rateLimited(response);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException("Wikimedia returned ${response.statusCode}");
    }

    final Map<String, dynamic> body = jsonDecode(await response.transform(utf8.decoder).join());
    // Errors come back as a normal response, and would otherwise look like an empty category.
    if (body["error"] != null) {
      throw HttpException("Wikimedia error: ${body["error"]["code"]}");
    }

    final Map<String, dynamic> pages = body["query"]?["pages"] ?? {};
    final files = <_Post>[];
    for (final page in pages.values) {
      final List<dynamic>? info = page["imageinfo"];
      if (info != null && info.isNotEmpty && _wikimediaImageFits(info.first)) {
        files.add(_Post("${page["pageid"]}", info.first["thumburl"] ?? info.first["url"]));
      }
    }

    final Map<String, dynamic>? next = body["continue"];
    return _WikimediaPage(files, next?.map((key, value) => MapEntry(key, "$value")));
  }

  bool _wikimediaImageFits(Map<String, dynamic> image) {
    final num width = image["width"];
    final num height = image["height"];
    return image["mime"] == "image/jpeg" &&
        width >= _minWidth &&
        height >= _minHeight &&
        width / height >= _wikimediaMinRatio &&
        width / height <= _wikimediaMaxRatio;
  }

  Future<void> _downloadWikimediaFile(_Post file) async {
    final target = File("${_directory.path}/w_${file.id}.jpg");
    if (await target.exists()) {
      return;
    }

    while (true) {
      try {
        await _savePhoto(file.imageUrl, target, "w_${file.id}");
        break;
      }
      on _RateLimited catch (limited) {
        // Moving on would lose this photo for good, since its page won't be fetched again.
        await Future.delayed(limited.retryAfter ?? _wikimediaRateLimitPause);
      }
      on Exception catch (error) {
        debugPrint("Photo ${file.id} failed: $error");
        break;
      }
    }
    await Future.delayed(_imagePause);
  }

  Future<_RateLimited> _rateLimited(HttpClientResponse response) async {
    final retryAfter = int.tryParse(response.headers.value(HttpHeaders.retryAfterHeader) ?? response.headers.value("x-ratelimit-reset") ?? "");
    await response.drain<void>();
    return _RateLimited(retryAfter == null ? null : Duration(seconds: retryAfter));
  }

  Future<_FeedPage> _fetchFeedPage() async {
    final url = _after == null ? _feedUrl : "$_feedUrl&after=$_after";
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw await _rateLimited(response);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException("Feed returned ${response.statusCode}");
    }

    return _parseFeed(await response.transform(utf8.decoder).join());
  }

  _FeedPage _parseFeed(String feed) {
    final posts = <_Post>[];
    String? lastPostId;

    for (final entry in _entryPattern.allMatches(feed)) {
      // The post's HTML is escaped inside the entry.
      final body = entry.group(1)!.replaceAll("&amp;", "&").replaceAll("&quot;", '"');
      final id = _postIdPattern.firstMatch(body)?.group(1);
      if (id == null) {
        continue;
      }
      lastPostId = id;

      final image = _imagePattern.firstMatch(body)?.group(0);
      if (image != null && _titleAllowsPost(_titlePattern.firstMatch(body)?.group(1))) {
        posts.add(_Post(id, image));
      }
    }
    return _FeedPage(posts, lastPostId);
  }

  /// r/EarthPorn titles usually state the size, which saves downloading photos that won't fit.
  bool _titleAllowsPost(String? title) {
    final size = title == null ? null : _sizePattern.firstMatch(title);
    if (size == null) {
      return true;
    }
    final width = int.parse(size.group(1)!);
    final height = int.parse(size.group(2)!);
    return width > height && width >= _minWidth && height >= _minHeight;
  }

  Future<void> _downloadPost(_Post post) async {
    final target = File("${_directory.path}/r_${post.id}.jpg");
    if (await target.exists()) {
      return;
    }

    try {
      await _savePhoto(post.imageUrl, target, post.id);
    }
    on Exception catch (error) {
      debugPrint("Photo ${post.id} failed: $error");
    }
    await Future.delayed(_imagePause);
  }

  Future<void> _savePhoto(String url, File target, String temporaryName) async {
    final temporary = File("${_directory.path}/$temporaryName.tmp");
    try {
      if (await _downloadTo(url, temporary) &&
          await _channel.resizePhoto(temporary.path, target.path, _minWidth, _minHeight)) {
        _addPhoto(target);
      }
    }
    finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<bool> _downloadTo(String url, File file) async {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw await _rateLimited(response);
    }
    if (response.statusCode != HttpStatus.ok || response.contentLength > _maxImageBytes) {
      await response.drain<void>();
      return false;
    }
    await response.pipe(file.openWrite()).timeout(const Duration(minutes: 3));
    return true;
  }

  /// Gives the screen something to show when Reddit is refusing us and we have nothing yet.
  Future<void> _fetchBingIfEmpty() async {
    if (_photos.isNotEmpty) {
      return;
    }

    try {
      final request = await _client.getUrl(Uri.parse(_bingUrl));
      final response = await request.close();
      final Map<String, dynamic> body = jsonDecode(await response.transform(utf8.decoder).join());

      for (final image in body["images"] as List<dynamic>) {
        final String urlBase = image["urlbase"];
        final name = urlBase.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), "_");
        final target = File("${_directory.path}/b_$name.jpg");
        if (await _downloadTo("https://www.bing.com${urlBase}_1920x1080.jpg", target)) {
          _addPhoto(target);
        }
      }
    }
    catch (error) {
      debugPrint("Bing photos failed: $error");
    }
  }

  void _addPhoto(File file) {
    _photos.add(file);
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close(force: true);
    super.dispose();
  }
}

class _Post
{
  final String id;
  final String imageUrl;

  _Post(this.id, this.imageUrl);
}

class _FeedPage
{
  final List<_Post> posts;
  final String? lastPostId;

  _FeedPage(this.posts, this.lastPostId);
}

class _WikimediaPage
{
  final List<_Post> files;
  final Map<String, String>? next;

  _WikimediaPage(this.files, this.next);
}

class _RateLimited implements Exception
{
  final Duration? retryAfter;

  _RateLimited(this.retryAfter);
}
