# Caliu-FrontEnd

App mòbil Flutter de **Caliu** (equip Cultura't · PES). Parla amb el backend (`Caliu-Backend`) només per HTTPS/HTTP + JSON; el contracte és `docs/openapi.yaml` del repo backend.

## Requisits

- [Flutter](https://docs.flutter.dev/get-started/install) (stable) i `flutter doctor` amb Android
- Android Studio (SDK + emulador opcional) o mòbil amb depuració USB
- Docker Desktop (per aixecar l’API local)
- Clau de **Google Maps SDK for Android** (compartida entre els membres o personal)

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

## Backend local (API d’esdeveniments)

Cal el repo **Caliu-Backend** amb `.env` (no està al Git; demana’l a l’equip).

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
