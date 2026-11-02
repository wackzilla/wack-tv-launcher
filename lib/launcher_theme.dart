import 'package:flutter/material.dart';

/// The looks the launcher can switch between in Launcher Settings > Theme.
///
/// To add one, add a value here. The compiler then points at each place that has to
/// choose per theme: the home screen in flauncher.dart and the colors in flauncher_app.dart.
///
/// The value's name is what's saved on the TV, so don't rename one.
enum LauncherTheme {
  xp("Windows XP", Icons.desktop_windows_outlined),
  scenic("Scenic", Icons.landscape_outlined);

  /// Used until a theme is picked on the TV.
  static const defaultTheme = scenic;

  final String label;
  final IconData icon;

  const LauncherTheme(this.label, this.icon);
}
