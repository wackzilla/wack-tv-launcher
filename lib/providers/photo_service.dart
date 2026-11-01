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

const _userAgent = "WackTVLauncher/1.0 (Android TV launcher)";
const _feedUrl = "https://www.reddit.com/r/EarthPorn/top.rss?t=all&limit=100";
const _bingUrl = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8";

// Reddit answers 429 to a second feed request straight after the first, so pages are far apart.
const _pagePause = Duration(minutes: 3);
const _imagePause = Duration(seconds: 2);
const _failurePause = Duration(minutes: 30);
const _maxRateLimitPause = Duration(hours: 1);
const _maxImageBytes = 40 * 1024 * 1024;

const _minWidth = 1600;
const _minHeight = 900;

final _entryPattern = RegExp(r"<entry>(.*?)</entry>", dotAll: true);
final _postIdPattern = RegExp(r"<id>t3_([a-z0-9]+)</id>");
final _titlePattern = RegExp(r"<title>(.*?)</title>", dotAll: true);
final _imagePattern = RegExp(r"https://i\.redd\.it/[A-Za-z0-9_-]+\.(?:jpe?g|png)");
final _sizePattern = RegExp(r"(\d{3,5})\s*(?:x|X|×|&#215;)\s*(\d{3,5})");

/// The Scenic theme's backgrounds: downloads [targetCount] photos from r/EarthPorn once, then
/// never touches the network again. Survives restarts by remembering its place in the feed.
class PhotoService extends ChangeNotifier
{
  static const targetCount = 250;

  final FLauncherChannel _channel;
  final HttpClient _client = HttpClient()
    ..userAgent = _userAgent
    ..connectionTimeout = const Duration(seconds: 30);

  final List<File> _photos = [];
  late Directory _directory;
  late File _stateFile;

  String? _after;
  bool _complete = false;
  bool _started = false;

  List<File> get photos => List.unmodifiable(_photos);

  bool get complete => _complete;

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

    await _loadState();
    await _loadPhotos();
    notifyListeners();

    if (!_complete) {
      await _download();
    }
  }

  Future<void> _loadState() async {
    if (await _stateFile.exists()) {
      try {
        final Map<String, dynamic> state = jsonDecode(await _stateFile.readAsString());
        _after = state["after"];
        _complete = state["complete"] ?? false;
      }
      on FormatException {
        await _stateFile.delete();
      }
    }
  }

  Future<void> _saveState() =>
      _stateFile.writeAsString(jsonEncode({"after": _after, "complete": _complete}));

  Future<void> _loadPhotos() async {
    final files = await _directory.list().where((entity) => entity is File && entity.path.endsWith(".jpg")).toList();
    _photos
      ..clear()
      ..addAll(files.cast<File>());
  }

  bool _isRedditPhoto(File file) => file.uri.pathSegments.last.startsWith("r_");

  Future<void> _download() async {
    Duration rateLimitPause = _pagePause;

    while (redditPhotoCount < targetCount) {
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

    // Bing's photos only fill in until the real ones arrive.
    if (redditPhotoCount > 0) {
      for (final photo in _photos.where((photo) => !_isRedditPhoto(photo)).toList()) {
        await photo.delete();
        _photos.remove(photo);
      }
    }
    notifyListeners();
  }

  Future<_FeedPage> _fetchFeedPage() async {
    final url = _after == null ? _feedUrl : "$_feedUrl&after=$_after";
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode == HttpStatus.tooManyRequests) {
      final retryAfter = int.tryParse(response.headers.value(HttpHeaders.retryAfterHeader) ?? response.headers.value("x-ratelimit-reset") ?? "");
      await response.drain<void>();
      throw _RateLimited(retryAfter == null ? null : Duration(seconds: retryAfter));
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

    final temporary = File("${_directory.path}/${post.id}.tmp");
    try {
      if (await _downloadTo(post.imageUrl, temporary) &&
          await _channel.resizePhoto(temporary.path, target.path, _minWidth, _minHeight)) {
        _addPhoto(target);
      }
    }
    on Exception catch (error) {
      debugPrint("Photo ${post.id} failed: $error");
    }
    finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
    await Future.delayed(_imagePause);
  }

  Future<bool> _downloadTo(String url, File file) async {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();

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

class _RateLimited implements Exception
{
  final Duration? retryAfter;

  _RateLimited(this.retryAfter);
}
