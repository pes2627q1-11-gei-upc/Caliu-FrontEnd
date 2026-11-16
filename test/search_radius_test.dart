import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:caliu/data/search_radius.dart';

void main() {
  test('només aplica el radi després de rebre la ubicació real', () async {
    final pending = Completer<LatLng>();
    final radius = SearchRadius(locate: () => pending.future);
    final operation = radius.apply(0.1);
    expect(radius.locating, isTrue);
    expect(radius.radiusKm, isNull);
    pending.complete(const LatLng(42, 1));
    await operation;
    expect(radius.center, const LatLng(42, 1));
    expect(radius.radiusKm, 0.1);
    expect(radius.locating, isFalse);
    radius.dispose();
  });

  test('error o permís denegat no inventa coordenades', () async {
    final radius = SearchRadius(locate: () async => throw StateError('denied'));
    await radius.apply(500);
    expect(radius.center, isNull);
    expect(radius.radiusKm, isNull);
    expect(radius.error, SearchRadius.unavailableMessage);
    radius.dispose();
  });

  test('restablir ignora una ubicació pendent', () async {
    final pending = Completer<LatLng>();
    final radius = SearchRadius(locate: () => pending.future);
    final operation = radius.apply(15);
    radius.clear();
    pending.complete(const LatLng(42, 1));
    await operation;
    expect(radius.radiusKm, isNull);
    expect(radius.center, isNull);
    radius.dispose();
  });

  test('rebutja límits invàlids i accepta el màxim', () async {
    final radius = SearchRadius(locate: () async => const LatLng(42, 1));
    for (final value in [0.0, 500.1, double.nan, double.infinity]) {
      await expectLater(radius.apply(value), throwsArgumentError);
    }
    await radius.apply(500);
    expect(radius.radiusKm, 500);
    radius.dispose();
  });
}
