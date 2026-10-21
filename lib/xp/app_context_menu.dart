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
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/add_to_category_dialog.dart';
import 'package:flauncher/xp/app_icon.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens [app] and remembers it in the Start menu's recently used list.
Future<void> launchXpApp(BuildContext context, App app) async {
  final appsService = context.read<AppsService>();
  final settingsService = context.read<SettingsService>();
  context.read<LauncherState>().setStartMenuOpen(false);

  await appsService.launchApp(app);
  await settingsService.addRecentApp(app.packageName);
}

/// What the app menu asks its caller to do once it closes.
enum AppContextMenuResult { move }

/// The menu shown when OK is held, or Menu is pressed, on an app. [category] is the
/// desktop group the app was picked from, if any.
Future<AppContextMenuResult?> showAppContextMenu(BuildContext context, App app, {Category? category}) =>
    showXpDialog<AppContextMenuResult>(context, _AppContextMenu(app: app, category: category));

class _AppContextMenu extends StatelessWidget
{
  final App app;
  final Category? category;

  const _AppContextMenu({required this.app, required this.category});

  @override
  Widget build(BuildContext context) {
    final appsService = context.read<AppsService>();
    final settingsService = context.watch<SettingsService>();
    final bool onStartMenu = settingsService.startMenuPinned.contains(app.packageName);
    final bool onTaskbar = settingsService.taskbarPinned.contains(app.packageName);
    final bool canMove = category != null && category!.sort == CategorySort.manual;

    void close() => Navigator.of(context).pop();

    return Container(
      width: 300,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFACA899)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(3, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                AppIcon(app.packageName, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: XpColors.textBlue, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const XpMenuSeparator(),
          XpMenuItem(
            label: "Open",
            bold: true,
            autofocus: true,
            onPressed: () {
              close();
              launchXpApp(context, app);
            },
          ),
          const XpMenuSeparator(),
          XpMenuItem(
            label: onStartMenu ? "Unpin from Start menu" : "Pin to Start menu",
            icon: Icons.push_pin_outlined,
            onPressed: () {
              settingsService.toggleStartMenuPin(app.packageName);
              close();
            },
          ),
          XpMenuItem(
            label: onTaskbar ? "Unpin from Taskbar" : "Pin to Taskbar",
            icon: Icons.view_day_outlined,
            onPressed: () {
              settingsService.toggleTaskbarPin(app.packageName);
              close();
            },
          ),
          if (canMove) ...[
            XpMenuItem(
              label: "Move",
              icon: Icons.open_with,
              onPressed: () => Navigator.of(context).pop(AppContextMenuResult.move),
            ),
            XpMenuItem(
              label: "Move to front",
              icon: Icons.first_page,
              onPressed: () {
                appsService.moveInCategory(app, category!, toFront: true);
                close();
              },
            ),
            XpMenuItem(
              label: "Move to back",
              icon: Icons.last_page,
              onPressed: () {
                appsService.moveInCategory(app, category!, toFront: false);
                close();
              },
            ),
          ],
          const XpMenuSeparator(),
          XpMenuItem(
            label: "Add to group...",
            icon: Icons.create_new_folder_outlined,
            onPressed: () {
              close();
              showDialog(context: context, builder: (_) => AddToCategoryDialog(app));
            },
          ),
          if (category != null)
            XpMenuItem(
              label: "Remove from ${category!.name}",
              icon: Icons.folder_off_outlined,
              onPressed: () {
                appsService.removeFromCategory(app, category!);
                close();
              },
            ),
          XpMenuItem(
            label: app.hidden ? "Show on desktop" : "Hide from desktop",
            icon: app.hidden ? Icons.visibility : Icons.visibility_off_outlined,
            onPressed: () {
              if (app.hidden) {
                appsService.showApplication(app);
              } else {
                appsService.hideApplication(app);
              }
              close();
            },
          ),
          const XpMenuSeparator(),
          XpMenuItem(
            label: "Properties",
            icon: Icons.info_outline,
            onPressed: () {
              close();
              appsService.openAppInfo(app);
            },
          ),
          XpMenuItem(
            label: "Delete (uninstall)",
            icon: Icons.delete_outline,
            onPressed: () {
              close();
              appsService.uninstallApp(app);
            },
          ),
        ],
      ),
    );
  }
}

/// A row in an XP pop-up menu: highlighted in blue when focused.
class XpMenuItem extends StatelessWidget
{
  final String label;
  final IconData? icon;
  final bool bold;
  final bool autofocus;
  final VoidCallback onPressed;

  const XpMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.bold = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => XpPressable(
    autofocus: autofocus,
    onPressed: onPressed,
    builder: (context, focused) => Container(
      color: focused ? XpColors.menuHover : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: icon == null ? null : Icon(icon, size: 16, color: focused ? Colors.white : XpColors.textBlue),
          ),
          Expanded(
            child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: focused ? Colors.white : XpColors.textDark,
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class XpMenuSeparator extends StatelessWidget
{
  const XpMenuSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
    color: const Color(0xFFACA899),
  );
}
