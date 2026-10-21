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
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/xp/app_context_menu.dart';
import 'package:flauncher/xp/app_icon.dart';
import 'package:flauncher/xp/xp_dialogs.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _wifiSettingsAction = "android.settings.WIFI_SETTINGS";

/// The two-column XP Start menu. Its left column doubles as the All Programs list.
class StartMenu extends StatefulWidget
{
  final double height;

  const StartMenu({super.key, required this.height});

  @override
  State<StartMenu> createState() => _StartMenuState();
}

class _StartMenuState extends State<StartMenu>
{
  bool _allPrograms = false;
  bool _inputsExpanded = false;
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
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      // Menu anywhere in the Start menu (other than on an app) closes it, like pressing Start again.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.contextMenu) {
        context.read<LauncherState>().setStartMenuOpen(false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: FocusScope(
      autofocus: true,
      child: Container(
        width: 500,
        height: widget.height,
        decoration: const BoxDecoration(
          color: XpColors.startMenuFooter,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 10, offset: Offset(3, 0))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            Container(height: 2, color: XpColors.orangeLine),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: _allPrograms ? _allProgramsList(context) : _programsColumn(context),
                    ),
                  ),
                  Container(width: 1, color: XpColors.startMenuRightBorder),
                  SizedBox(width: 220, child: _placesColumn(context)),
                ],
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    ),
  );

  Widget _programsColumn(BuildContext context) {
    final appsService = context.watch<AppsService>();
    final settingsService = context.watch<SettingsService>();

    final pinned = _appsFor(appsService, settingsService.startMenuPinned);
    final recent = _appsFor(appsService, settingsService.recentApps)
        .where((app) => !pinned.contains(app))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pinned.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text("Hold OK on any app and choose \"Pin to Start menu\" to keep it here.",
                      style: TextStyle(color: XpColors.textGrey, fontSize: 12),
                    ),
                  ),
                for (int i = 0; i < pinned.length; i++)
                  _ProgramItem(app: pinned[i], large: true, autofocus: i == 0),
                if (recent.isNotEmpty) const _Separator(color: Color(0xFFD5D2CA)),
                for (int i = 0; i < recent.length; i++)
                  _ProgramItem(app: recent[i], autofocus: pinned.isEmpty && i == 0),
              ],
            ),
          ),
        ),
        const _Separator(color: Color(0xFFD5D2CA)),
        _StartMenuItem(
          label: "All Programs",
          bold: true,
          autofocus: pinned.isEmpty && recent.isEmpty,
          trailing: const _GreenArrow(),
          onPressed: () => setState(() => _allPrograms = true),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _allProgramsList(BuildContext context) {
    final apps = context.watch<AppsService>().applications;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StartMenuItem(
          label: "Back",
          bold: true,
          autofocus: true,
          leading: const RotatedBox(quarterTurns: 2, child: _GreenArrow()),
          onPressed: () => setState(() => _allPrograms = false),
        ),
        const _Separator(color: Color(0xFFD5D2CA)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 6),
            itemCount: apps.length,
            itemBuilder: (context, index) => _ProgramItem(app: apps[index]),
          ),
        ),
      ],
    );
  }

  Widget _placesColumn(BuildContext context) {
    final appsService = context.read<AppsService>();
    final launcherState = context.read<LauncherState>();

    void closeThen(void Function() action) {
      launcherState.setStartMenuOpen(false);
      action();
    }

    return Container(
      color: XpColors.startMenuRight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only on TVs: streaming boxes have no tuner app and no inputs to switch to.
            if (_hasLiveTv)
              _PlaceItem(
                label: "My TV",
                icon: Icons.live_tv,
                iconColor: const Color(0xFF2B5BC6),
                bold: true,
                onPressed: () => closeThen(appsService.openLiveTv),
              ),
            if (_inputs.isNotEmpty)
              _PlaceItem(
                label: "TV Inputs",
                icon: Icons.settings_input_hdmi,
                iconColor: const Color(0xFF555555),
                bold: true,
                trailing: Icon(_inputsExpanded ? Icons.expand_less : Icons.chevron_right, size: 16, color: XpColors.textBlue),
                onPressed: () => setState(() => _inputsExpanded = !_inputsExpanded),
              ),
            if (_inputsExpanded)
              for (final input in _inputs)
                _PlaceItem(
                  label: input.label,
                  icon: Icons.input,
                  iconColor: const Color(0xFF3C7F2E),
                  indent: true,
                  onPressed: () => closeThen(() => appsService.openTvInput(input)),
                ),
            if (_hasLiveTv || _inputs.isNotEmpty)
              const _Separator(color: XpColors.startMenuRightBorder),
            _PlaceItem(
              label: "Control Panel",
              icon: Icons.tune,
              iconColor: const Color(0xFF2E7BD6),
              onPressed: () => closeThen(appsService.openSettings),
            ),
            _PlaceItem(
              label: "Network Connections",
              icon: Icons.wifi,
              iconColor: const Color(0xFF2E7BD6),
              onPressed: () => closeThen(() => appsService.launchActivityFromAction(_wifiSettingsAction)),
            ),
            _PlaceItem(
              label: "Launcher Settings",
              icon: Icons.desktop_windows_outlined,
              iconColor: const Color(0xFF2E7BD6),
              onPressed: () => closeThen(() => showDialog(context: context, builder: (_) => const SettingsPanel())),
            ),
            const _Separator(color: XpColors.startMenuRightBorder),
            _PlaceItem(
              label: "Help and Support",
              icon: Icons.help,
              iconColor: const Color(0xFF2E7BD6),
              onPressed: () => closeThen(() => showHelpAndSupport(context)),
            ),
            _PlaceItem(
              label: "About Wack XP",
              icon: Icons.info,
              iconColor: const Color(0xFF2E7BD6),
              onPressed: () => closeThen(() => showAboutWackXp(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final appsService = context.read<AppsService>();
    final launcherState = context.read<LauncherState>();

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4282D6), XpColors.startMenuFooter, Color(0xFF1A4BB5)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _FooterButton(
            label: "Log Off",
            icon: Icons.key,
            color: const Color(0xFFE8A33A),
            onPressed: () {
              launcherState.setStartMenuOpen(false);
              appsService.startAmbientMode();
            },
          ),
          const SizedBox(width: 12),
          _FooterButton(
            label: "Turn Off Computer",
            icon: Icons.power_settings_new,
            color: const Color(0xFFD9481E),
            onPressed: () {
              launcherState.setStartMenuOpen(false);
              showTurnOffDialog(context);
            },
          ),
        ],
      ),
    );
  }

  List<App> _appsFor(AppsService appsService, List<String> packageNames) => packageNames
      .map(appsService.findApplication)
      .whereType<App>()
      .toList();
}

