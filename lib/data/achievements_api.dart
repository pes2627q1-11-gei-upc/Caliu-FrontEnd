import 'achievements_http_api.dart';
import 'auth_session.dart';

class AchievementsApiException implements Exception {
  const AchievementsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Una medalla del catàleg amb el progrés de l'usuari (H.U #59).
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    this.progress = 0,
    this.icon = 'medal',
    this.unlockedByServer,
  });

  final String id;
  final String title;

  /// Regla per aconseguir-la, p. ex. "Assisteix a 5 actes".
  final String description;

  /// Límit definit a les regles.
  final int target;

  /// Progrés acumulat de l'usuari.
  final int progress;

  /// Clau de la icona (vegeu `achievementIcon` a la pantalla).
  final String icon;

  /// Estat que envia el backend (`unlocked`), si n'hi ha. Mana sobre el
  /// càlcul local, per si el servidor aplica altres regles.
  final bool? unlockedByServer;

  /// Desbloquejada en arribar al límit (o segons el backend).
  bool get unlocked => unlockedByServer ?? progress >= target;

  /// Fracció de 0 a 1 per a la barra de progrés.
  double get fraction => target <= 0 ? 1 : (progress / target).clamp(0, 1);

  factory Achievement.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final target = json['target'];
    if (id is! String || title is! String || target is! num) {
      throw const AchievementsApiException(
        'L\'assoliment rebut no té el format esperat.',
      );
    }
    final progress = json['progress'];
    return Achievement(
      id: id,
      title: title,
      description: json['description']?.toString() ?? '',
      target: target.toInt(),
      progress: progress is num ? progress.toInt() : 0,
      icon: json['icon']?.toString() ?? 'medal',
      unlockedByServer: json['unlocked'] is bool
          ? json['unlocked'] as bool
          : null,
    );
  }
}

/// El progrés real depèn de les assistències validades per GPS, que encara no
/// existeixen: amb dades simulades es podrien confondre amb assoliments reals.
/// Per això l'accés des del perfil s'amaga fins que es pugui carregar el
/// progrés real del compte (revisió de la PR #34). Per provar-lo:
/// `flutter run --dart-define=ACHIEVEMENTS=true`.
const achievementsAvailable = bool.fromEnvironment('ACHIEVEMENTS');

/// Catàleg d'assoliments amb el progrés de l'usuari autenticat.
///
/// Endpoint del backend (OpenAPI), vegeu [HttpAchievementsApi]:
/// - `GET /achievements` → `{ "items": [{ "id", "title", "description",
///   "icon", "target", "progress", "unlocked" }] }`; 401 sense JWT vàlid
abstract interface class AchievementsApi {
  Future<List<Achievement>> fetchAchievements();
}

/// Instància que fa servir l'app: el backend real (tasca #230).
AchievementsApi createAchievementsApi({AuthSessionStore? session}) =>
    HttpAchievementsApi(session: session);

/// Implementació amb dades simulades, per als tests.
class MockAchievementsApi implements AchievementsApi {
  MockAchievementsApi({
    this.session,
    List<Achievement>? seed,
    this.latency = const Duration(milliseconds: 300),
  }) : _achievements = List.unmodifiable(seed ?? sampleAchievements);

  /// Si és null no es comprova la sessió.
  final AuthSessionStore? session;

  /// Retard artificial per simular la xarxa (zero als tests).
  final Duration latency;

  final List<Achievement> _achievements;

  @override
  Future<List<Achievement>> fetchAchievements() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final session = this.session;
    if (session != null) {
      final token = await session.readToken();
      if (token == null || token.isEmpty) {
        throw const AchievementsApiException(
          'Cal iniciar sessió per veure els teus assoliments',
          statusCode: 401,
        );
      }
    }
    return _achievements;
  }
}

/// Catàleg simulat. El nombre i les regles reals els ha de definir l'equip.
const sampleAchievements = [
  Achievement(
    id: 'first-event',
    title: 'Primeres passes',
    description: 'Assisteix al teu primer acte cultural.',
    target: 1,
    progress: 1,
    icon: 'steps',
  ),
  Achievement(
    id: 'explorer',
    title: 'Explorador cultural',
    description: 'Assisteix a 5 actes culturals.',
    target: 5,
    progress: 3,
    icon: 'explore',
  ),
  Achievement(
    id: 'museums',
    title: 'Amant dels museus',
    description: 'Assisteix a 3 exposicions.',
    target: 3,
    progress: 3,
    icon: 'museum',
  ),
  Achievement(
    id: 'fairs',
    title: 'Fira rere fira',
    description: 'Assisteix a 3 fires.',
    target: 3,
    progress: 1,
    icon: 'fair',
  ),
  Achievement(
    id: 'collector',
    title: 'Col·leccionista',
    description: 'Desa 10 esdeveniments a Preferits.',
    target: 10,
    progress: 4,
    icon: 'favorite',
  ),
  Achievement(
    id: 'social',
    title: 'Ànima social',
    description: 'Segueix 5 persones de la comunitat.',
    target: 5,
    icon: 'people',
  ),
];
