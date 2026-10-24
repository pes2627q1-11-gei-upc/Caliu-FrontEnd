# Caliu · FrontEnd

<p align="center">
  <img src="docs/assets/banner.svg" alt="Caliu: Sent el Caliu, enamora’t de la cultura catalana" width="100%">
</p>

App mòbil **Flutter** de **Caliu**: mapa i agenda d’esdeveniments culturals a Catalunya (equip **Cultura't** · PES FIB-UPC · grup 11).

<p align="center">
  <a href="https://github.com/pes2627q1-11-gei-upc/Caliu-FrontEnd/actions/workflows/ci-flutter.yml"><img src="https://github.com/pes2627q1-11-gei-upc/Caliu-FrontEnd/actions/workflows/ci-flutter.yml/badge.svg?branch=main" alt="CI Flutter"></a>
  <img src="https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Maps-Google%20Maps-4285F4?logo=googlemaps&logoColor=white" alt="Google Maps">
  <img src="https://img.shields.io/badge/API-Caliu%20Backend-339933?logo=nodedotjs&logoColor=white" alt="API">
</p>

<p align="center">
  <a href="docs/onboarding.md"><b>Onboarding</b></a> ·
  <a href="CONTRIBUTING.md"><b>Contribuir</b></a> ·
  <a href="https://github.com/pes2627q1-11-gei-upc/Caliu-Backend"><b>Backend</b></a> ·
  <a href="https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/main/docs/openapi.yaml"><b>OpenAPI</b></a>
</p>

## Què fa

- **Mapa** amb esdeveniments propers (geolocalització).
- **Fitxa** d’esdeveniment (imatge, categories, lloc, enllaç web oficial quan hi ha `url`).
- **Cerca i filtres** (text, categories/chips, radi).
- Parla amb el backend **només** per HTTP/JSON; contracte: OpenAPI del repo backend.

## Arrencada ràpida

Requisits: [Flutter](https://docs.flutter.dev/get-started/install) (stable), Android SDK, Docker Desktop (per l’API local), clau **Maps SDK for Android**.

```powershell
git clone https://github.com/pes2627q1-11-gei-upc/Caliu-FrontEnd.git
cd Caliu-FrontEnd
flutter pub get
```

1. Configura la clau de Maps (secció següent).
2. Aixeca el backend i defineix `API_BASE_URL`.
3. Executa:

```powershell
flutter run --dart-define=API_BASE_URL=http://IP_DEL_PC:3000
```

## Secrets (Maps)

La clau **no** es puja a GitHub.

1. Copia [`android/local.properties.example`](android/local.properties.example) → `android/local.properties` (Flutter ja pot haver creat `sdk.dir` / `flutter.sdk`).
2. Afegeix:

```properties
MAPS_API_KEY=la_teva_clau_aqui
```

3. Activa **Maps SDK for Android** a Google Cloud Console.
4. `android/local.properties` està al `.gitignore`. No posis mai la clau al `AndroidManifest.xml`.

## Backend local

Cal el repo [Caliu-Backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend) amb `.env` (copieu `.env.example` allà).

```powershell
cd Caliu-Backend
docker compose up -d mongo api-node
curl.exe http://localhost:3000/health
```

Dades: `docker compose exec api-node npm run seed` (només Mongo local) o dades d’Atlas. Comprova:

```powershell
curl.exe "http://localhost:3000/events?lat=41.3851&lng=2.1734&radiusKm=15&limit=5"
```

### URL de l’API des del mòbil

| Entorn | Base URL | Com |
|--------|----------|-----|
| Emulador Android | `http://10.0.2.2:3000` | `flutter run` (default) |
| Mòbil físic **USB** | `http://127.0.0.1:3000` | `.\scripts\run-mobil.ps1` (`adb reverse`) |
| Mòbil físic Wi‑Fi | `http://IP_DEL_PC:3000` | mateixa xarxa; a eduroam sovint falla → USB |
| Demo / profe (Render) | `https://caliu-api.onrender.com` | APK o `flutter run` amb aquesta URL |

API pública (Render): https://caliu-api.onrender.com/health  

```powershell
flutter run --dart-define=API_BASE_URL=https://caliu-api.onrender.com
# o APK:
flutter build apk --dart-define=API_BASE_URL=https://caliu-api.onrender.com
```

> Al pla free de Render el servei pot estar adormit: la primera petició pot trigar ~30–60 s.

**Mòbil per USB (recomanat):**

```powershell
# Backend en marxa + cable + depuració USB
.\scripts\run-mobil.ps1
```

A l’app, pestanya **Perfil** → «Estat del servidor» (ha de sortir verd / Connectat).

Més detall: [docs/onboarding.md](docs/onboarding.md).

## Stack

| Peça | Tecnologia |
|------|------------|
| UI | Flutter (Material) |
| Mapa | `google_maps_flutter` |
| Ubicació | `geolocator` |
| HTTP | `http` |
| Enllaços | `url_launcher` |
| API | Caliu-Backend (`GET /events`, …) |

## Estructura (`lib/`)

```
lib/
├── main.dart
├── config.dart              # API_BASE_URL (dart-define)
├── map_view.dart
├── search_screen.dart
├── profile_screen.dart      # estat API (GET /health)
├── event_detail_screen.dart
├── data/
├── theme/
├── widgets/
└── scripts/run-mobil.ps1    # adb reverse + flutter run
```

## Estat (Sprint 1)

| Funcionalitat | Estat |
|---------------|--------|
| Mapa + markers | Fet |
| Fitxa d’esdeveniment | Fet |
| Cerca / filtres / chips | Fet |
| Auth / preferits | Pendent (back + front) |
| Desplegament públic + APK release | En curs |

## Com treballem

- Canvis via **pull request** a `main`
- Commits preferiblement en [Conventional Commits](https://www.conventionalcommits.org/) amb referència Taiga, p. ex. `feat(map): markers des de l’API` + `Refs: #85`
- Contracte API: no inventar camps; seguir [`docs/openapi.yaml`](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/main/docs/openapi.yaml) del backend

## Equip

**Cultura't · Caliu** — PES 2026-27 Q1 · FIB-UPC · grup 11.

Gestió de tasques a **Taiga** (projecte *Cultura't - Caliu*; enllaç intern de l’equip).
