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

import 'dart:ui' as ui;

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/scenic/photo_background.dart';
import 'package:flauncher/scenic/scenic_menu.dart';
import 'package:flauncher/scenic/weather_panel.dart';
import 'package:flauncher/widgets/date_time_widget.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/widgets/network_widget.dart';
import 'package:flauncher/xp/app_context_menu.dart';
import 'package:flauncher/xp/app_icon.dart';
import 'package:flauncher/xp/xp_dialogs.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _wifiSettingsAction = "android.settings.WIFI_SETTINGS";

const _rowItemWidth = 104.0;
const _rowItemSpacing = 4.0;
const _itemsPerRow = 8;
const _rowsMaxHeight = 188.0;

const _infoBoxInset = 110.0;
const _clockTop = 160.0;
// Clear of the dock once the app rows have pushed it up.
const _clockTopRaised = 62.0;
const _weatherOffset = 8.0;
const _infoBoxMove = Duration(milliseconds: 220);
// Lines the next photo button up with the middle of the weather box.
const _nextPhotoOffset = 44.0;

const _clockShadow = [Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 12)];

/// The Scenic home screen: rotating photos, clock, weather and a dock of pinned apps.
/// Pressing down from the dock reveals the rest of the apps.
class ScenicHome extends StatefulWidget
{
  const ScenicHome({super.key});

  @override
  State<ScenicHome> createState() => _ScenicHomeState();
}

class _ScenicHomeState extends State<ScenicHome>
{
  // One node per app, kept across rebuilds so an icon stays selected while it's moved around.
  final Map<String, FocusNode> _focusNodes = {};
  final FocusNode _settingsFocusNode = FocusNode(debugLabel: "settings button");
  final FocusNode _networkFocusNode = FocusNode(debugLabel: "network button");
  final FocusNode _nextPhotoFocusNode = FocusNode(debugLabel: "next photo button");
  final ValueNotifier<int> _nextPhoto = ValueNotifier(0);
  final ValueNotifier<String> _focusedAppName = ValueNotifier("");

  String? _firstDockPackage;
  String? _lastDockPackage;
  String? _firstRowPackage;
  String? _movingPackage;
  bool _rowsOpen = false;

  late final LauncherState _launcherState;
  late int _homePressedCount;
  late bool _menuOpen;

  @override
  void initState() {
    super.initState();
    _launcherState = context.read<LauncherState>();
    _homePressedCount = _launcherState.homePressedCount;
    _menuOpen = _launcherState.startMenuOpen;
    _launcherState.addListener(_onLauncherStateChanged);
  }

  @override
  void dispose() {
    _launcherState.removeListener(_onLauncherStateChanged);
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _settingsFocusNode.dispose();
    _networkFocusNode.dispose();
    _nextPhotoFocusNode.dispose();
    _nextPhoto.dispose();
    _focusedAppName.dispose();
    super.dispose();
  }

  void _onLauncherStateChanged() {
    if (_launcherState.homePressedCount != _homePressedCount) {
      _homePressedCount = _launcherState.homePressedCount;
      _menuOpen = _launcherState.startMenuOpen;
      _movingPackage = null;
      _nextPhoto.value++;
      setState(() => _rowsOpen = false);
      _focusAfterFrame(() => _focusNodes[_firstDockPackage] ?? _focusNodes[_firstRowPackage] ?? _settingsFocusNode);
    }
    else if (_menuOpen && !_launcherState.startMenuOpen) {
      // Closing the menu leaves the button that opens it selected.
      _menuOpen = false;
      _focusAfterFrame(() => _settingsFocusNode);
    }
    else {
      _menuOpen = _launcherState.startMenuOpen;
    }
  }

