# Downloads the latest Wack XP build from GitHub Actions, installs it on the TV
# and makes it the home screen.
# Usage: .\install.ps1                 (latest build from GitHub)
#        .\install.ps1 C:\path\to.apk  (a specific APK)
param([string]$Apk)

$tv = "192.168.0.112:5555"
$package = "com.wack.tvlauncher"
$service = "$package/me.efesser.flauncher.HomeButtonService"

if (-not $Apk) {
  $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
  if (-not $gh) { $gh = "C:\Program Files\GitHub CLI\gh.exe" }
  $dir = Join-Path $env:TEMP "wack-xp-build"
  Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
  Write-Host "Downloading the latest build..."
  & $gh run download --repo wackzilla/wack-tv-launcher --name wack-xp --dir $dir
  if ($LASTEXITCODE -ne 0) { Write-Host "Download failed." -ForegroundColor Yellow; exit 1 }
  $Apk = Join-Path $dir "wack-xp.apk"
}

adb connect $tv

Write-Host "Installing -> " -NoNewline
$result = adb -s $tv install -r $Apk 2>&1 | Out-String
if ($result -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
  # The old Java launcher used a different signing key, so it has to be removed first.
  Write-Host "Replacing the old launcher (different signing key) -> " -NoNewline
  adb -s $tv uninstall $package
  $result = adb -s $tv install $Apk 2>&1 | Out-String
}
Write-Host $result

$installed = adb -s $tv shell pm list packages $package
if ($installed -match "package:$package") {
  Write-Host "Disabling stock launcher -> " -NoNewline
  adb -s $tv shell pm disable-user --user 0 com.google.android.tvlauncher
  Write-Host "Turning on the Home button service"
  adb -s $tv shell settings put secure enabled_accessibility_services $service
  adb -s $tv shell settings put secure accessibility_enabled 1
  adb -s $tv shell input keyevent KEYCODE_HOME
} else {
  Write-Host "Install failed. Stock launcher left alone." -ForegroundColor Yellow
}

# To go back to the stock home screen:
#   adb -s 192.168.0.112:5555 shell settings put secure enabled_accessibility_services '""'
#   adb -s 192.168.0.112:5555 shell pm enable com.google.android.tvlauncher
