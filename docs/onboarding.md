# Onboarding — Caliu FrontEnd

## Requisits

- Flutter stable (`flutter doctor` OK a Android)
- Clau **Maps SDK for Android**
- Backend local ([Caliu-Backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend)) amb Docker
- Per mòbil físic: cable USB + depuració USB (`adb devices`)

Per provar registre, login, perfil i preferències de Sprint 1, fes servir la
branca `development` de Caliu-Backend i el desplegament de Render corresponent.
Consulta el contracte a [`docs/openapi.yaml` de `development`](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/development/docs/openapi.yaml).

## Passos

```powershell
git clone https://github.com/pes2627q1-11-gei-upc/Caliu-FrontEnd.git
cd Caliu-FrontEnd
flutter pub get
```

1. Copia `android/local.properties.example` → `android/local.properties` i afegeix `MAPS_API_KEY=...`
2. Aixeca l’API al backend (`docker compose up -d mongo api-node`) i comprova `curl.exe http://localhost:3000/health`
3. Arrenca l’app (tria una opció):

### A) Mòbil físic per USB (recomanat)

No cal saber la IP del PC. El script fa `adb reverse` i apunta a `127.0.0.1:3000`:

```powershell
.\scripts\run-mobil.ps1
```

Manual:

```powershell
adb devices
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Cada vegada que desconnectis el cable, torna a fer `adb reverse`.

### B) Emulador Android

```powershell
flutter run
# default a lib/config.dart = http://10.0.2.2:3000
```

### C) Mateixa Wi‑Fi (sense USB)

```powershell
ipconfig
# Al navegador del mòbil: http://IP_DEL_PC:3000/health  (ha de respondre OK)
flutter run --dart-define=API_BASE_URL=http://IP_DEL_PC:3000
```

**Eduroam / xarxa de la uni:** sovint el mòbil i el PC no es veuen. Usa l’opció A (USB) o la zona Wi‑Fi del mòbil amb el PC connectat allà.

### D) API a Render (sense Docker local)

```powershell
flutter run --dart-define=API_BASE_URL=https://caliu-api.onrender.com
# o
flutter build apk --dart-define=API_BASE_URL=https://caliu-api.onrender.com
```

Comprova: https://caliu-api.onrender.com/health  
(Si fa temps que no s’usa, la primera resposta pot trigar una mica.)

## Comprovar que l’API arriba

1. Pestanya **Perfil** a l’app → targeta «Estat del servidor» (verd = connectat).
2. O al navegador / `curl`: `{"status":"ok","service":"api-node"}`.

## Proves ràpides

- Registre amb username, email i contrasenya: en acabar, el perfil ha d'aparèixer autenticat sense un segon login.
- Tanca i torna a obrir l'app: el JWT es recupera de l'emmagatzematge segur i es consulta `GET /users/me`.
- Edita username i preferències; aquestes últimes es carreguen des de `GET /events/categories`.
- Tanca la sessió i comprova que el perfil desapareix. El logout remot revoca només el token actual.
- Mapa amb pins (permisos d’ubicació)
- Obrir una fitxa des d’un pin
- Cerca per text (p. ex. un municipi o títol)
- Si hi ha `url`, el botó de web oficial obre el navegador

Les crides autenticades utilitzen `Authorization: Bearer <token>`. El token es
desa només amb `flutter_secure_storage`; el client no persisteix contrasenyes.
En un error de xarxa durant el logout, reintenta'l per confirmar la revocació o
tria explícitament tancar només al dispositiu.

## Més

- [README](../README.md)
- [deploy.md](deploy.md) — APK amb Render
- [sprint-1.md](sprint-1.md) — què s’ha entregat
- [CONTRIBUTING](../CONTRIBUTING.md)
- OpenAPI del backend: `docs/openapi.yaml` al repo Caliu-Backend
