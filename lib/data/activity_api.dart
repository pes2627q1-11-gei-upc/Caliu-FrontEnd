import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'auth_session.dart';
import 'event.dart';

class ActivityApiException implements Exception {
  const ActivityApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Una assistència de l'historial d'activitat de l'usuari (H.U #36).
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.event,
    required this.at,
  });

  final String id;
  final Event event;

  /// Quan hi va assistir.
  final DateTime at;
}

/// Historial d'assistència de l'usuari autenticat (H.U #36).
///
/// **Les assistències encara no poden ser reals.** Saber si l'usuari ha anat
/// a un acte depèn de la validació d'assistència per GPS (`HaAssistit`), que
/// encara no existeix. Fins llavors, l'app només mostra dades simulades
/// ([MockActivityApi]).
///
/// El backend encara no l'exposa. Proposta de contracte (pendent de
/// confirmar a l'OpenAPI del backend):
/// - `GET /users/me/activity` →
///   `{ "items": [{ "id", "event": Event, "attendedAt" }] }`,
///   el més recent primer. Només ha d'incloure assistències validades per
///   GPS (`HaAssistit`).
abstract interface class ActivityApi {
  /// Assistències de l'usuari, la més recent primer.
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

/// Assistències simulades relatives a [now] (per defecte, ara): unes de
/// recents i unes d'antigues, perquè surtin les dues seccions.
List<ActivityEntry> sampleActivity({DateTime? now}) {
  final today = now ?? DateTime.now();
  ActivityEntry attended(
    String id,
    int daysAgo,
    String title, {
    String? venue,
    required String municipality,
    required String comarca,
    required LatLng location,
    required String category,
  }) {
    final at = today.subtract(Duration(days: daysAgo));
    return ActivityEntry(
      id: 'mock-act-$id',
      at: at,
      event: Event(
        id: 'mock-past-$id',
        title: title,
        venue: venue,
        municipality: municipality,
        comarca: comarca,
        location: location,
        categories: [category],
        startDate: at,
      ),
    );
  }

  return [
    attended(
      '1',
      2,
      'Concert de Sant Esteve',
      venue: 'Palau de la Música Catalana',
      municipality: 'Barcelona',
      comarca: 'Barcelonès',
      location: const LatLng(41.3875, 2.1753),
      category: 'música',
    ),
    attended(
      '2',
      12,
      'Fira Modernista de Terrassa',
      municipality: 'Terrassa',
      comarca: 'Vallès Occidental',
      location: const LatLng(41.5633, 2.0089),
      category: 'fires',
    ),
    attended(
      '3',
      45,
      'Exposició: Dalí i la ciència',
      venue: 'Teatre-Museu Dalí',
      municipality: 'Figueres',
      comarca: 'Alt Empordà',
      location: const LatLng(42.2681, 2.9592),
      category: 'exposicions',
    ),
    attended(
      '4',
      150,
      'Fira de Sant Ponç',
      venue: 'Carrer de l\'Hospital',
      municipality: 'Barcelona',
      comarca: 'Barcelonès',
      location: const LatLng(41.3809, 2.1700),
      category: 'fires',
    ),
    attended(
      '5',
      240,
      'Festival Grec: nit de dansa',
      venue: 'Teatre Grec',
      municipality: 'Barcelona',
      comarca: 'Barcelonès',
      location: const LatLng(41.3689, 2.1586),
      category: 'dansa',
    ),
  ];
}
