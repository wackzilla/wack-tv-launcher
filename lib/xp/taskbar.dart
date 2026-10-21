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
import 'package:flauncher/widgets/date_time_widget.dart';
import 'package:flauncher/widgets/network_widget.dart';
import 'package:flauncher/xp/app_context_menu.dart';
import 'package:flauncher/xp/app_icon.dart';
import 'package:flauncher/xp/xp_dialogs.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const taskbarHeight = 44.0;

class Taskbar extends StatefulWidget
{
  final FocusNode startButtonFocusNode;
  final bool startButtonAutofocus;

  const Taskbar({super.key, required this.startButtonFocusNode, this.startButtonAutofocus = false});

  @override
  State<Taskbar> createState() => _TaskbarState();
}

class _TaskbarState extends State<Taskbar>
{
  String? _movingPackage;

  @override
  Widget build(BuildContext context) {
    final appsService = context.watch<AppsService>();
    final settingsService = context.watch<SettingsService>();
    final pinned = settingsService.taskbarPinned
        .map(appsService.findApplication)
        .whereType<App>()
        .toList();

    return Container(
      height: taskbarHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [XpColors.taskbarTop, XpColors.taskbarMiddle, XpColors.taskbarMiddle, XpColors.taskbarBottom],
          stops: [0, 0.12, 0.85, 1],
        ),
      ),
      child: Row(
        children: [
          _StartButton(focusNode: widget.startButtonFocusNode, autofocus: widget.startButtonAutofocus),
          const SizedBox(width: 8),
          if (pinned.isNotEmpty) ...[
            const _QuickLaunchGrip(),
            for (final app in pinned)
              _TaskbarAppButton(
                key: ValueKey(app.packageName),
                app: app,
                moving: _movingPackage == app.packageName,
                onStartMove: () => setState(() => _movingPackage = app.packageName),
                // Left and right move one place; up and down do nothing on a single row.
                onMove: (steps) {
                  if (steps.abs() == 2) {
                    settingsService.moveTaskbarPin(app.packageName, steps.sign);
                  }
                },
                onEndMove: () => setState(() => _movingPackage = null),
              ),
          ],
          const Spacer(),
          const _SystemTray(),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget
{
  final FocusNode focusNode;
  final bool autofocus;

  const _StartButton({required this.focusNode, required this.autofocus});

  @override
  Widget build(BuildContext context) {
    final launcherState = context.watch<LauncherState>();
    final bool pressed = launcherState.startMenuOpen;

    return XpPressable(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: launcherState.toggleStartMenu,
      builder: (context, focused) => Container(
        width: 128,
        height: taskbarHeight,
        padding: const EdgeInsets.only(left: 10, right: 18),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: pressed
                ? const [XpColors.startGreenBottom, XpColors.startGreen, XpColors.startGreenBottom]
                : focused
                    ? const [Color(0xFF7FCB76), Color(0xFF4DB33E), XpColors.startGreen]
                    : const [XpColors.startGreenTop, XpColors.startGreen, XpColors.startGreenBottom],
          ),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 3, offset: Offset(2, 0))],
        ),
        child: Row(
          children: [
            const WackLogo(size: 26),
            const SizedBox(width: 6),
            Text("start",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                shadows: focused
                    ? const [Shadow(color: Color(0xFFFFF4B0), blurRadius: 8), ...xpTextShadow]
                    : xpTextShadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLaunchGrip extends StatelessWidget
{
  const _QuickLaunchGrip();

  @override
  Widget build(BuildContext context) => Container(
    width: 3,
    height: 28,
    margin: const EdgeInsets.only(right: 6),
    decoration: const BoxDecoration(
      border: Border.symmetric(vertical: BorderSide(color: Color(0x66FFFFFF), width: 1)),
    ),
  );
}

class _TaskbarAppButton extends StatelessWidget
{
  final App app;
  final bool moving;
  final VoidCallback onStartMove;
  final void Function(int steps) onMove;
  final VoidCallback onEndMove;

  const _TaskbarAppButton({
    super.key,
    required this.app,
    required this.moving,
    required this.onStartMove,
    required this.onMove,
    required this.onEndMove,
  });

  @override
  Widget build(BuildContext context) => XpMoveKeys(
    moving: moving,
    onMove: onMove,
    onEndMove: onEndMove,
    child: XpPressable(
      onPressed: () => moving ? onEndMove() : launchXpApp(context, app),
      onMenu: () async {
        if (moving) {
          onEndMove();
          return;
        }
        final result = await showAppContextMenu(context, app, pinnedIn: PinnedIn.taskbar);
        if (result == AppContextMenuResult.move) {
          onStartMove();
        }
      },
      builder: (context, focused) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: focused || moving ? const Color(0x553D95FF) : null,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: moving ? XpColors.orangeLine : focused ? Colors.white : Colors.transparent,
            width: moving ? 2 : 1,
          ),
        ),
        child: AppIcon(app.packageName, size: 26),
      ),
    ),
  );
}

class _SystemTray extends StatelessWidget
{
  const _SystemTray();

  @override
  Widget build(BuildContext context) => Container(
    height: taskbarHeight,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [XpColors.trayTop, XpColors.tray, XpColors.tray, XpColors.trayBorder],
        stops: [0, 0.12, 0.85, 1],
      ),
      border: Border(left: BorderSide(color: XpColors.trayBorder, width: 1)),
    ),
    child: Row(
      children: [
        const IconTheme(
          data: IconThemeData(color: Colors.white, size: 20),
          child: NetworkWidget(),
        ),
        const SizedBox(width: 12),
        // Time over date, like the Windows 11 taskbar clock
        Selector<SettingsService, ({String timeFormat, String dateFormat, bool showTime, bool showDate})>(
          selector: (_, settings) => (
            timeFormat: settings.timeFormat,
            dateFormat: settings.dateFormat,
            showTime: settings.showTimeInStatusBar,
            showDate: settings.showDateInStatusBar,
          ),
          builder: (_, clock, __) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (clock.showTime)
                DateTimeWidget(clock.timeFormat,
                  key: ValueKey("time ${clock.timeFormat}"),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.2, shadows: xpTextShadow),
                ),
              if (clock.showDate)
                DateTimeWidget(clock.dateFormat,
                  key: ValueKey("date ${clock.dateFormat}"),
                  updateInterval: const Duration(minutes: 1),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 13, height: 1.2, shadows: xpTextShadow),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
