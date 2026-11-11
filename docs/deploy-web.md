# Provar Caliu des del navegador (Flutter Web)

> **Objectiu:** poder provar l'app des de l'ordinador sense emulador ni mòbil.
> L'app final continua sent **només Android**. La versió web és una eina de test.

## Per què val la pena

| Avantatge | Detall |
|---|---|
| **Sense emulador ni mòbil** | `flutter run -d chrome` arrenca en segons i consumeix molt menys que l'emulador d'Android Studio. |
| **Hot reload** | Igual que al mòbil: guardes i veus el canvi a l'instant. |
| **DevTools del navegador** | Pestanya *Network* per veure les peticions a l'API, *Console* per als errors i *Sensors* per simular una ubicació (p. ex. Barcelona). |
| **Revisió de PRs més ràpida** | Amb el deploy web, qualsevol membre (o el professor) pot obrir un enllaç i provar l'última versió de `main` sense instal·lar l'APK. |
| **Mateix codi** | No cal mantenir res a part: és el mateix projecte Flutter compilat per a un altre target. |

**Limitacions (cal provar-les al mòbil abans de tancar una US):**
- Permisos nativs, notificacions push (FCM) i rendiment real.
- `flutter_secure_storage` a web guarda el token al navegador (menys segur). És acceptable per a testing, no per a producció.
- La geolocalització al navegador només funciona en `localhost` o per HTTPS.

---

## 1. Backend: CORS (branca `feature/web-cors` del backend)

El navegador bloqueja les peticions d'un origen (`http://localhost:5000`) a un altre (`https://caliu-api.onrender.com`) si el servidor no ho permet explícitament. Per això `api-node` té un middleware CORS propi (`src/middlewares/cors.js`, sense dependències noves):

- Només respon CORS als orígens de la variable **`CORS_ORIGINS`** (separats per comes).
- Si la variable és buida, CORS queda desactivat, com abans.
- Respon el *preflight* `OPTIONS` (necessari per enviar `Authorization` i JSON).
- Tests a `tests/cors.test.js`.

**Valor a Render** (*Environment → Environment Variables*) i al `.env` local:
```env
CORS_ORIGINS=http://localhost:5000,https://pes2627q1-11-gei-upc.github.io
```

> **Per què una llista i no `*`:** amb `*` qualsevol web podria cridar la nostra API des del navegador d'un usuari. Amb la llista només ho poden fer el nostre entorn local i el nostre deploy. L'app Android no es veu afectada, perquè CORS només s'aplica als navegadors.
>
> Render desplega des de `main` del backend: el CORS no hi serà actiu fins que `development` es fusioni a `main`.

---

## 2. Frontend: configuració per entorn

La URL de l'API ja es llegeix de `API_BASE_URL` (`lib/config.dart`, via `--dart-define`). Per no haver d'escriure-la cada vegada, posa-la en un fitxer:

**2.1. `.env.example`** (ja és al repo):
```env
API_BASE_URL=https://caliu-api.onrender.com
```

**2.2. Cada membre** el copia a `.env` (ja és al `.gitignore`) i hi posa la seva URL, per exemple el backend local `http://localhost:3000`.

**2.3. Executar** passant el fitxer amb `--dart-define-from-file`, que llegeix `.env` directament:
```bash
flutter run -d chrome --web-port 5000 --dart-define-from-file=.env
```
- `--web-port 5000` fixa l'origen a `http://localhost:5000`, el mateix que hi ha a `CORS_ORIGINS`. Sense aquesta opció, Flutter tria un port aleatori i el backend el rebutjaria.
- Funciona igual per al mòbil: `flutter run --dart-define-from-file=.env`.

> **Mentre el backend no tingui CORS**, es pot provar en local desactivant la seguretat de Chrome (només per a desenvolupament):
> `flutter run -d chrome --web-port 5000 --dart-define-from-file=.env --web-browser-flag "--disable-web-security"`

---

## 3. Google Maps a web

