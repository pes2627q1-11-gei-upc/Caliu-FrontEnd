# Desplegament — Caliu FrontEnd

L’API pública és al backend: **https://caliu-api.onrender.com**  
Guia completa del servei: [deploy del Backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/main/docs/deploy.md).

## APK per al profe / demo

```powershell
cd Caliu-FrontEnd
flutter build apk --dart-define=API_BASE_URL=https://caliu-api.onrender.com
```

Sortida: `build\app\outputs\flutter-apk\app-release.apk`

1. Instal·lar al mòbil (sense Docker ni USB).
2. Obrir **Perfil** → Connectat (la 1a vegada pot trigar si Render estava adormit).
3. Provar mapa, fitxa, cerca i web oficial.
4. Pujar l’APK al Drive de l’equip.

## Prova en local (dev)

| Mode | Ordre |
|------|--------|
| USB | `.\scripts\run-mobil.ps1` (API local al PC) |
| Emulador | `flutter run` |
| Contra Render | `flutter run --dart-define=API_BASE_URL=https://caliu-api.onrender.com` |
