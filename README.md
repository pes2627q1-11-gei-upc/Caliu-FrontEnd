# Caliu-FrontEnd

App mòbil Flutter de **Caliu** (equip Cultura't · PES). Parla amb el backend (`Caliu-Backend`) només per HTTPS/HTTP + JSON; el contracte és `docs/openapi.yaml` del repo backend.

## Requisits

- [Flutter](https://docs.flutter.dev/get-started/install) (stable) i `flutter doctor` amb Android OK
- Android Studio (SDK + emulador opcional) o mòbil amb depuració USB
- Docker Desktop (per aixecar l’API local)
- Clau de **Google Maps SDK for Android** (cada persona la seva, o la del projecte compartit)

## Arrencada ràpida

```powershell
git clone <url-del-repo>
cd Caliu-FrontEnd
flutter pub get
```

Configura la clau de Maps i la URL de l’API (seccions següents) i després:

```powershell
flutter run
```

## Clau de Google Maps (obligatòria)

La clau **no** es puja a GitHub.

1. Crea / usa un projecte a [Google Cloud Console](https://console.cloud.google.com/).
2. Habilita **Maps SDK for Android**.
3. Crea una API key. Restricció recomanada:
   - Apps Android
   - Package: `com.example.caliu`
   - SHA-1 del keystore de debug (al PC):

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

4. A `android/local.properties` (ja el crea Flutter; **està al `.gitignore`**) afegeix:

```properties
MAPS_API_KEY=la_teva_clau_aqui
```

Pots partir de `android/local.properties.example`.

5. El `AndroidManifest` usa `${MAPS_API_KEY}` via Gradle. **Mai** deixis una clau `AIza...` al Manifest versionat.

Si el mapa surt gris amb el logo de Google, la clau o Maps SDK no estan bé.

## Backend local (API d’esdeveniments)

Cal el repo **Caliu-Backend** amb `.env` (no està al Git; demana’l a l’equip o copia la plantilla).

```powershell
cd Caliu-Backend
docker compose up -d mongo api-node
curl.exe http://localhost:3000/health
```

Dades de prova (seed) o ingesta real (vegeu docs del backend). Comprova:

```powershell
curl.exe "http://localhost:3000/events?lat=41.3851&lng=2.1734&radiusKm=15&limit=5"
```

Has de rebre JSON amb `items`.

### URL de l’API des del mòbil

El mòbil **no** pot usar `localhost` (seria ell mateix).

| Entorn | Base URL |
|--------|----------|
| Emulador Android | `http://10.0.2.2:3000` |
| Mòbil físic (mateixa Wi‑Fi) | `http://IP_DEL_PC:3000` |

Obté la IP del PC (`ipconfig`, interfície Wi‑Fi). Comprova al **navegador del mòbil**: `http://IP:3000/health`.

Configura la URL d’una d’aquestes maneres:

1. Edita el valor per defecte a `lib/config.dart`, **o**
2. En arrencar:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

En debug, Android permet HTTP clar (`usesCleartextTraffic`) per parlar amb l’API local.

## Estructura útil

```text
lib/
  main.dart           # Entrada; home = mapa
  config.dart         # API_BASE_URL
  map_view.dart       # Mapa + GPS + pins (#78–#80)
  data/
    event.dart        # Model Event (OpenAPI)
    events_api.dart   # GET /events
```

Coordenades de l’API: GeoJSON `[lng, lat]`. Al mapa: `LatLng(lat, lng)`.

## Tasques Taiga relacionades (Sprint 1)

| ID | Què |
|----|-----|
| #78 | Integrar Google Maps |
| #79 | GPS (`geolocator`) |
| #80 | Pins des de `GET /events?lat&lng&radiusKm` |
| #21 / #85–#86 | Fitxa detallada (pendent) |
| #3 / #2 | Cerca i filtres (pendent) |

## Problemes freqüents

| Símptoma | Què mirar |
|----------|-----------|
| `flutter` no es reconeix | PATH / reiniciar terminal |
| NDK / Gradle falla | Versió NDK a `android/app/build.gradle.kts` o instal·lar-la a SDK Manager |
| Install canceled by user | Xiaomi: “Instal·lar via USB” a opcions de desenvolupador |
| Mapa gris | `MAPS_API_KEY` + Maps SDK for Android |
| 0 pins + error de xarxa | Docker, IP a `config.dart`, mateixa Wi‑Fi, firewall port 3000 |
| 0 pins sense error | Sense events / sense `location` / `radiusKm` petit |
| `bad auth` a l’ingesta Atlas | URI / password a `SOURCE_MONGO_URI` (backend) |

## Flux Git

- Branques per funcionalitat + PR (no pujar secrets).
- No commitis `android/local.properties` ni cap `.env`.

## Documentació relacionada

- Backend: `Caliu-Backend/docs/openapi.yaml`
- Explicacions PR1 (API events) i PR2 (ingesta) a la carpeta compartida del curs
