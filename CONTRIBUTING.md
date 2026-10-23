# Com contribuir — Caliu FrontEnd

## Abans de començar

1. [docs/onboarding.md](docs/onboarding.md)
2. No inventis camps de l’API: segueix l’OpenAPI del [backend](https://github.com/pes2627q1-11-gei-upc/Caliu-Backend/blob/main/docs/openapi.yaml)
3. Agafa la història a Taiga i marca-la *In progress*

## Flux

1. Branca o commit clar a `main` via PR quan sigui possible
2. Conventional Commits + `Refs: #NN`
3. Abans del PR: `flutter analyze` i `flutter test`
4. Descripció del PR: què / com provar / captures si canvia UI
5. Actualitza Taiga en merge

## Secrets

- Maps: només a `android/local.properties` (gitignored)
- Cap IP personal a `lib/config.dart`: usa `--dart-define=API_BASE_URL=...`
