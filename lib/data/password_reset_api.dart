import 'dart:math';

class PasswordResetException implements Exception {
  const PasswordResetException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Massa peticions (rate limit).
  bool get isRateLimited => statusCode == 429;

  /// El token no és vàlid, ha caducat o ja s'ha fet servir.
  bool get isInvalidToken => statusCode == 400;

  @override
  String toString() => message;
}

/// El backend encara no envia el correu de recuperació (tasques #172 i #173):
/// sense correu, l'usuari no pot aconseguir el codi i quedaria encallat. Per
/// això l'enllaç «He oblidat la contrasenya» s'amaga fins que funcioni
/// (revisió de la PR #33). Per provar-lo:
/// `flutter run --dart-define=PASSWORD_RESET=true`.
const passwordResetAvailable = bool.fromEnvironment('PASSWORD_RESET');

/// Recuperació de contrasenya per correu (H.U #57).
///
/// El backend encara no l'exposa (tasques #172 i #173). Proposta de contracte
/// (pendent de confirmar a l'OpenAPI del backend):
/// - `POST /auth/forgot-password` → body `{ "email" }`. Respon sempre 202,
///   existeixi o no el compte, perquè no reveli quins correus hi ha.
/// - `POST /auth/reset-password` → body `{ "token", "password" }`. 400 si
///   el token no és vàlid, ha caducat o ja s'ha fet servir.
/// - Tots dos amb rate limit: 429 si se supera.
abstract interface class PasswordResetApi {
  /// Demana que s'enviï el correu amb el token de reset.
  Future<void> requestReset(String email);

  /// Canvia la contrasenya amb el [token] rebut per correu.
  Future<void> resetPassword({required String token, required String password});
}

/// Instància que fa servir l'app. Quan el backend estigui llest, aquí es
/// canviarà la implementació simulada per la HTTP.
PasswordResetApi createPasswordResetApi() => MockPasswordResetApi();

/// Implementació en memòria mentre no hi ha backend. Simula els comptes
/// existents, la caducitat dels tokens, que només es puguin fer servir un cop
/// i el rate limit.
class MockPasswordResetApi implements PasswordResetApi {
  MockPasswordResetApi({
    Set<String>? accounts,
    Map<String, DateTime>? tokens,
    this.tokenLifetime = const Duration(minutes: 30),
    this.maxRequestsPerWindow = 5,
    this.rateLimitWindow = const Duration(minutes: 15),
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  }) : _accounts = {...(accounts ?? sampleAccounts)},
       _tokens = {...?tokens},
       _clock = clock ?? DateTime.now;

  final Set<String> _accounts;

  /// Token → moment en què caduca.
  final Map<String, DateTime> _tokens;
  final Set<String> _usedTokens = {};
  final List<DateTime> _requests = [];

  final Duration tokenLifetime;
  final int maxRequestsPerWindow;
  final Duration rateLimitWindow;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;
  final DateTime Function() _clock;

  /// Últim token "enviat per correu" (per als tests i les proves).
  String? lastIssuedToken;

  @override
  Future<void> requestReset(String email) async {
    await _simulateRequest();
    final normalized = email.trim().toLowerCase();
    // Si el compte no existeix, es respon igual però no s'envia res.
    if (!_accounts.contains(normalized)) return;
    final token = _newToken();
    _tokens[token] = _clock().add(tokenLifetime);
    lastIssuedToken = token;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await _simulateRequest();
    final cleanToken = token.trim();
    final expiresAt = _tokens[cleanToken];
    if (expiresAt == null) {
      throw const PasswordResetException(
        'El codi no és vàlid. Comprova que l\'has copiat sencer.',
        statusCode: 400,
      );
    }
    if (_usedTokens.contains(cleanToken)) {
      throw const PasswordResetException(
        'Aquest codi ja s\'ha fet servir. Demana\'n un de nou.',
        statusCode: 400,
      );
    }
    if (!_clock().isBefore(expiresAt)) {
      throw const PasswordResetException(
        'El codi ha caducat. Demana\'n un de nou.',
        statusCode: 400,
      );
    }
    _usedTokens.add(cleanToken);
  }

  Future<void> _simulateRequest() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final now = _clock();
    _requests.removeWhere((at) => now.difference(at) >= rateLimitWindow);
    if (_requests.length >= maxRequestsPerWindow) {
      throw const PasswordResetException(
        'Massa intents. Espera uns minuts i torna-ho a provar.',
        statusCode: 429,
      );
    }
    _requests.add(now);
  }

  static final _random = Random.secure();

  String _newToken() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(
      8,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }
}

/// Comptes simulats que poden rebre el correu de recuperació.
const sampleAccounts = {'prova@example.cat'};
