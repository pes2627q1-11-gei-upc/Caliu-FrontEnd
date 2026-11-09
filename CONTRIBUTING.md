# Com contribuir — Caliu FrontEnd

## Abans de començar

1. [docs/onboarding.md](docs/onboarding.md)
2. No inventis camps de l’API: segueix l’OpenAPI del [backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/development/docs/openapi.yaml)
3. Agafa la història a Taiga i marca-la *In progress*

## Flux Git (estil Git Flow)

| Branca | Ús |
|--------|-----|
| `main` | Estable / entregable |
| `development` | Integració del sprint |
| `feature/<id-taiga>-<nom>` | Una tasca; surt de `development` i hi torna amb PR |

Exemple de branca: `feature/85-pins-mapa`

1. `git checkout development && git pull`
2. `git checkout -b feature/<id>-<nom-curt>`
3. Commits i push de la branca
4. **Pull request** cap a `development` (plantilla a `.github/pull_request_template.md`)
5. Quan calgui alliberar: PR de `development` → `main`
6. Actualitza Taiga en merge

## Commits

Format: `task #<id>: <resum en imperatiu>`  
El resum (després dels dos punts) **≤ 50 caràcters**.

```
task #85: afegeix pins al mapa amb GET /events
```

## Abans del PR

```powershell
flutter analyze --no-fatal-infos
flutter test
```

La CI (`ci-flutter`) també corre a les PR cap a `development` i `main`.

## Secrets

- Maps: només a `android/local.properties` (gitignored)
- Cap IP personal a `lib/config.dart`: usa `--dart-define=API_BASE_URL=...`
