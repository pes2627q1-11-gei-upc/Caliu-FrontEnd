# Sprint 1 — Caliu FrontEnd

Resum del que s’ha fet al mòbil (octubre 2026). Detall conjunt: [sprint-1 del Backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/main/docs/sprint-1.md).

## Entregat

- Mapa amb pins des de `GET /events`
- Fitxa d’esdeveniment (imatge, categories, lloc, web oficial)
- Cerca i filtres (text, categories/chips)
- Perfil amb estat de l’API (`GET /health`)
- Registre amb auto-login, login i JWT a emmagatzematge segur
- Consulta/edició de perfil (`GET`/`PATCH /users/me`), preferències (`GET`/`PUT /users/me/preferences`) i categories (`GET /events/categories`)
- Logout de la sessió actual (`POST /auth/logout`)
- Arrencada mòbil per USB (`scripts/run-mobil.ps1`)
- CI (`flutter analyze` + tests)
- Documentació + banner al README

## Pendent / en curs

- APK release amb URL de Render (vegeu [deploy.md](deploy.md))
- Prova end-to-end amb el backend `development` desplegat a Render (pendent)
- APK de demo amb el backend integrat desplegat i configurat (pendent)

La demo d'aquesta integració utilitza el backend `development` desplegat a
Render. El client no manté un catàleg propi de preferències.

Les proves Flutter s'han d'executar amb `flutter test` i l'anàlisi amb
`flutter analyze`; els resultats d'aquesta entrega es registren a la PR després
d'executar-los en un entorn amb Flutter instal·lat.

## Històries Taiga (orientatiu)

`#1`, `#85`–`#90` (mapa, fitxa, cerca, chips) — tancar / Ready for test si encara no.
