# Wack XP

A Windows XP style home screen for Android TV, built on [FLauncher](https://gitlab.com/flauncher/flauncher) (via [osrosal/flauncher](https://github.com/osrosal/flauncher)). Made for a Philips Android TV, but it should work on any Android TV.

Not affiliated with Microsoft. The wallpaper and logo are original drawings in the XP style.

## What's on it

- **Desktop:** your apps as XP desktop icons over a green-hills wallpaper (or your own picture or gradient)
- **Taskbar:** green **start** button, pinned apps (Quick Launch), network status and clock
- **Start menu:**
  - Left: apps pinned to the Start menu, recently used apps, and **All Programs** (every app, including hidden ones)
  - Right: **My TV** (Live TV), **TV Inputs** (HDMI, AV...), **Control Panel** (Android settings), **Network Connections** (Wi-Fi), **Launcher Settings**, **Help and Support**, **About**
  - Bottom: **Log Off** (screensaver) and **Turn Off Computer** (Stand By, Turn Off, Restart)
- **App options:** hold OK, or press Menu, on any app to open it, pin it to the Start menu or taskbar, move it, add it to a group, hide it, open its properties, or uninstall it
- **Home button override:** an accessibility service makes the remote's Home button always come back to Wack XP, and reopens it if the stock home screen shows up. Both can be turned off in Launcher Settings.

## Remote

| Button | Does |
|---|---|
| OK | Open |
| Hold OK / Menu | App options. Menu anywhere else opens the Start menu |
| Home | Back to the desktop, closing anything open |
| Back | Close the Start menu or current window |

## Build

Every push to `master` builds a signed APK with GitHub Actions (**Actions** tab > latest run > `wack-xp` artifact). The signing key is kept in the repo's Actions secrets, not in the code.

## Install

```powershell
.\install.ps1
```

This downloads the latest build, installs it on the TV over ADB, disables the stock launcher, and turns on the Home button service. Pass a path to install a specific APK: `.\install.ps1 C:\path\to\wack-xp.apk`.

## Undo

```powershell
adb -s 192.168.0.112:5555 shell settings put secure enabled_accessibility_services '""'
adb -s 192.168.0.112:5555 shell pm enable com.google.android.tvlauncher
adb -s 192.168.0.112:5555 uninstall com.wack.tvlauncher
```

## License

GPL-3.0, like FLauncher. See [LICENSE](LICENSE).
