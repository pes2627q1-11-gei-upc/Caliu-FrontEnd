import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'auth_session.dart';
import 'event.dart';
import 'favorites_api.dart';

class ActivityApiException implements Exception {
  const ActivityApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

enum ActivityType {
  /// L'usuari ha afegit l'esdeveniment als preferits.
  favoriteAdded,

  /// L'usuari ha assistit a l'esdeveniment.
  attended,
}

/// Una entrada de l'historial d'activitat de l'usuari (H.U #36).
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.type,
    required this.event,
    required this.at,
  });

  final String id;
  final ActivityType type;
  final Event event;
  final DateTime at;
}

/// Historial d'activitat de l'usuari autenticat.
///
/// El backend encara no l'exposa. Proposta de contracte (pendent de
/// confirmar a l'OpenAPI del backend):
/// - `GET /users/me/activity` →
///   `{ "items": [{ "id", "type": "favorite_added" | "attended",
///   "event": Event, "createdAt" }] }`, el més recent primer
abstract interface class ActivityApi {
  /// Activitat de l'usuari, la més recent primer.
  Future<List<ActivityEntry>> fetchActivity();
}

/// Instància que fa servir l'app. Quan el backend estigui llest, aquí es
/// canviarà la implementació simulada per la HTTP.
ActivityApi createActivityApi({AuthSessionStore? session}) =>
    MockActivityApi(session: session ?? AuthSession());

/// Implementació amb dades simulades mentre no hi ha backend.
class MockActivityApi implements ActivityApi {
  MockActivityApi({
    this.session,
    List<ActivityEntry>? seed,
    this.latency = const Duration(milliseconds: 300),
  }) : _entries = List.of(seed ?? sampleActivity());

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final List<ActivityEntry> _entries;

  @override
  Future<List<ActivityEntry>> fetchActivity() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session != null) {
      final token = await session.readToken();
      if (token == null || token.isEmpty) {
        throw const ActivityApiException(
          'Cal iniciar sessió per veure la teva activitat',
          statusCode: 401,
        );
      }
    }
    final sorted = List.of(_entries)..sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(sorted);
  }
}

/// Activitat simulada relativa a [now] (per defecte, ara), perquè les dates
/// surtin recents.
List<ActivityEntry> sampleActivity({DateTime? now}) {
  final today = now ?? DateTime.now();
  return [
    ActivityEntry(
      id: 'mock-act-1',
      type: ActivityType.favoriteAdded,
      event: sampleFavorites[0],
      at: today.subtract(const Duration(hours: 3)),
    ),
    ActivityEntry(
      id: 'mock-act-2',
      type: ActivityType.attended,
      event: Event(
        id: 'mock-past-1',
        title: 'Concert de Sant Esteve',
        venue: 'Palau de la Música Catalana',
        municipality: 'Barcelona',
        comarca: 'Barcelonès',
        location: const LatLng(41.3875, 2.1753),
        categories: const ['música'],
        startDate: today.subtract(const Duration(days: 2)),
      ),
      at: today.subtract(const Duration(days: 2)),
    ),
    ActivityEntry(
      id: 'mock-act-3',
      type: ActivityType.favoriteAdded,
      event: sampleFavorites[1],
      at: today.subtract(const Duration(days: 5)),
    ),
    ActivityEntry(
      id: 'mock-act-4',
      type: ActivityType.attended,
      event: Event(
        id: 'mock-past-2',
        title: 'Fira Modernista de Terrassa',
        municipality: 'Terrassa',
        comarca: 'Vallès Occidental',
        location: const LatLng(41.5633, 2.0089),
        categories: const ['fires'],
        startDate: today.subtract(const Duration(days: 12)),
      ),
      at: today.subtract(const Duration(days: 12)),
    ),
  ];
}
