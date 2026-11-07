# REDLINE FX (Flutter) - one-shot setup / check / build for Windows.
#   1. flutter create (adds android / ios / windows folders, keeps lib/ and test/)
#   2. Bluetooth permissions (Android manifest, iOS Info.plist), Windows window size / title
#   3. pub get -> analyze -> test -> build windows -> start the app
# Every step is written to setup-log.txt (UTF-8).
#   setup.ps1            full run
#   setup.ps1 -NoRun     do not start the app at the end
#   setup.ps1 -Android   also build a debug APK
param([switch]$NoRun, [switch]$Android)
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $PSScriptRoot
$log = Join-Path $PSScriptRoot 'setup-log.txt'
Set-Content -LiteralPath $log -Value "=== REDLINE FX setup $(Get-Date -Format s) ===" -Encoding UTF8

function Log([string]$s) { Write-Host $s; Add-Content -LiteralPath $log -Value $s -Encoding UTF8 }
function Run([string]$title, [string[]]$argv) {
  Log ""
  Log "### $title : flutter $($argv -join ' ')"
  & $script:flutter @argv 2>&1 | ForEach-Object { Log "$_" }
  $code = $LASTEXITCODE
  Log "### exit=$code"
  return $code
}

$script:flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $script:flutter) {
  foreach ($p in @("$env:USERPROFILE\development\flutter\bin\flutter.bat", "C:\flutter\bin\flutter.bat", "C:\src\flutter\bin\flutter.bat")) {
    if (Test-Path $p) { $script:flutter = $p; break }
  }
}
if (-not $script:flutter) { Log "ERROR: flutter not found (PATH)"; exit 1 }
Log "flutter: $script:flutter"

$dev = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
Log "developer mode: $dev"

$env:VSLANG = '1033'   # English compiler messages in the log
$r = @{}
$r.version = Run 'version' @('--version')

if (-not (Test-Path 'android') -or -not (Test-Path 'ios') -or -not (Test-Path 'windows')) {
  $r.create = Run 'create platforms' @('create', '--project-name', 'redline_fx', '--org', 'com.redlinefx', '--platforms=android,ios,windows', '.')
}

# --- Android: BLE permissions
$mf = 'android\app\src\main\AndroidManifest.xml'
if ((Test-Path $mf) -and -not (Select-String -LiteralPath $mf -Pattern 'BLUETOOTH_SCAN' -Quiet)) {
  $perm = @'
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
'@
  $t = [IO.File]::ReadAllText((Resolve-Path $mf))
  $t = ([regex]'(<manifest[^>]*>)').Replace($t, "`$1`n$perm", 1)
  $t = $t.Replace('android:label="redline_fx"', 'android:label="REDLINE FX"')
  [IO.File]::WriteAllText((Resolve-Path $mf), $t)
  Log "patched $mf"
}

# --- iOS: Bluetooth usage text, deployment target (universal_ble needs 13.1+)
$pl = 'ios\Runner\Info.plist'
if ((Test-Path $pl) -and -not (Select-String -LiteralPath $pl -Pattern 'NSBluetoothAlwaysUsageDescription' -Quiet)) {
  $t = [IO.File]::ReadAllText((Resolve-Path $pl))
  $i = $t.LastIndexOf('</dict>')
  $t = $t.Insert($i, "`t<key>NSBluetoothAlwaysUsageDescription</key>`n`t<string>Used to connect to the REDLINE FX pedal.</string>`n")
  $t = $t.Replace('<string>Redline Fx</string>', '<string>REDLINE FX</string>')
  [IO.File]::WriteAllText((Resolve-Path $pl), $t)
  Log "patched $pl"
}
$pb = 'ios\Runner.xcodeproj\project.pbxproj'
if (Test-Path $pb) {
  $t = [IO.File]::ReadAllText((Resolve-Path $pb))
  $n = [regex]::Replace($t, 'IPHONEOS_DEPLOYMENT_TARGET = 1[23]\.[0-9];', 'IPHONEOS_DEPLOYMENT_TARGET = 14.0;')
  if ($n -ne $t) { [IO.File]::WriteAllText((Resolve-Path $pb), $n); Log "patched $pb (iOS 14.0)" }
}
if (Test-Path 'ios\Podfile') {
  $t = [IO.File]::ReadAllText((Resolve-Path 'ios\Podfile'))
  $n = [regex]::Replace($t, "#?\s*platform :ios, '[0-9.]+'", "platform :ios, '14.0'")
  if ($n -ne $t) { [IO.File]::WriteAllText((Resolve-Path 'ios\Podfile'), $n); Log "patched ios\Podfile" }
}

