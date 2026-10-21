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

/// The launcher doesn't show itself on its own desktop.
const _ownPackageName = "com.wack.tvlauncher";

const double _iconHeight = 92;
const double _iconSpacing = 6;

/// The Windows XP style home screen: wallpaper, desktop icons, taskbar and Start menu.
class FLauncher extends StatefulWidget {
  const FLauncher();

  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> {
  // One node per app, kept across rebuilds so an icon stays selected while it's moved around.
  final Map<String, FocusNode> _iconFocusNodes = {};
  final FocusNode _startButtonFocusNode = FocusNode(debugLabel: "start button");
  String? _firstIconPackage;
  String? _movingPackage;

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
    for (final node in _iconFocusNodes.values) {
      node.dispose();
    }
    _startButtonFocusNode.dispose();
    super.dispose();
  }

  void _onLauncherStateChanged() {
    if (_launcherState.homePressedCount != _homePressedCount) {
      _homePressedCount = _launcherState.homePressedCount;
      _startMenuOpen = _launcherState.startMenuOpen;
      _movingPackage = null;
      _focusAfterFrame(() {
        final firstIcon = _iconFocusNodes[_firstIconPackage];
        return firstIcon != null && firstIcon.context != null ? firstIcon : _startButtonFocusNode;
      });
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
      _firstIconPackage = entries.isEmpty ? null : entries.first.app.packageName;

      return LayoutBuilder(
        builder: (context, constraints) {
          // Icons flow top to bottom, so moving left or right jumps a whole column.
          final int iconsPerColumn = ((constraints.maxHeight - 12 + _iconSpacing) ~/ (_iconHeight + _iconSpacing)).clamp(1, 1000);

          return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SizedBox(
            height: constraints.maxHeight - 12,
            child: Wrap(
              direction: Axis.vertical,
              spacing: _iconSpacing,
              runSpacing: 10,
              children: [
                for (int i = 0; i < entries.length; i++)
                  _DesktopIcon(
                    key: ValueKey(entries[i].app.packageName),
                    app: entries[i].app,
                    category: entries[i].category,
                    focusNode: _iconFocusNodes.putIfAbsent(entries[i].app.packageName,
                        () => FocusNode(debugLabel: entries[i].app.packageName)),
                    autofocus: i == 0,
                    moving: _movingPackage == entries[i].app.packageName,
                    onStartMove: () => setState(() => _movingPackage = entries[i].app.packageName),
                    onMove: (steps) => _moveIcon(appsService, entries[i].app, entries[i].category, steps, iconsPerColumn),
                    onEndMove: () => _endMove(appsService, entries[i].category),
                  ),
              ],
            ),
          ),
          );
        },
      );
    },
  );

  /// [steps] is -1/+1 for up/down, or -2/+2 for left/right (a whole column).
  void _moveIcon(AppsService appsService, App app, Category category, int steps, int iconsPerColumn) {
    final applications = category.applications;
    final int oldIndex = applications.indexWhere((application) => application.packageName == app.packageName);
    if (oldIndex < 0) {
      return;
    }

    final int delta = steps.abs() == 2 ? steps.sign * iconsPerColumn : steps;
    final int newIndex = (oldIndex + delta).clamp(0, applications.length - 1);
    if (newIndex != oldIndex) {
      appsService.reorderApplication(category, oldIndex, newIndex);
    }
  }

  void _endMove(AppsService appsService, Category category) {
    setState(() => _movingPackage = null);
    appsService.saveApplicationOrderInCategory(category);
  }

  /// Every app on the launcher's groups, in group order, each shown once.
  static List<({App app, Category category})> _desktopApps(AppsService appsService) {
    final seen = <String>{};
    final entries = <({App app, Category category})>[];

    for (final section in appsService.launcherSections) {
      if (section is! Category) {
        continue;
      }
      for (final app in section.applications) {
        if (app.packageName == _ownPackageName) {
          continue;
        }
        if (!app.hidden && seen.add(app.packageName)) {
          entries.add((app: app, category: section));
        }
      }
    }
    return entries;
  }
}

class _DesktopIcon extends StatelessWidget {
  static final _moveKeys = {
    LogicalKeyboardKey.arrowUp: -1,
    LogicalKeyboardKey.arrowDown: 1,
    LogicalKeyboardKey.arrowLeft: -2,
    LogicalKeyboardKey.arrowRight: 2,
  };

  final App app;
  final Category category;
  final FocusNode focusNode;
  final bool autofocus;
  final bool moving;
  final VoidCallback onStartMove;
  final void Function(int steps) onMove;
  final VoidCallback onEndMove;

  const _DesktopIcon({
    super.key,
    required this.app,
    required this.category,
    required this.focusNode,
    required this.moving,
    required this.onStartMove,
    required this.onMove,
    required this.onEndMove,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    // While moving, the arrows slide the icon instead of changing the selection,
    // and Back drops it where it is.
    onKeyEvent: (_, event) {
      if (!moving) {
        return KeyEventResult.ignored;
      }
      final int? steps = _moveKeys[event.logicalKey];
      if (steps != null) {
        if (event is! KeyUpEvent) {
          onMove(steps);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.goBack || event.logicalKey == LogicalKeyboardKey.escape) {
        if (event is KeyDownEvent) {
          onEndMove();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: XpPressable(
      focusNode: focusNode,
      autofocus: autofocus,
      ensureVisibleAlignment: 0.3,
      onPressed: () => moving ? onEndMove() : launchXpApp(context, app),
      onMenu: () async {
        if (moving) {
          onEndMove();
          return;
        }
        final result = await showAppContextMenu(context, app, category: category);
        if (result == AppContextMenuResult.move) {
          onStartMove();
        }
      },
      builder: (context, focused) => SizedBox(
        width: 100,
        height: _iconHeight,
        child: Stack(
          // Expand so every icon is centred in the same fixed-width slot, whatever its label's width
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: focused || moving ? const Color(0xB3316AC5) : null,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: moving
                          ? XpColors.orangeLine
                          : focused ? const Color(0xFFFFF3B0) : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: AppIcon(app.packageName, size: 46),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: focused || moving
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
                      shadows: focused || moving ? null : xpTextShadow,
                    ),
                  ),
                ),
              ],
            ),
            if (moving)
              const Positioned(
                top: -6,
                right: 6,
                child: Icon(Icons.open_with, color: Colors.white, size: 22, shadows: xpTextShadow),
              ),
          ],
        ),
      ),
    ),
  );
}
