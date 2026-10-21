# Downloads the latest Wack XP build from GitHub Actions, installs it on a TV
# and makes it the home screen.
# Usage: .\install.ps1                          (latest build, office onn box)
#        .\install.ps1 -Tv 192.168.0.112:5555   (another device, e.g. the Philips TV)
#        .\install.ps1 C:\path\to\wack-xp.apk   (a specific APK)
param([string]$Apk, [string]$Tv = "192.168.0.109:5555")

$package = "com.wack.tvlauncher"
$activity = "$package/me.efesser.flauncher.MainActivity"
$service = "$package/me.efesser.flauncher.HomeButtonService"
$stockHomes = @("com.google.android.tvlauncher", "com.google.android.apps.tv.launcherx")

if (-not $Apk) {
  $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
  if (-not $gh) { $gh = "C:\Program Files\GitHub CLI\gh.exe" }
  $dir = Join-Path $env:TEMP "wack-xp-build"
  Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
  # Without a run id, gh can pick an older run's artifact, so ask for the newest successful build.
  $run = & $gh run list --repo wackzilla/wack-tv-launcher --workflow build.yml --branch master --status success --limit 1 --json databaseId,headSha --jq '.[0] | "\(.databaseId) \(.headSha[0:7])"'
  if (-not $run) { Write-Host "No successful build found." -ForegroundColor Yellow; exit 1 }
  $runId, $commit = $run -split " "
  Write-Host "Downloading build $runId (commit $commit)..."
  & $gh run download $runId --repo wackzilla/wack-tv-launcher --name wack-xp --dir $dir
  if ($LASTEXITCODE -ne 0) { Write-Host "Download failed." -ForegroundColor Yellow; exit 1 }
  $Apk = Join-Path $dir "wack-xp.apk"
}

adb connect $Tv | Out-Null
if ((adb -s $Tv get-state 2>&1) -ne "device") {
  Write-Host "Can't reach $Tv over ADB." -ForegroundColor Yellow
  exit 1
}

Write-Host "Installing on $Tv..."
$result = adb -s $Tv install -r $Apk 2>&1 | Out-String
if ($result -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
  # The old Java launcher used a different signing key, so it has to be removed first.
  Write-Host "Replacing the old launcher (different signing key)..."
  adb -s $Tv uninstall $package | Out-Null
  $result = adb -s $Tv install $Apk 2>&1 | Out-String
}
Write-Host $result.Trim()

$installed = adb -s $Tv shell pm list packages $package
if ($installed -notmatch "package:$package") {
  Write-Host "Install failed. Home screen left alone." -ForegroundColor Yellow
  exit 1
}

$previousServices = adb -s $Tv shell settings get secure enabled_accessibility_services
if ($previousServices -and $previousServices -ne "null" -and $previousServices -notmatch [regex]::Escape($service)) {
  Write-Host "Turning off other Home button services: $previousServices"
}

Write-Host "Making Wack XP the home screen"
adb -s $Tv shell cmd package set-home-activity $activity | Out-Null

foreach ($stock in $stockHomes) {
  $state = adb -s $Tv shell pm list packages -e $stock
  if ("$state".Trim() -eq "package:$stock") {
    Write-Host "Disabling stock launcher $stock"
    adb -s $Tv shell pm disable-user --user 0 $stock | Out-Null
  }
}

Write-Host "Turning on the Wack XP Home button service"
adb -s $Tv shell settings put secure enabled_accessibility_services $service
adb -s $Tv shell settings put secure accessibility_enabled 1
adb -s $Tv shell input keyevent KEYCODE_HOME

# To undo:
#   adb -s <tv> shell settings put secure enabled_accessibility_services <previous service, or '""'>
#   adb -s <tv> shell cmd package set-home-activity <previous launcher activity>
#   adb -s <tv> uninstall com.wack.tvlauncher
# On the office onn box, Projectivy was the previous launcher:
#   adb -s 192.168.0.109:5555 shell settings put secure enabled_accessibility_services com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
#   adb -s 192.168.0.109:5555 shell cmd package set-home-activity com.spocky.projengmenu/.ui.home.MainActivity
