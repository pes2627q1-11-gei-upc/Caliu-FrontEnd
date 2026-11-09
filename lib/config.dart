/// Base URL of api-node.
///
/// Override at run time (recommended):
///   flutter run --dart-define-from-file=.env   (copy .env.example → .env)
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
///   flutter run -d chrome --web-port 5000 --dart-define-from-file=.env  (web, see docs/deploy-web.md)
///   .\scripts\run-mobil.ps1   → http://127.0.0.1:3000 via adb reverse
///
/// Default: Android emulator → host machine (10.0.2.2).
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);
