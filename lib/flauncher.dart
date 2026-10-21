/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/xp/app_context_menu.dart';
import 'package:flauncher/xp/app_icon.dart';
import 'package:flauncher/xp/hills_wallpaper.dart';
import 'package:flauncher/xp/start_menu.dart';
import 'package:flauncher/xp/taskbar.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/category.dart';

/// The Windows XP style home screen: wallpaper, desktop icons, taskbar and Start menu.
class FLauncher extends StatefulWidget {
  const FLauncher();

  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> {
  final FocusNode _firstIconFocusNode = FocusNode(debugLabel: "first desktop icon");
  final FocusNode _startButtonFocusNode = FocusNode(debugLabel: "start button");

  late final LauncherState _launcherState;
  late int _homePressedCount;
  late bool _startMenuOpen;

  @override
  void initState() {
    super.initState();
    _launcherState = context.read<LauncherState>();
    _homePressedCount = _launcherState.homePressedCount;
    _startMenuOpen = _launcherState.startMenuOpen;
    _launcherState.addListener(_onLauncherStateChanged);
  }

  @override
  void dispose() {
    _launcherState.removeListener(_onLauncherStateChanged);
    _firstIconFocusNode.dispose();
    _startButtonFocusNode.dispose();
    super.dispose();
  }

  void _onLauncherStateChanged() {
    if (_launcherState.homePressedCount != _homePressedCount) {
      _homePressedCount = _launcherState.homePressedCount;
      _startMenuOpen = _launcherState.startMenuOpen;
      _focusAfterFrame(() => _firstIconFocusNode.context != null ? _firstIconFocusNode : _startButtonFocusNode);
    }
    else if (_startMenuOpen && !_launcherState.startMenuOpen) {
      // Like XP, closing the Start menu leaves the Start button selected.
      _startMenuOpen = false;
      _focusAfterFrame(() => _startButtonFocusNode);
    }
    else {
      _startMenuOpen = _launcherState.startMenuOpen;
    }
  }

  void _focusAfterFrame(FocusNode Function() node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node().context != null) {
          node().requestFocus();
        }
      });

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      // Menu on anything that doesn't have its own menu opens the Start menu.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.contextMenu) {
        _launcherState.toggleStartMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Material(
      color: Colors.black,
      child: Stack(
      children: [
        Positioned.fill(child: _wallpaper(context)),
        Consumer<LauncherState>(
          builder: (context, state, _) {
            if (!state.launcherVisible) {
              return const Center(child: AlternativeLauncherView());
            }

            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: ExcludeFocus(
                        excluding: state.startMenuOpen,
                        child: _desktop(),
                      ),
                    ),
                    ExcludeFocus(
                      excluding: state.startMenuOpen,
                      child: Selector<AppsService, bool>(
                        selector: (_, appsService) => appsService.initialized && _desktopApps(appsService).isEmpty,
                        builder: (_, desktopEmpty, __) => Taskbar(
                          startButtonFocusNode: _startButtonFocusNode,
                          startButtonAutofocus: desktopEmpty,
                        ),
                      ),
                    ),
                  ],
                ),
                if (state.startMenuOpen)
                  Positioned(
                    left: 0,
                    bottom: taskbarHeight,
                    child: LayoutBuilder(
                      builder: (context, _) {
                        final double height = MediaQuery.sizeOf(context).height - taskbarHeight - 24;
                        return StartMenu(height: height.clamp(300.0, 480.0));
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
      ),
    ),
  );

  Widget _wallpaper(BuildContext context) {
    final wallpaperService = context.watch<WallpaperService>();
    final gradientChosen = context.select<SettingsService, bool>((settings) => settings.gradientUuid != null);

    if (wallpaperService.wallpaper != null) {
      return Image(
        image: wallpaperService.wallpaper!,
        key: const Key("background"),
        fit: BoxFit.cover,
      );
    }
    if (gradientChosen) {
      return Container(key: const Key("background"), decoration: BoxDecoration(gradient: wallpaperService.gradient.gradient));
    }
    return const HillsWallpaper(key: Key("background"));
  }

  Widget _desktop() => Consumer<AppsService>(
    builder: (context, appsService, _) {
      if (!appsService.initialized) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }

      final entries = _desktopApps(appsService);
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SizedBox(
            height: constraints.maxHeight - 12,
            child: Wrap(
              direction: Axis.vertical,
              spacing: 6,
              runSpacing: 10,
              children: [
                for (int i = 0; i < entries.length; i++)
                  _DesktopIcon(
                    key: ValueKey(entries[i].app.packageName),
                    app: entries[i].app,
                    category: entries[i].category,
                    focusNode: i == 0 ? _firstIconFocusNode : null,
                    autofocus: i == 0,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// Every app on the launcher's groups, in group order, each shown once.
  static List<({App app, Category category})> _desktopApps(AppsService appsService) {
    final seen = <String>{};
    final entries = <({App app, Category category})>[];

    for (final section in appsService.launcherSections) {
      if (section is! Category) {
        continue;
      }
      for (final app in section.applications) {
        if (!app.hidden && seen.add(app.packageName)) {
          entries.add((app: app, category: section));
        }
      }
    }
    return entries;
  }
}

class _DesktopIcon extends StatelessWidget {
  final App app;
  final Category category;
  final FocusNode? focusNode;
  final bool autofocus;

  const _DesktopIcon({
    super.key,
    required this.app,
    required this.category,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => XpPressable(
    focusNode: focusNode,
    autofocus: autofocus,
    ensureVisibleAlignment: 0.3,
    onPressed: () => launchXpApp(context, app),
    onMenu: () => showAppContextMenu(context, app, category: category),
    builder: (context, focused) => SizedBox(
      width: 100,
      height: 92,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: focused ? const Color(0x80316AC5) : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: AppIcon(app.packageName, size: 46),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: focused
                ? BoxDecoration(
                    color: XpColors.selection,
                    border: Border.all(color: const Color(0xFFFFF3B0), width: 1),
                  )
                : null,
            child: Text(app.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.15,
                shadows: focused ? null : xpTextShadow,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
