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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/xp/xp_style.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

const accessibilitySettingsAction = "android.settings.ACCESSIBILITY_SETTINGS";

/// XP's "Turn off computer" box: Stand By, Turn Off and Restart.
Future<void> showTurnOffDialog(BuildContext context) => showXpDialog(context, const _TurnOffDialog());

class _TurnOffDialog extends StatelessWidget
{
  const _TurnOffDialog();

  @override
  Widget build(BuildContext context) {
    final appsService = context.read<AppsService>();

    Future<void> standBy() async {
      Navigator.of(context).pop();
      await appsService.standBy();
    }

    Future<void> powerMenu() async {
      Navigator.of(context).pop();
      if (!await appsService.showPowerDialog()) {
        if (context.mounted) {
          await showHomeServiceHelp(context, reason: "Turning off or restarting the TV from here");
        }
      }
    }

    return Container(
      width: 440,
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(3, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 52,
            color: const Color(0xFF00309C),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: const Text("Turn off computer",
              style: TextStyle(color: Colors.white, fontSize: 20, shadows: xpTextShadow),
            ),
          ),
          Container(height: 2, color: XpColors.orangeLine),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7BA2E7), Color(0xFF5A82D6), Color(0xFF4062C2)],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PowerButton(
                  label: "Stand By",
                  icon: Icons.nightlight_round,
                  colors: const [Color(0xFFFFE27A), Color(0xFFE0A81A)],
                  onPressed: standBy,
                  autofocus: true,
                ),
                _PowerButton(
                  label: "Turn Off",
                  icon: Icons.power_settings_new,
                  colors: const [Color(0xFFF58C6C), Color(0xFFC9300F)],
                  onPressed: powerMenu,
                ),
                _PowerButton(
                  label: "Restart",
                  icon: Icons.restart_alt,
                  colors: const [Color(0xFF8BD67A), Color(0xFF2F9A1B)],
                  onPressed: powerMenu,
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFF00309C),
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerRight,
            child: XpButton(label: "Cancel", onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget
{
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onPressed;
  final bool autofocus;

  const _PowerButton({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => XpPressable(
    autofocus: autofocus,
    onPressed: onPressed,
    builder: (context, focused) => Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: focused ? 3 : 1.5),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            boxShadow: focused ? const [BoxShadow(color: Color(0xAAFFFFFF), blurRadius: 10)] : null,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 8),
        Text(label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: focused ? FontWeight.bold : FontWeight.normal,
            shadows: xpTextShadow,
          ),
        ),
      ],
    ),
  );
}

/// Explains how to turn on the accessibility service that powers the Home button
/// override and the power buttons.
Future<void> showHomeServiceHelp(BuildContext context, {String reason = "The Home button override"}) =>
    showXpDialog(context, Builder(
      builder: (context) => XpWindow(
        title: "Home button service",
        icon: Icons.accessibility_new,
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("$reason needs the \"Wack XP Home button\" service. Turn it on under "
                  "Settings > Device Preferences > Accessibility.\n\n"
                  "Or run this from your PC:\n"
                  "adb shell settings put secure enabled_accessibility_services "
                  "com.wack.tvlauncher/me.efesser.flauncher.HomeButtonService\n"
                  "adb shell settings put secure accessibility_enabled 1"),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  XpButton(
                    label: "Open Accessibility settings",
                    autofocus: true,
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.read<AppsService>().launchActivityFromAction(accessibilitySettingsAction);
                    },
                  ),
                  const SizedBox(width: 8),
                  XpButton(label: "Later", onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    ));

Future<void> showHelpAndSupport(BuildContext context) => showXpDialog(context, Builder(
  builder: (context) => XpWindow(
    title: "Help and Support Center",
    icon: Icons.help_outline,
    width: 600,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Using Wack XP with your remote",
            style: TextStyle(color: XpColors.textBlue, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const _HelpLine(Icons.touch_app, "OK", "Open the selected app or item."),
          const _HelpLine(Icons.back_hand_outlined, "Hold OK", "Options for an app: pin it to the Start menu or taskbar, move it, hide it, see its properties or uninstall it."),
          const _HelpLine(Icons.menu, "Menu", "The same options as holding OK. Anywhere else, Menu opens the Start menu."),
          const _HelpLine(Icons.home_outlined, "Home", "Always comes back here, closing whatever is open."),
          const _HelpLine(Icons.arrow_back, "Back", "Closes the Start menu or the current window."),
          const _HelpLine(Icons.apps, "All Programs", "Every installed app, including hidden ones. Hold OK on a hidden app to show it on the desktop again."),
          const _HelpLine(Icons.settings_input_hdmi, "TV Inputs", "Switch to HDMI and other inputs from the Start menu."),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: XpButton(label: "OK", autofocus: true, onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    ),
  ),
));

class _HelpLine extends StatelessWidget
{
  final IconData icon;
  final String keyName;
  final String text;

  const _HelpLine(this.icon, this.keyName, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: XpColors.textBlue),
        const SizedBox(width: 8),
        SizedBox(width: 110, child: Text(keyName, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

Future<void> showAboutWackXp(BuildContext context) => showXpDialog(context, Builder(
  builder: (context) => XpWindow(
    title: "About Wack XP",
    icon: Icons.info_outline,
    width: 520,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              WackLogo(size: 44),
              SizedBox(width: 12),
              Text.rich(TextSpan(children: [
                TextSpan(text: "Wack ", style: TextStyle(fontSize: 26, color: XpColors.textDark)),
                TextSpan(text: "XP", style: TextStyle(fontSize: 26, color: Color(0xFFE5631F), fontWeight: FontWeight.bold)),
                TextSpan(text: "\nTV Edition", style: TextStyle(fontSize: 14, color: XpColors.textGrey)),
              ])),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => Text("Version ${snapshot.data?.version ?? ""}"),
          ),
          const SizedBox(height: 8),
          const Text("A Windows XP style home screen for Android TV, built on FLauncher.\n"
              "FLauncher is © Étienne Fesser, Oscar Rojas and contributors, and is free software "
              "under the GNU General Public License v3.0. So is Wack XP.\n\n"
              "Not affiliated with Microsoft. Windows and Windows XP are trademarks of Microsoft Corporation."),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: XpButton(label: "OK", autofocus: true, onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    ),
  ),
));

/// The Wack XP badge: a glossy orb with a "W", used on the Start button and in About.
class WackLogo extends StatelessWidget
{
  final double size;

  const WackLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: size * 0.06),
      gradient: const RadialGradient(
        center: Alignment(-0.4, -0.5),
        colors: [Color(0xFFFFD27A), Color(0xFFF08A24), Color(0xFFC4500C)],
        stops: [0, 0.55, 1],
      ),
      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(1, 1))],
    ),
    child: Text("W",
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.52,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        height: 1,
        shadows: xpTextShadow,
      ),
    ),
  );
}