  void _focusAfterFrame(FocusNode Function() node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node().context != null) {
          node().requestFocus();
        }
      });

  FocusNode _nodeFor(String packageName) =>
      _focusNodes.putIfAbsent(packageName, () => FocusNode(debugLabel: packageName));

  // With nothing pinned the rows are always open, so the boxes stay up out of their way.
  bool get _infoBoxesRaised => _rowsOpen || (_firstDockPackage == null && _firstRowPackage != null);

  void _openRows() {
    setState(() => _rowsOpen = true);
    _focusAfterFrame(() => _focusNodes[_firstRowPackage] ?? _settingsFocusNode);
  }

  void _closeRows() {
    final firstDock = _focusNodes[_firstDockPackage];
    if (firstDock != null) {
      firstDock.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      // Menu on anything that doesn't have its own menu opens the settings menu.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.contextMenu) {
        _launcherState.toggleStartMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoBackground(nextPhoto: _nextPhoto),
          Consumer<LauncherState>(
            builder: (context, state, _) {
              if (!state.launcherVisible) {
                return const Center(child: AlternativeLauncherView());
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedPositioned(
                    duration: _infoBoxMove,
                    curve: Curves.easeOut,
                    right: 12,
                    top: (_infoBoxesRaised ? _clockTopRaised : _clockTop) + _nextPhotoOffset,
                    child: ExcludeFocus(excluding: state.startMenuOpen, child: _nextPhotoButton()),
                  ),
                  AnimatedPositioned(
                    duration: _infoBoxMove,
                    curve: Curves.easeOut,
                    left: _infoBoxInset,
                    top: _infoBoxesRaised ? _clockTopRaised : _clockTop,
                    child: const _Clock(),
                  ),
                  AnimatedPositioned(
                    duration: _infoBoxMove,
                    curve: Curves.easeOut,
                    right: _infoBoxInset,
                    top: (_infoBoxesRaised ? _clockTopRaised : _clockTop) + _weatherOffset,
                    child: const WeatherPanel(),
                  ),
                  Positioned(
                    top: 20,
                    right: 28,
                    child: ExcludeFocus(excluding: state.startMenuOpen, child: _topButtons(context)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ExcludeFocus(excluding: state.startMenuOpen, child: _appsArea()),
                  ),
                  if (state.startMenuOpen)
                    const Positioned(top: 62, right: 28, bottom: 20, child: Align(alignment: Alignment.topRight, child: ScenicMenu())),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _nextPhotoButton() => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        (_focusNodes[_lastDockPackage] ?? _focusNodes[_firstRowPackage])?.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: _NextPhotoButton(
      focusNode: _nextPhotoFocusNode,
      onPressed: () => _nextPhoto.value++,
    ),
  );

  Widget _topButtons(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _RoundButton(
        focusNode: _networkFocusNode,
        onPressed: () => context.read<AppsService>().launchActivityFromAction(_wifiSettingsAction),
        child: const NetworkWidget(),
      ),
      const SizedBox(width: 10),
      _RoundButton(
        onPressed: () => showTurnOffDialog(context),
        child: const Icon(Icons.power_settings_new),
      ),
      const SizedBox(width: 10),
      _RoundButton(
        focusNode: _settingsFocusNode,
        onPressed: _launcherState.toggleStartMenu,
        child: const Icon(Icons.settings),
      ),
    ],
  );

  Widget _appsArea() => Consumer2<AppsService, SettingsService>(
    builder: (context, appsService, settingsService, _) {
      if (!appsService.initialized) {
        return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: Colors.white)));
      }

      final pinnedPackages = settingsService.taskbarPinned;
      final pinned = pinnedPackages.map(appsService.findApplication).whereType<App>().toList();
      final rows = appsService.desktopApps.where((entry) => !pinnedPackages.contains(entry.app.packageName)).toList();

      _firstDockPackage = pinned.isEmpty ? null : pinned.first.packageName;
      _lastDockPackage = pinned.isEmpty ? null : pinned.last.packageName;
      _firstRowPackage = rows.isEmpty ? null : rows.first.app.packageName;

      // With nothing pinned the dock can't hold the selection, so the rows stay open.
      final bool showRows = rows.isNotEmpty && (_rowsOpen || pinned.isEmpty);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: ValueListenableBuilder<String>(
              valueListenable: _focusedAppName,
              builder: (_, name, __) => Text(name,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500, shadows: _clockShadow),
              ),
            ),
          ),
          _dock(settingsService, pinned, rows.isNotEmpty),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: showRows
                ? _rows(appsService, rows, closeOnBlur: pinned.isNotEmpty)
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 20),
        ],
      );
    },
  );

  Widget _dock(SettingsService settingsService, List<App> pinned, bool hasRows) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown && hasRows && !_rowsOpen) {
        _openRows();
        return KeyEventResult.handled;
      }
      // Named here because the nearest thing in those directions depends on how many apps are pinned.
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _networkFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight && _focusNodes[_lastDockPackage]?.hasPrimaryFocus == true) {
        _nextPhotoFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Stack(
          children: [
            const Positioned.fill(child: _GlassPanel(radius: 18)),
            if (pinned.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Text("Hold OK on an app below and choose \"Pin to Dock\" to keep it here.",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // The selected icon grows out of the dock.
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < pinned.length; i++)
                      _DockIcon(
                        key: ValueKey(pinned[i].packageName),
                        app: pinned[i],
                        focusNode: _nodeFor(pinned[i].packageName),
                        autofocus: i == 0,
                        moving: _movingPackage == pinned[i].packageName,
                        focusedAppName: _focusedAppName,
                        onStartMove: () => setState(() => _movingPackage = pinned[i].packageName),
                        // Left and right move one place; up and down do nothing on a single row.
                        onMove: (steps) {
                          if (steps.abs() == 2) {
                            settingsService.moveTaskbarPin(pinned[i].packageName, steps.sign);
                          }
                        },
                        onEndMove: () => setState(() => _movingPackage = null),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _rows(AppsService appsService, List<({App app, Category category})> rows, {required bool closeOnBlur}) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      // A dialog taking focus isn't leaving: the selection comes back here when it closes.
      if (!hasFocus && closeOnBlur && ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _rowsOpen = false);
        _focusedAppName.value = "";
      }
    },
    onKeyEvent: (_, event) {
      if (closeOnBlur && (event.logicalKey == LogicalKeyboardKey.goBack || event.logicalKey == LogicalKeyboardKey.escape)) {
        if (event is KeyDownEvent) {
          _closeRows();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: SizedBox(
          width: 888,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              const Positioned.fill(child: _GlassPanel(radius: 18)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _rowsMaxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: _rowItemSpacing,
                    runSpacing: _rowItemSpacing,
                    children: [
                      for (int i = 0; i < rows.length; i++)
                        _RowIcon(
                          key: ValueKey(rows[i].app.packageName),
                          app: rows[i].app,
                          category: rows[i].category,
                          focusNode: _nodeFor(rows[i].app.packageName),
                          // Only when the dock is empty: otherwise it starts on the dock.
                          autofocus: i == 0 && !closeOnBlur,
                          moving: _movingPackage == rows[i].app.packageName,
                          onStartMove: () => setState(() => _movingPackage = rows[i].app.packageName),
                          onMove: (steps) => _moveRowApp(appsService, rows, i, steps),
                          onEndMove: () {
                            setState(() => _movingPackage = null);
                            appsService.saveApplicationOrderInCategory(rows[i].category);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// [steps] is -1/+1 for up/down (a whole row), or -2/+2 for left/right (one place). Pinned and
  /// hidden apps aren't shown here, so the move lands next to the app it visibly passes.
  void _moveRowApp(AppsService appsService, List<({App app, Category category})> rows, int index, int steps) {
    final int delta = steps.abs() == 1 ? steps * _itemsPerRow : steps.sign;
    final int targetIndex = (index + delta).clamp(0, rows.length - 1);
    final category = rows[index].category;
    if (targetIndex == index || rows[targetIndex].category != category) {
      return;
    }

    final applications = category.applications;
    final int oldIndex = applications.indexWhere((application) => application.packageName == rows[index].app.packageName);
    final int newIndex = applications.indexWhere((application) => application.packageName == rows[targetIndex].app.packageName);
    if (oldIndex >= 0 && newIndex >= 0) {
      appsService.reorderApplication(category, oldIndex, newIndex);
    }
  }
}

/// The same see-through dark glass as the clock and weather boxes.
class _GlassPanel extends StatelessWidget
{
  final double radius;

  const _GlassPanel({required this.radius});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: ScenicColors.darkGlassBlur, sigmaY: ScenicColors.darkGlassBlur),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ScenicColors.darkGlass,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: ScenicColors.glassBorder),
        ),
      ),
    ),
  );
}

class _Clock extends StatelessWidget
{
  const _Clock();

  @override
  Widget build(BuildContext context) => Selector<SettingsService, ({String timeFormat, bool showTime, bool showDate})>(
    selector: (_, settings) => (
      // The big clock leaves off AM/PM, but keeps the 12 or 24 hour choice.
      timeFormat: settings.timeFormat.replaceAll(RegExp(r"\s*a"), ""),
      showTime: settings.showTimeInStatusBar,
      showDate: settings.showDateInStatusBar,
    ),
    builder: (_, clock, __) => !clock.showDate && !clock.showTime ? const SizedBox.shrink() : ScenicDarkBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (clock.showDate)
            const DateTimeWidget("EEEE, MMMM d",
              updateInterval: Duration(minutes: 1),
              textStyle: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w400, shadows: _clockShadow),
            ),
          if (clock.showTime)
            DateTimeWidget(clock.timeFormat,
              key: ValueKey("scenic time ${clock.timeFormat}"),
              textStyle: const TextStyle(color: Colors.white, fontSize: 79, height: 1.1, fontWeight: FontWeight.w300, shadows: _clockShadow),
            ),
        ],
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget
{
  final Widget child;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  const _RoundButton({required this.child, required this.onPressed, this.focusNode});

  @override
  Widget build(BuildContext context) => XpPressable(
    focusNode: focusNode,
    onPressed: onPressed,
    builder: (context, focused) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: focused ? Colors.white : ScenicColors.glassStrong,
      ),
      child: IconTheme(
        data: IconThemeData(color: focused ? Colors.black87 : Colors.white, size: 18),
        child: child,
      ),
    ),
  );
}

/// Stays out of the way of the photo: barely visible until it's selected.
class _NextPhotoButton extends StatelessWidget
{
  final FocusNode focusNode;
  final VoidCallback onPressed;

  const _NextPhotoButton({required this.focusNode, required this.onPressed});

  @override
  Widget build(BuildContext context) => XpPressable(
    focusNode: focusNode,
    onPressed: onPressed,
    builder: (context, focused) => AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: focused ? 1 : 0.12,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xB3000000),
          border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 2),
        ),
        child: const Icon(Icons.chevron_right, color: Colors.white, size: 30),
      ),
    ),
  );
}

