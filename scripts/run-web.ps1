# Arrenca l'app a Chrome (Flutter Web) per provar-la sense emulador ni mòbil.
#
# - Genera web/maps_config.js amb la MATEIXA clau de Google Maps que l'app Android
#   (MAPS_API_KEY de android/local.properties). Aquest fitxer no es puja al repo.
# - Fa servir el port 5000, que és l'origen permès a CORS_ORIGINS del backend.
# - Llegeix API_BASE_URL de .env (copia .env.example -> .env). Sense .env, usa Render.
#
# Ús (des de l'arrel del FrontEnd):
#   .\scripts\run-web.ps1
#   .\scripts\run-web.ps1 -NoWebSecurity   # si el backend encara no té CORS (només dev!)

param(
    [switch] $NoWebSecurity
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 1. Clau de Google Maps
$props = Join-Path $root "android\local.properties"
$key = ""
if (Test-Path $props) {
    $line = Get-Content $props | Where-Object { $_ -match '^\s*MAPS_API_KEY\s*=' } | Select-Object -First 1
    if ($line) { $key = ($line -split '=', 2)[1].Trim() }
}
if (-not $key) {
    Write-Warning "No trobo MAPS_API_KEY a android/local.properties: el mapa no es carregarà."
}
Set-Content -Path (Join-Path $root "web\maps_config.js") -Value "window.MAPS_API_KEY = `"$key`";" -Encoding UTF8
Write-Host "==> web/maps_config.js generat"

# 2. Arguments de flutter
$flutterArgs = @("run", "-d", "chrome", "--web-port", "5000")
if (Test-Path (Join-Path $root ".env")) {
    $flutterArgs += "--dart-define-from-file=.env"
} else {
    Write-Warning "No hi ha .env: s'usa https://caliu-api.onrender.com (copia .env.example -> .env per canviar-ho)."
    $flutterArgs += "--dart-define=API_BASE_URL=https://caliu-api.onrender.com"
}
if ($NoWebSecurity) {
    $flutterArgs += @("--web-browser-flag", "--disable-web-security")
}

Write-Host "==> flutter $($flutterArgs -join ' ')"
flutter @flutterArgs