class _Header extends StatelessWidget
{
  const _Header();

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3C8AE5), XpColors.startMenuHeaderTop, XpColors.startMenuHeaderBottom],
        stops: [0, 0.2, 1],
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFC965), Color(0xFFE5631F)],
            ),
          ),
          child: const Icon(Icons.sports_esports, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 10),
        Selector<SettingsService, String>(
          selector: (_, settings) => settings.userName,
          builder: (_, userName, __) => Text(userName,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, shadows: xpTextShadow),
          ),
        ),
      ],
    ),
  );
}

class _ProgramItem extends StatelessWidget
{
  final App app;
  final bool large;
  final bool autofocus;

  const _ProgramItem({required this.app, this.large = false, this.autofocus = false});

  @override
  Widget build(BuildContext context) => _StartMenuItem(
    label: app.name,
    sublabel: app.hidden ? "Hidden from desktop" : null,
    bold: large,
    autofocus: autofocus,
    leading: AppIcon(app.packageName, size: large ? 32 : 24),
    onPressed: () => launchXpApp(context, app),
    onMenu: () => showAppContextMenu(context, app),
  );
}

class _StartMenuItem extends StatelessWidget
{
  final String label;
  final String? sublabel;
  final bool bold;
  final bool autofocus;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onPressed;
  final VoidCallback? onMenu;

  const _StartMenuItem({
    required this.label,
    required this.onPressed,
    this.sublabel,
    this.bold = false,
    this.autofocus = false,
    this.leading,
    this.trailing,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) => XpPressable(
    autofocus: autofocus,
    onPressed: onPressed,
    onMenu: onMenu,
    builder: (context, focused) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: focused ? XpColors.selection : null,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: focused ? Colors.white : XpColors.textDark,
                    fontSize: 14,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (sublabel != null)
                  Text(sublabel!,
                    style: TextStyle(color: focused ? Colors.white70 : XpColors.textGrey, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    ),
  );
}

class _PlaceItem extends StatelessWidget
{
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool bold;
  final bool indent;
  final Widget? trailing;
  final VoidCallback onPressed;

  const _PlaceItem({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
    this.bold = false,
    this.indent = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => XpPressable(
    onPressed: onPressed,
    builder: (context, focused) => Container(
      margin: EdgeInsets.fromLTRB(indent ? 24 : 4, 1, 4, 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: focused ? XpColors.selection : null,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Icon(icon, size: indent ? 18 : 24, color: focused ? Colors.white : iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: focused ? Colors.white : XpColors.textBlue,
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (trailing != null)
            IconTheme(
              data: IconThemeData(color: focused ? Colors.white : XpColors.textBlue),
              child: trailing!,
            ),
        ],
      ),
    ),
  );
}

class _FooterButton extends StatelessWidget
{
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _FooterButton({required this.label, required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => XpPressable(
    onPressed: onPressed,
    builder: (context, focused) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: focused ? const Color(0x553D95FF) : null,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: focused ? Colors.white70 : Colors.transparent),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, shadows: xpTextShadow)),
        ],
      ),
    ),
  );
}

class _GreenArrow extends StatelessWidget
{
  const _GreenArrow();

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      color: XpColors.startGreen,
      borderRadius: BorderRadius.circular(3),
    ),
    child: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
  );
}

class _Separator extends StatelessWidget
{
  final Color color;

  const _Separator({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
    color: color,
  );
}
