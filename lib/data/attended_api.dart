import 'activity_api.dart';
import 'activity_http_api.dart';
import 'auth_session.dart';
import 'event.dart';

class AttendedApiException implements Exception {
  const AttendedApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Esdeveniments passats als quals ha assistit l'usuari autenticat (H.U #51).
///
/// Endpoint del backend (OpenAPI), vegeu [HttpAttendedApi]:
/// - `GET /users/me/attended` → `{ "items": [Event, ...] }`, només
///   esdeveniments acabats, del més recent al més antic
abstract interface class AttendedApi {
  /// Esdeveniments passats als quals ha assistit, el més recent primer.
  Future<List<Event>> fetchAttended();
}

/// Instància que fa servir l'app: el backend real (tasca #229).
AttendedApi createAttendedApi({AuthSessionStore? session}) =>
    HttpAttendedApi(AttendanceHttpClient(session: session));

/// Implementació amb dades simulades, per als tests.
class MockAttendedApi implements AttendedApi {
  MockAttendedApi({
    this.session,
    List<Event>? seed,
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  }) : _events = List.of(seed ?? sampleAttended()),
       _clock = clock ?? DateTime.now;

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final List<Event> _events;
  final DateTime Function() _clock;

  @override
  Future<List<Event>> fetchAttended() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session != null) {
      final token = await session.readToken();
      if (token == null || token.isEmpty) {
        throw const AttendedApiException(
          'Cal iniciar sessió per veure el teu historial',
          statusCode: 401,
        );
      }
    }
    // Com el backend: només esdeveniments ja passats.
    final now = _clock();
    final past =
        _events
            .where((e) => e.startDate != null && e.startDate!.isBefore(now))
            .toList()
          ..sort((a, b) => b.startDate!.compareTo(a.startDate!));
    return List.unmodifiable(past);
  }
}

/// Historial simulat: els mateixos esdeveniments que l'activitat simulada,
/// perquè les dues pestanyes del perfil siguin coherents.
List<Event> sampleAttended({DateTime? now}) =>
    sampleActivity(now: now).map((entry) => entry.event).toList();