# --- Windows: MSVC on a Japanese system reads sources as CP932; plugin headers contain UTF-8
#     characters -> C4819 warning -> error (/WX). Compile everything as UTF-8.
$cm = 'windows\CMakeLists.txt'
if ((Test-Path $cm) -and -not (Select-String -LiteralPath $cm -Pattern '/utf-8' -SimpleMatch -Quiet)) {
  $t = [IO.File]::ReadAllText((Resolve-Path $cm))
  $t = ([regex]'(?m)^(project\([^\r\n]*\))').Replace($t, "`$1`nadd_compile_options(/utf-8)", 1)
  $t = $t.Replace('PRIVATE /W4 /WX', 'PRIVATE /utf-8 /W4 /WX')
  [IO.File]::WriteAllText((Resolve-Path $cm), $t)
  Log "patched $cm (/utf-8)"
}

# --- Windows: window size / title
$mc = 'windows\runner\main.cpp'
if (Test-Path $mc) {
  $t = [IO.File]::ReadAllText((Resolve-Path $mc))
  $n = $t.Replace('Win32Window::Size size(1280, 720);', 'Win32Window::Size size(1360, 900);').Replace('L"redline_fx"', 'L"REDLINE FX"')
  if ($n -ne $t) { [IO.File]::WriteAllText((Resolve-Path $mc), $n); Log "patched $mc" }
}

# --- Windows: GPU diagnostics (gpu-log.txt next to the exe) + prefer the discrete GPU on hybrid laptops
if ((Test-Path 'windows\runner') -and (Test-Path 'tool\gpu_probe.h')) {
  Copy-Item -Force 'tool\gpu_probe.h' 'windows\runner\gpu_probe.h'
  if ((Test-Path $mc) -and -not (Select-String -LiteralPath $mc -Pattern 'gpu_probe' -SimpleMatch -Quiet)) {
    $t = [IO.File]::ReadAllText((Resolve-Path $mc))
    $t = $t.Replace('#include "utils.h"', "#include `"utils.h`"`n#include `"gpu_probe.h`"")
    $t = ([regex]'(_In_ int show_command\)\s*\{)').Replace($t, "`$1`n  gpu_probe::Start();", 1)
    [IO.File]::WriteAllText((Resolve-Path $mc), $t)
    Log "patched $mc (gpu probe)"
  }
  if ((Test-Path $mc) -and -not (Select-String -LiteralPath $mc -Pattern 'ImpellerWanted' -SimpleMatch -Quiet)) {
    $t = [IO.File]::ReadAllText((Resolve-Path $mc))
    $t = $t.Replace('flutter::DartProject project(L"data");', "flutter::DartProject project(L`"data`");`n  if (!gpu_probe::ImpellerWanted()) project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);")
    [IO.File]::WriteAllText((Resolve-Path $mc), $t)
    Log "patched $mc (Skia renderer unless impeller-on.txt)"
  }
}
try {
  Get-CimInstance Win32_VideoController | ForEach-Object {
    Log ("GPU: " + $_.Name + " | driver " + $_.DriverVersion + " (" + $_.DriverDate + ") | status " + $_.Status + " | " + $_.CurrentHorizontalResolution + "x" + $_.CurrentVerticalResolution)
  }
} catch { Log "GPU: query failed" }

# a still-running app from the previous setup locks build\ (tests and the build fail)
Get-Process -Name 'redline_fx' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
if (Test-Path 'build\unit_test_assets') { Remove-Item -Recurse -Force 'build\unit_test_assets' -ErrorAction SilentlyContinue }

$r.pubget = Run 'pub get' @('pub', 'get')
$r.analyze = Run 'analyze' @('analyze', '--no-fatal-infos', '--no-fatal-warnings')
$r.test = Run 'test' @('test', '--reporter', 'expanded')
if ($r.pubget -eq 0) { $r.windows = Run 'build windows' @('build', 'windows', '--release') }
if ($Android -and $r.pubget -eq 0) { $r.apk = Run 'build apk' @('build', 'apk', '--debug') }

Log ""
Log ("RESULT " + (($r.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '))

$exe = 'build\windows\x64\runner\Release\redline_fx.exe'
if ($r.windows -eq 0 -and -not $NoRun -and (Test-Path $exe)) {
  Log "start $exe"
  Start-Process -FilePath (Resolve-Path $exe)
}
