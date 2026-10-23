# Arrenca l'app al mòbil físic per USB.
# Reenvia el port 3000 del PC al mòbil (no cal IP Wi‑Fi).
#
# Abans: backend en marxa (docker compose up -d mongo api-node)
#         i depuració USB activada (adb devices ha de llistar el mòbil).
#
# Ús (des de l'arrel del FrontEnd):
#   .\scripts\run-mobil.ps1
#   .\scripts\run-mobil.ps1 -DeviceId emulator-5554

param(
    [string] $DeviceId = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
    Write-Error "No trobo 'adb'. Obre un terminal on flutter/android SDK estigui al PATH (o Android Studio → SDK Platform-Tools)."
}

Write-Host "==> Dispositius adb"
adb devices

if ($DeviceId) {
    adb -s $DeviceId reverse tcp:3000 tcp:3000
} else {
    adb reverse tcp:3000 tcp:3000
}
Write-Host "==> adb reverse tcp:3000 -> tcp:3000 OK"

$flutterArgs = @(
    "run",
    "--dart-define=API_BASE_URL=http://127.0.0.1:3000"
)
if ($DeviceId) {
    $flutterArgs += @("-d", $DeviceId)
}

Write-Host "==> flutter $($flutterArgs -join ' ')"
flutter @flutterArgs