class _DockIcon extends StatelessWidget
{
  final App app;
  final FocusNode focusNode;
  final bool autofocus;
  final bool moving;
  final ValueNotifier<String> focusedAppName;
  final VoidCallback onStartMove;
  final void Function(int steps) onMove;
  final VoidCallback onEndMove;

  const _DockIcon({
    super.key,
    required this.app,
    required this.focusNode,
    required this.autofocus,
    required this.moving,
    required this.focusedAppName,
    required this.onStartMove,
    required this.onMove,
    required this.onEndMove,
  });

  @override
  Widget build(BuildContext context) => XpMoveKeys(
    moving: moving,
    onMove: onMove,
    onEndMove: onEndMove,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          focusedAppName.value = app.name;
        }
        else if (focusedAppName.value == app.name) {
          focusedAppName.value = "";
        }
      },
      child: XpPressable(
        focusNode: focusNode,
        autofocus: autofocus,
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
        builder: (context, focused) => AnimatedScale(
          scale: focused || moving ? 1.25 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: moving ? ScenicColors.accent : focused ? Colors.white : Colors.transparent,
                width: 2,
              ),
              boxShadow: focused || moving ? const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4))] : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AppIcon(app.packageName, size: 38),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RowIcon extends StatelessWidget
{
  final App app;
  final Category category;
  final FocusNode focusNode;
  final bool autofocus;
  final bool moving;
  final VoidCallback onStartMove;
  final void Function(int steps) onMove;
  final VoidCallback onEndMove;

  const _RowIcon({
    super.key,
    required this.app,
    required this.category,
    required this.focusNode,
    required this.autofocus,
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
      focusNode: focusNode,
      autofocus: autofocus,
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
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: _rowItemWidth,
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: focused || moving ? const Color(0x33FFFFFF) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: moving ? ScenicColors.accent : focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            AppIcon(app.packageName, size: 38),
            const SizedBox(height: 4),
            Text(app.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
