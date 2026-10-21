/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../widgets/settings/back_button_actions.dart';
import 'apps_service.dart';

class LauncherState extends ChangeNotifier
{
  /// Lets the Home button close any dialog or menu that's open on top of the desktop.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _isDefaultLauncher;
  bool _launcherVisible;
  bool _startMenuOpen;
  int _homePressedCount;

  bool  get isDefaultLauncher => _isDefaultLauncher;
  bool  get launcherVisible => _launcherVisible;
  bool  get startMenuOpen => _startMenuOpen;

  /// Increases every time the Home button is pressed, so the desktop knows to take focus back.
  int   get homePressedCount => _homePressedCount;

  LauncherState() :
    _isDefaultLauncher = false,
    _launcherVisible = true,
    _startMenuOpen = false,
    _homePressedCount = 0;

  void toggleLauncherVisibility() {
    _launcherVisible = !_launcherVisible;
    notifyListeners();
  }

  void setStartMenuOpen(bool open) {
    if (_startMenuOpen != open) {
      _startMenuOpen = open;
      notifyListeners();
    }
  }

  void toggleStartMenu() => setStartMenuOpen(!_startMenuOpen);

  void goHome() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _startMenuOpen = false;
    _launcherVisible = true;
    _homePressedCount++;
    notifyListeners();
  }

  Future<void> refresh(AppsService appsService) async {
    _isDefaultLauncher = await appsService.isDefaultLauncher();
    notifyListeners();
  }

  void handleBackNavigation(BuildContext context) {
    AppsService appsService = context.read<AppsService>();
    LauncherState launcherState = context.read<LauncherState>();
    SettingsService settingsService = context.read<SettingsService>();

    if (launcherState.startMenuOpen) {
      launcherState.setStartMenuOpen(false);
      return;
    }

    // This is the home screen, even when the Home button service (rather than Android's
    // default launcher setting) is what keeps it there, so Back never closes it.
    launcherState.refresh(appsService);
    String action = settingsService.backButtonAction;

    switch (action) {
      case BACK_BUTTON_ACTION_CLOCK:
        launcherState.toggleLauncherVisibility();
        break;
      case BACK_BUTTON_ACTION_SCREENSAVER:
        appsService.startAmbientMode();
        break;
    }
  }
}