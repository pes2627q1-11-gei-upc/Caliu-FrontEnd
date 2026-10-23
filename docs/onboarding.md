# Onboarding — Caliu FrontEnd

## Requisits

- Flutter stable (`flutter doctor` OK a Android)
- Clau **Maps SDK for Android**
- Backend local ([Caliu-Backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend)) amb Docker

## Passos

```powershell
git clone https://github.com/pes2627q1-11-gei-upc/Caliu-FrontEnd.git
cd Caliu-FrontEnd
flutter pub get
```

1. Copia `android/local.properties.example` → `android/local.properties` i afegeix `MAPS_API_KEY=...`
2. Aixeca l’API al backend (`docker compose up -d mongo api-node`)
3. Arrenca l’app:

```powershell
# Emulador (default a lib/config.dart = 10.0.2.2)
flutter run

# Mòbil físic
flutter run --dart-define=API_BASE_URL=http://IP_DEL_PC:3000
```

## Proves ràpides

- Mapa amb pins / llista d’esdeveniments
- Obrir una fitxa des d’un pin
- Cerca per text (p. ex. un municipi o títol)
- Si hi ha `url`, el botó de web oficial obre el navegador

## Més

- [README](../README.md)
- [CONTRIBUTING](../CONTRIBUTING.md)
- OpenAPI del backend: `docs/openapi.yaml` al repo Caliu-Backend
