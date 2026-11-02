import 'package:flauncher/launcher_theme.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemePanelPage extends StatelessWidget {
  static const String routeName = "theme_panel";

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final current = settingsService.launcherTheme;

    return Column(
      children: [
        Text("Theme", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        for (final theme in LauncherTheme.values)
          TextButton(
            autofocus: theme == current,
            onPressed: () => settingsService.setLauncherTheme(theme),
            child: Row(
              children: [
                Icon(theme.icon),
                Container(width: 8),
                Expanded(child: Text(theme.label, style: Theme.of(context).textTheme.bodyMedium)),
                if (theme == current) const Icon(Icons.check),
              ],
            ),
          ),
      ],
    );
  }
}
