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

import 'dart:typed_data';

import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// An app's icon. Icons are loaded once per package and shared by the desktop,
/// taskbar and Start menu.
class AppIcon extends StatelessWidget
{
  static final Map<String, Future<Uint8List>> _cache = {};

  final String packageName;
  final double size;

  const AppIcon(this.packageName, {super.key, required this.size});

  static void evict(String packageName) => _cache.remove(packageName);

  @override
  Widget build(BuildContext context) {
    final future = _cache.putIfAbsent(packageName, () async {
      final appsService = context.read<AppsService>();
      Uint8List bytes = await appsService.getAppIcon(packageName);
      if (bytes.isEmpty) {
        bytes = await appsService.getAppBanner(packageName);
      }
      return bytes;
    });

    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<Uint8List>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true);
          }
          return Icon(Icons.web_asset, size: size * 0.9, color: Colors.white70);
        },
      ),
    );
  }
}
