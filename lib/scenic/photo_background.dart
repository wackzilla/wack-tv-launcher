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
import 'dart:io';

import 'package:flauncher/providers/photo_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _rotateEvery = Duration(minutes: 2);
const _fadeDuration = Duration(seconds: 2);

/// Crossfades through the downloaded photos in a shuffled order, so all of them come up before
/// any repeats. Shows a dusk gradient until the first photo has arrived.
class PhotoBackground extends StatefulWidget
{
  /// Moves on to the next photo whenever this notifies.
  final Listenable nextPhoto;

  const PhotoBackground({super.key, required this.nextPhoto});

  @override
  State<PhotoBackground> createState() => _PhotoBackgroundState();
}

class _PhotoBackgroundState extends State<PhotoBackground>
{
  final List<File> _queue = [];
  late final PhotoService _photoService;
  late Timer _timer;
  File? _current;

  @override
  void initState() {
    super.initState();
    _photoService = context.read<PhotoService>();
    _photoService.addListener(_onPhotosChanged);
    _photoService.start();
    widget.nextPhoto.addListener(_onNextPhoto);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(_rotateEvery, (_) {
      // No point decoding photos behind whatever app is open.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _showNext();
      }
    });
  }

  // Starts the wait over, so a photo that was just asked for gets its full time on screen.
  void _onNextPhoto() {
    _timer.cancel();
    _startTimer();
    _showNext();
  }

  @override
  void dispose() {
    _timer.cancel();
    widget.nextPhoto.removeListener(_onNextPhoto);
    _photoService.removeListener(_onPhotosChanged);
    super.dispose();
  }

  void _onPhotosChanged() {
    if (_current == null) {
      _showNext();
    }
  }

  File? _nextPhoto() {
    if (_queue.isEmpty) {
      _queue
        ..addAll(_photoService.photos.where((photo) => photo.path != _current?.path))
        ..shuffle();
    }
    while (_queue.isNotEmpty) {
      final photo = _queue.removeLast();
      if (photo.existsSync()) {
        return photo;
      }
    }
    return null;
  }

  Future<void> _showNext() async {
    final next = _nextPhoto();
    if (next == null) {
      return;
    }

    // Decode first, so the fade starts from a ready photo rather than a blank frame.
    bool failed = false;
    await precacheImage(FileImage(next), context, onError: (_, __) => failed = true);
    if (!mounted || failed) {
      return;
    }

    final previous = _current;
    setState(() => _current = next);
    if (previous != null) {
      Future.delayed(_fadeDuration * 2, () => FileImage(previous).evict());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: _fadeDuration,
    layoutBuilder: (current, previous) => Stack(
      fit: StackFit.expand,
      children: [...previous, if (current != null) current],
    ),
    child: _current == null
        ? const DecoratedBox(
            key: ValueKey("no photo"),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF28305E), Color(0xFF6A5A92), Color(0xFFC48A8E), Color(0xFF2B3A55)],
              ),
            ),
          )
        : Image.file(
            _current!,
            key: ValueKey(_current!.path),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
  );
}
