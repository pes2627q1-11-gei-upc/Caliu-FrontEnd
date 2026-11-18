import 'package:caliu/data/search_radius.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  final calls = <String>[];
  var enabled = true;
  var permission = 0;
  var requestedPermission = 2;
  var failPosition = false;

  setUp(() {
    calls.clear();
    enabled = true;
    permission = 0;
    requestedPermission = 2;
    failPosition = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return enabled;
        case 'checkPermission':
          return permission;
        case 'requestPermission':
          return requestedPermission;
        case 'getCurrentPosition':
          if (failPosition) {
            throw PlatformException(code: 'POSITION_UNAVAILABLE');
          }
          return {
            'latitude': 42.0,
            'longitude': 1.0,
            'timestamp': 1794900000000,
            'accuracy': 10.0,
            'altitude': 0.0,
            'heading': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
            'altitude_accuracy': 0.0,
            'heading_accuracy': 0.0,
          };
        default:
          throw StateError('Unexpected: ${call.method}');
      }
    });
  });

  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('demana permís i usa la posició rebuda del proveïdor', () async {
    final radius = SearchRadius();
    await radius.apply(5);
    expect(calls, contains('requestPermission'));
    expect(radius.center, const LatLng(42, 1));
    expect(radius.radiusKm, 5);
    radius.dispose();
  });

  for (final denied in [0, 1]) {
    test(
      'permís denegat $denied impedeix obtenir posició i aplicar radi',
      () async {
        permission = denied;
        requestedPermission = denied;
        final radius = SearchRadius();
        await radius.apply(5);
        expect(calls, isNot(contains('getCurrentPosition')));
        expect(radius.center, isNull);
        expect(radius.radiusKm, isNull);
        expect(radius.error, SearchRadius.unavailableMessage);
        radius.dispose();
      },
    );
  }

  test('servei desactivat no demana permisos ni aplica radi', () async {
    enabled = false;
    final radius = SearchRadius();
    await radius.apply(5);
    expect(calls, ['isLocationServiceEnabled']);
    expect(radius.radiusKm, isNull);
    expect(radius.error, SearchRadius.unavailableMessage);
    radius.dispose();
  });

  test('error del proveïdor permet reintentar amb èxit', () async {
    failPosition = true;
    final radius = SearchRadius();
    await radius.apply(5);
    expect(radius.radiusKm, isNull);
    expect(radius.center, isNull);
    failPosition = false;
    await radius.apply(5);
    expect(radius.radiusKm, 5);
    expect(radius.error, isNull);
    radius.dispose();
  });
}
