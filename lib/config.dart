/// Base URL of api-node.
///
/// Override at run time (recommended):
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
///
/// Default: Android emulator → host machine. On a physical device, always
/// pass --dart-define with your PC LAN IP or a public HTTPS URL.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000',
);
