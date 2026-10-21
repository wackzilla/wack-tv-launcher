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

import 'dart:async';

import 'package:flauncher/widgets/settings/back_button_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appHighlightAnimationEnabledKey = "app_highlight_animation_enabled";
const _appKeyClickEnabledKey = "app_key_click_enabled";
const _autoHideAppBar = "auto_hide_app_bar";
const _gradientUuidKey = "gradient_uuid";
const _backButtonAction = "back_button_action";
const _dateFormat = "date_format";
const _showCategoryTitles = "show_category_titles";
const _showDateInStatusBar = "show_date_in_status_bar";
const _showTimeInStatusBar = "show_time_in_status_bar";
const _timeFormat = "time_format";
// Read by HomeButtonService on the Android side as "flutter.override_home" and
// "flutter.guard_stock_launcher", so don't rename them.
const _overrideHome = "override_home";
const _guardStockLauncher = "guard_stock_launcher";
const _startMenuPinned = "start_menu_pinned";
const _taskbarPinned = "taskbar_pinned";
const _recentApps = "recent_apps";
const _userName = "user_name";

const _maxRecentApps = 6;

class SettingsService extends ChangeNotifier {
  static final defaultDateFormat = "EEEE d";
  // XP's taskbar clock was 12-hour, like "5:02 PM"
  static final defaultTimeFormat = "h:mm a";
  final SharedPreferences _sharedPreferences;


  bool get appHighlightAnimationEnabled => _sharedPreferences.getBool(_appHighlightAnimationEnabledKey) ?? true;

  bool get appKeyClickEnabled => _sharedPreferences.getBool(_appKeyClickEnabledKey) ?? true;

  bool get autoHideAppBarEnabled => _sharedPreferences.getBool(_autoHideAppBar) ?? false;

  bool get showCategoryTitles => _sharedPreferences.getBool(_showCategoryTitles) ?? true;

  bool get showDateInStatusBar => _sharedPreferences.getBool(_showDateInStatusBar) ?? true;

  bool get showTimeInStatusBar => _sharedPreferences.getBool(_showTimeInStatusBar) ?? true;

  String? get gradientUuid => _sharedPreferences.getString(_gradientUuidKey);

  String get backButtonAction => _sharedPreferences.getString(_backButtonAction) ?? BACK_BUTTON_ACTION_NOTHING;

  String get dateFormat => _sharedPreferences.getString(_dateFormat) ?? defaultDateFormat;

  String get timeFormat => _sharedPreferences.getString(_timeFormat) ?? defaultTimeFormat;

  bool get overrideHome => _sharedPreferences.getBool(_overrideHome) ?? true;

  bool get guardStockLauncher => _sharedPreferences.getBool(_guardStockLauncher) ?? true;

  List<String> get startMenuPinned => _sharedPreferences.getStringList(_startMenuPinned) ?? const [];

  List<String> get taskbarPinned => _sharedPreferences.getStringList(_taskbarPinned) ?? const [];

  List<String> get recentApps => _sharedPreferences.getStringList(_recentApps) ?? const [];

  String get userName => _sharedPreferences.getString(_userName) ?? "Wack";

  SettingsService(
    this._sharedPreferences
  );

  Future<void> setOverrideHome(bool value) async {
    return set(_overrideHome, value);
  }

  Future<void> setGuardStockLauncher(bool value) async {
    return set(_guardStockLauncher, value);
  }

  Future<void> setUserName(String value) async {
    await _sharedPreferences.setString(_userName, value);
    notifyListeners();
  }

  Future<void> toggleStartMenuPin(String packageName) =>
      _toggleInList(_startMenuPinned, startMenuPinned, packageName);

  Future<void> toggleTaskbarPin(String packageName) =>
      _toggleInList(_taskbarPinned, taskbarPinned, packageName);

  Future<void> addRecentApp(String packageName) async {
    List<String> recent = List.of(recentApps)
      ..remove(packageName)
      ..insert(0, packageName);
    if (recent.length > _maxRecentApps) {
      recent = recent.sublist(0, _maxRecentApps);
    }

    await _sharedPreferences.setStringList(_recentApps, recent);
    notifyListeners();
  }

  Future<void> _toggleInList(String key, List<String> current, String packageName) async {
    List<String> list = List.of(current);
    if (!list.remove(packageName)) {
      list.add(packageName);
    }

    await _sharedPreferences.setStringList(key, list);
    notifyListeners();
  }

  Future<void> set(String key, bool value) async {
    await _sharedPreferences.setBool(key, value);
    notifyListeners();
  }

  Future<void> setAppHighlightAnimationEnabled(bool value) async {
    return set(_appHighlightAnimationEnabledKey, value);
  }

  Future<void> setAppKeyClickEnabled(bool value) async {
    return set(_appKeyClickEnabledKey, value);
  }

  Future<void> setAutoHideAppBarEnabled(bool value) async {
    return set(_autoHideAppBar, value);
  }

  Future<void> setGradientUuid(String value) async {
    await _sharedPreferences.setString(_gradientUuidKey, value);
    notifyListeners();
  }

  Future<void> clearGradientUuid() async {
    await _sharedPreferences.remove(_gradientUuidKey);
    notifyListeners();
  }

  Future<void> setBackButtonAction(String value) async {
    await _sharedPreferences.setString(_backButtonAction, value);
    notifyListeners();
  }

  Future<void> setDateTimeFormat(String dateFormatString, String timeFormatString) async {
    await Future.wait([
      _sharedPreferences.setString(_dateFormat, dateFormatString),
      _sharedPreferences.setString(_timeFormat, timeFormatString)
    ]);
    notifyListeners();
  }

  Future<void> setShowCategoryTitles(bool show) async {
    return set(_showCategoryTitles, show);
  }

  Future<void> setShowDateInStatusBar(bool show) async {
    return set(_showDateInStatusBar, show);
  }

  Future<void> setShowTimeInStatusBar(bool show) async {
    return set(_showTimeInStatusBar, show);
  }
}
