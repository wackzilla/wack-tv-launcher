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

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/tv_input.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/scenic/weather_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/xp/app_context_menu.dart';
import 'package:flauncher/xp/app_icon.dart';
import 'package:flauncher/xp/xp_dialogs.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _wifiSettingsAction = "android.settings.WIFI_SETTINGS";

/// Everything the XP Start menu offers besides apps. It shares the Start menu's open state,
/// so Back, Home and launching an app close it the same way.
class ScenicMenu extends StatefulWidget
{
  const ScenicMenu({super.key});

  @override
  State<ScenicMenu> createState() => _ScenicMenuState();
}

class _ScenicMenuState extends State<ScenicMenu>
{
  bool _inputsExpanded = false;
  bool _hiddenExpanded = false;
  List<TvInput> _inputs = const [];
  bool _hasLiveTv = false;

  @override
  void initState() {
    super.initState();
    final appsService = context.read<AppsService>();
    appsService.getTvInputs().then((inputs) {
      if (mounted) {
        setState(() => _inputs = inputs);
      }
    });
    appsService.hasLiveTv().then((hasLiveTv) {
      if (mounted) {
        setState(() => _hasLiveTv = hasLiveTv);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appsService = context.watch<AppsService>();
    final launcherState = context.read<LauncherState>();
    final List<App> hiddenApps = appsService.applications.where((app) => app.hidden).toList();

    void closeThen(void Function() action) {
      launcherState.setStartMenuOpen(false);
      action();
    }

    return FocusScope(
      autofocus: true,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: ScenicColors.window,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ScenicColors.glassBorder),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MenuItem(
                label: "Launcher Settings",
                icon: Icons.tune,
                autofocus: true,
                onPressed: () => closeThen(() => showDialog(context: context, builder: (_) => const SettingsPanel())),
              ),
              _MenuItem(
                label: "Android Settings",
                icon: Icons.settings_outlined,
                onPressed: () => closeThen(appsService.openSettings),
              ),
              _MenuItem(
                label: "Network",
                icon: Icons.wifi,
                onPressed: () => closeThen(() => appsService.launchActivityFromAction(_wifiSettingsAction)),
              ),
              _MenuItem(
                label: "Weather Location",
                icon: Icons.wb_sunny_outlined,
                onPressed: () => closeThen(() => showWeatherLocationDialog(context)),
              ),
              // Only on TVs: streaming boxes have no tuner app and no inputs to switch to.
              if (_hasLiveTv)
                _MenuItem(
                  label: "Live TV",
                  icon: Icons.live_tv,
                  onPressed: () => closeThen(appsService.openLiveTv),
                ),
              if (_inputs.isNotEmpty)
                _MenuItem(
                  label: "TV Inputs",
                  icon: Icons.settings_input_hdmi,
                  trailing: _inputsExpanded ? Icons.expand_less : Icons.chevron_right,
                  onPressed: () => setState(() => _inputsExpanded = !_inputsExpanded),
                ),
              if (_inputsExpanded)
                for (final input in _inputs)
                  _MenuItem(
                    label: input.label,
                    icon: Icons.input,
                    indent: true,
                    onPressed: () => closeThen(() => appsService.openTvInput(input)),
                  ),
              if (hiddenApps.isNotEmpty)
                _MenuItem(
                  label: "Hidden Apps",
                  icon: Icons.visibility_off_outlined,
                  trailing: _hiddenExpanded ? Icons.expand_less : Icons.chevron_right,
                  onPressed: () => setState(() => _hiddenExpanded = !_hiddenExpanded),
                ),
              if (_hiddenExpanded)
                for (final app in hiddenApps)
                  _MenuItem(
                    key: ValueKey(app.packageName),
                    label: app.name,
                    leading: AppIcon(app.packageName, size: 22),
                    indent: true,
                    onPressed: () => launchXpApp(context, app),
                    onMenu: () => showAppContextMenu(context, app),
                  ),
              const _Separator(),
              _MenuItem(
                label: "Screensaver",
                icon: Icons.nightlight_outlined,
                onPressed: () => closeThen(appsService.startAmbientMode),
              ),
              _MenuItem(
                label: "Power",
                icon: Icons.power_settings_new,
                onPressed: () => closeThen(() => showTurnOffDialog(context)),
              ),
              const _Separator(),
              _MenuItem(
                label: "Help",
                icon: Icons.help_outline,
                onPressed: () => closeThen(() => showHelpAndSupport(context)),
              ),
              _MenuItem(
                label: "About",
                icon: Icons.info_outline,
                onPressed: () => closeThen(() => showAboutWackXp(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget
{
  final String label;
  final IconData? icon;
  final Widget? leading;
  final IconData? trailing;
  final bool autofocus;
  final bool indent;
  final VoidCallback onPressed;
  final VoidCallback? onMenu;

  const _MenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.trailing,
    this.autofocus = false,
    this.indent = false,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) => XpPressable(
    autofocus: autofocus,
    onPressed: onPressed,
    onMenu: onMenu,
    builder: (context, focused) {
      final color = focused ? Colors.black87 : Colors.white;

      return Container(
        margin: EdgeInsets.fromLTRB(indent ? 26 : 8, 1, 8, 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: focused ? Colors.white : null,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            leading ?? Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 14),
              ),
            ),
            if (trailing != null) Icon(trailing, size: 18, color: color),
          ],
        ),
      );
    },
  );
}

class _Separator extends StatelessWidget
{
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
    color: ScenicColors.glassBorder,
  );
}
