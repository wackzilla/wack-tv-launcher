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

import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colors of the Windows XP "Luna" (blue) theme.
class XpColors
{
  static const taskbarTop = Color(0xFF3F8CF3);
  static const taskbarMiddle = Color(0xFF245EDC);
  static const taskbarBottom = Color(0xFF1941A5);

  static const startGreenTop = Color(0xFF5EAC56);
  static const startGreen = Color(0xFF3C9D2F);
  static const startGreenBottom = Color(0xFF2E7F24);

  static const trayTop = Color(0xFF1290E8);
  static const tray = Color(0xFF0F7BD9);
  static const trayBorder = Color(0xFF0B5DB3);

  static const titleBarTop = Color(0xFF0997FF);
  static const titleBar = Color(0xFF0053EE);
  static const titleBarBottom = Color(0xFF0050EE);
  static const windowBorder = Color(0xFF0831D9);
  static const windowFace = Color(0xFFECE9D8);

  static const selection = Color(0xFF316AC5);
  static const menuHover = Color(0xFF316AC5);

  static const startMenuHeaderTop = Color(0xFF1868CE);
  static const startMenuHeaderBottom = Color(0xFF0E60CB);
  static const startMenuRight = Color(0xFFD3E5FA);
  static const startMenuRightBorder = Color(0xFF95BDEE);
  static const startMenuFooter = Color(0xFF1C55C8);
  static const orangeLine = Color(0xFFE59700);

  static const textDark = Color(0xFF000000);
  static const textBlue = Color(0xFF0B2F79);
  static const textGrey = Color(0xFF6D6D6D);
}

const xpTextShadow = [Shadow(color: Color(0xCC000000), offset: Offset(1, 1), blurRadius: 2)];

const _activateKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

/// A focusable item driven by the remote: OK presses it, holding OK long-presses it, and
/// the Menu key (or holding OK, when [onMenu] is set and [onLongPress] isn't) opens its menu.
class XpPressable extends StatefulWidget
{
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenu;
  final bool autofocus;
  final FocusNode? focusNode;
  final double ensureVisibleAlignment;

  const XpPressable({
    super.key,
    required this.builder,
    required this.onPressed,
    this.onLongPress,
    this.onMenu,
    this.autofocus = false,
    this.focusNode,
    this.ensureVisibleAlignment = 0.5,
  });

  @override
  State<XpPressable> createState() => _XpPressableState();
}

class _XpPressableState extends State<XpPressable>
{
  bool _focused = false;

  VoidCallback? get _longPress => widget.onLongPress ?? widget.onMenu;

  @override
  Widget build(BuildContext context) => FocusKeyboardListener(
    onPressed: (key) {
      if (_activateKeys.contains(key)) {
        widget.onPressed();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.contextMenu && widget.onMenu != null) {
        widget.onMenu!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    onLongPress: (_) {
      if (_longPress == null) {
        return KeyEventResult.ignored;
      }
      _longPress!();
      return KeyEventResult.handled;
    },
    builder: (context) => InkWell(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: widget.onPressed,
      onLongPress: _longPress,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(context,
            alignment: widget.ensureVisibleAlignment,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
          );
        }
      },
      child: widget.builder(context, _focused),
    ),
  );
}

/// An XP window: rounded blue title bar with the minimize/maximize/close buttons and a beige face.
class XpWindow extends StatelessWidget
{
  final String title;
  final IconData icon;
  final Widget child;
  final double width;

  const XpWindow({
    super.key,
    required this.title,
    required this.child,
    this.icon = Icons.desktop_windows,
    this.width = 520,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    decoration: BoxDecoration(
      color: XpColors.windowBorder,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(3, 4))],
    ),
    padding: const EdgeInsets.fromLTRB(3, 0, 3, 3),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [XpColors.titleBarTop, XpColors.titleBar, XpColors.titleBarBottom, XpColors.titleBar],
              stops: [0, 0.15, 0.85, 1],
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, shadows: xpTextShadow),
                ),
              ),
              const _TitleBarButton(icon: Icons.minimize),
              const SizedBox(width: 2),
              const _TitleBarButton(icon: Icons.crop_square),
              const SizedBox(width: 2),
              const _TitleBarButton(icon: Icons.close, close: true),
            ],
          ),
        ),
        Container(
          color: XpColors.windowFace,
          child: DefaultTextStyle(
            style: const TextStyle(color: XpColors.textDark, fontSize: 13),
            child: child,
          ),
        ),
      ],
    ),
  );
}

class _TitleBarButton extends StatelessWidget
{
  final IconData icon;
  final bool close;

  const _TitleBarButton({required this.icon, this.close = false});

  @override
  Widget build(BuildContext context) => Container(
    width: 21,
    height: 21,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: Colors.white, width: 1),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: close
            ? const [Color(0xFFE5866A), Color(0xFFC63C1A)]
            : const [Color(0xFF6E9CF5), Color(0xFF2257D5)],
      ),
    ),
    child: Icon(icon, size: 13, color: Colors.white),
  );
}

/// A classic grey-beige XP push button.
class XpButton extends StatelessWidget
{
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  const XpButton({super.key, required this.label, required this.onPressed, this.autofocus = false});

  @override
  Widget build(BuildContext context) => XpPressable(
    autofocus: autofocus,
    onPressed: onPressed,
    builder: (context, focused) => Container(
      constraints: const BoxConstraints(minWidth: 84),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFF003C74)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFECEBE6), Color(0xFFD6D0C5)],
        ),
        boxShadow: focused
            ? const [BoxShadow(color: Color(0xFFF8B330), spreadRadius: 2)]
            : null,
      ),
      child: Text(label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: XpColors.textDark, fontSize: 13),
      ),
    ),
  );
}

/// Shows [child] centered over the desktop, like an XP window that grabs focus.
Future<T?> showXpDialog<T>(BuildContext context, Widget child) => showDialog<T>(
  context: context,
  barrierColor: const Color(0x33000000),
  builder: (context) => Center(
    child: Material(type: MaterialType.transparency, child: child),
  ),
);