Fem servir **la mateixa clau que l'app Android** (`MAPS_API_KEY` d'`android/local.properties`). Com a Android, **la clau no es puja mai al repo**:

- `web/index.html` carrega `web/maps_config.js` (ignorat per Git), que defineix `window.MAPS_API_KEY`, i amb aquesta clau carrega la Maps JavaScript API.
- **En local**, `scripts/run-web.ps1` genera `maps_config.js` llegint `android/local.properties` i arrenca Chrome al port 5000:
  ```powershell
  .\scripts\run-web.ps1
  .\scripts\run-web.ps1 -NoWebSecurity   # si el backend encara no té CORS
  ```
- **Al deploy**, el workflow genera `maps_config.js` a partir del secret de GitHub **`MAPS_API_KEY`**.

**Requisits de la clau** (Google Cloud Console → *Credencials*, ho fa qui la va crear):
- Al projecte hi ha d'estar activada la **Maps JavaScript API**, a més del *Maps SDK for Android*.
- *Restriccions d'API*: si n'hi ha, cal afegir-hi la **Maps JavaScript API**.
- *Restriccions d'aplicació*: si està limitada a **apps Android**, a web fallarà (`RefererNotAllowedMapError` / `ApiTargetBlockedMapError`). Una clau només admet un tipus de restricció d'aplicació, així que cal posar-la a **Cap**.

> **Compromís:** al deploy públic la clau és visible a `maps_config.js`. Si està sense restricció d'aplicació, algú la podria copiar i gastar la quota del projecte. Per a un projecte d'assignatura amb poc trànsit és acceptable. L'alternativa segura és una clau web separada restringida per referent HTTP.

---

## 4. Deploy web automàtic (GitHub Pages)

Cada push a `main` compila la versió web i la publica a
`https://pes2627q1-11-gei-upc.github.io/Caliu-FrontEnd/`.

**4.1. Fitxer `.github/workflows/deploy-web.yml`** (ja és al repo):
```yaml
name: Deploy web (testing)

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: >
          flutter build web --release
          --base-href /Caliu-FrontEnd/
          --dart-define=API_BASE_URL=https://caliu-api.onrender.com
      - uses: actions/upload-pages-artifact@v3
        with:
          path: build/web

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

**4.2. Activar Pages:** *Settings → Pages → Source: **GitHub Actions***. Ho ha de fer algú amb permisos d'administrador al repo.

**Per què `--base-href /Caliu-FrontEnd/`:** GitHub Pages serveix el projecte dins d'una subcarpeta. Sense això, el navegador busca els fitxers a l'arrel del domini i la pàgina surt en blanc.

> **Si el repo és privat** i l'organització no té un pla de GitHub que permeti Pages en repos privats, la mateixa build (`build/web`) es pot publicar a **Firebase Hosting** (ja fem servir Firebase per a FCM) o a **Cloudflare Pages**. Totes dues opcions són gratuïtes. En aquest cas, cal canviar l'origen a `CORS_ORIGINS` i a la clau de Maps.

**Compilar en local** (per comprovar la build abans del push):
```bash
flutter build web --release --dart-define-from-file=.env
```

---

## Resum de tasques

| # | Qui | Tasca | Estat |
|---|---|---|---|
| 1 | Backend | Middleware CORS + tests + `CORS_ORIGINS` | PR `feature/web-cors` |
| 2 | Admin Render | `CORS_ORIGINS` a les variables d'entorn de Render | Pendent |
| 3 | Frontend | `.env.example` + `--dart-define-from-file` + `scripts/run-web.ps1` | Fet |
| 4 | Admin Google Cloud | Maps JavaScript API activada + clau sense restricció d'app Android | Pendent |
| 5 | Admin repo | Secret `MAPS_API_KEY` (*Settings → Secrets and variables → Actions*) | Pendent |
| 6 | Frontend | Workflow `deploy-web.yml` | Fet |
| 7 | Admin repo | Activar GitHub Pages (Source: GitHub Actions) | Pendent |
