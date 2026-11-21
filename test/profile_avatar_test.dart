import 'dart:convert';
import 'dart:typed_data';

import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/avatar_api.dart';
import 'package:caliu/data/avatar_controller.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/data/favorites_api.dart';
import 'package:caliu/data/favorites_controller.dart';
import 'package:caliu/profile_screen.dart';
import 'package:caliu/square_crop_screen.dart';
import 'package:caliu/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

/// PNG vàlid d'1x1 píxel.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _NoSession implements AuthSessionStore {
  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String value) async {}

  @override
  Future<void> clear() async {}
}

class _FailingApi implements AvatarApi {
  @override
  Future<Uint8List?> fetchAvatar() async => null;

  @override
  Future<void> uploadAvatar(Uint8List bytes, {required String contentType}) =>
      Future.error(const AvatarApiException('Error de xarxa', statusCode: 503));
}

MockAvatarApi _api({Uint8List? initial}) =>
    MockAvatarApi(initial: initial, latency: Duration.zero);

Widget _app(AvatarController controller, {AvatarPicker? picker}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: ProfileAvatar(
        username: 'Nuria_42',
        controller: controller,
        picker: picker,
        radius: 30,
      ),
    ),
  ),
);

Future<void> _chooseGallery(WidgetTester tester) async {
  await tester.tap(find.byType(ProfileAvatar));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tria de la galeria'));
  await tester.pumpAndSettle();
}

/// Sessió en memòria per simular el canvi de compte.
class _MemorySession implements AuthSessionStore {
  _MemorySession(this.token);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Cada compte (token) té la seva foto, com faria el backend.
class _PerAccountAvatarApi implements AvatarApi {
  _PerAccountAvatarApi(this.session, this.photos);

  final _MemorySession session;
  final Map<String, Uint8List> photos;

  @override
  Future<Uint8List?> fetchAvatar() async => photos[session.token];

  @override
  Future<void> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async => photos[session.token!] = bytes;
}

class _FakeLogin extends StatelessWidget {
  const _FakeLogin(this.session, this.token);

  final _MemorySession session;
  final String token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () async {
          await session.saveToken(token);
          if (context.mounted) Navigator.of(context).pop(true);
        },
        child: const Text('Entra com a B'),
      ),
    );
  }
}

void main() {
  group('Avatar lligat a la sessió (revisió PR #35)', () {
    final photoA = Uint8List.fromList([..._png]);
    final photoB = Uint8List.fromList([..._png, 0]);

    Future<(AvatarController, _MemorySession)> pumpProfile(
      WidgetTester tester, {
      required Map<String, Uint8List> photos,
    }) async {
      final session = _MemorySession('token-a');
      final avatar = AvatarController(_PerAccountAvatarApi(session, photos));
      await avatar.load(); // com fa main() en obrir l'app
      final authApi = AuthApi(
        client: MockClient((request) async {
          if (request.url.path == '/users/me') {
            final user = request.headers['authorization'] == 'Bearer token-b'
                ? 'compte_b'
                : 'compte_a';
            return http.Response(
              '{"id":"$user","username":"$user","email":"$user@example.cat",'
              '"preferences":[]}',
              200,
            );
          }
          if (request.url.path == '/auth/logout') return http.Response('', 204);
          throw StateError('Crida inesperada: ${request.url}');
        }),
        baseUrl: 'http://localhost:3000',
      );
      final eventsApi = EventsApi(
        client: MockClient(
          (_) async => http.Response('{"status":"ok","service":"test"}', 200),
        ),
        baseUrl: 'http://localhost:3000',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            authApi: authApi,
            authSession: session,
            eventsApi: eventsApi,
            favorites: FavoritesController(
              MockFavoritesApi(seed: const [], latency: Duration.zero),
            ),
            avatar: avatar,
            loginBuilder: (_) => _FakeLogin(session, 'token-b'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (avatar, session);
    }

    Future<void> logout(WidgetTester tester) async {
      await tester.tap(find.text('Tanca la sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tanca la sessió').last);
      await tester.pumpAndSettle();
    }

    Future<void> loginAsB(WidgetTester tester) async {
      await tester.tap(find.text('Inicia sessió'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entra com a B'));
      await tester.pumpAndSettle();
    }

    ImageProvider? shownImage(WidgetTester tester) => tester
        .widget<CircleAvatar>(find.byKey(const Key('profile-avatar')))
        .foregroundImage;

    testWidgets('en tancar sessió s\'esborra la foto', (tester) async {
      final (avatar, session) = await pumpProfile(
        tester,
        photos: {'token-a': photoA},
      );
      expect(avatar.bytes, photoA);
      expect(shownImage(tester), isA<MemoryImage>());

      await logout(tester);

      expect(session.token, isNull);
      expect(avatar.bytes, isNull);
    });

    testWidgets('canvi de compte: es veu la foto del compte nou', (
      tester,
    ) async {
      final (avatar, _) = await pumpProfile(
        tester,
        photos: {'token-a': photoA, 'token-b': photoB},
      );
      await logout(tester);
      await loginAsB(tester);

      expect(find.text('compte_b'), findsOneWidget);
      expect(avatar.bytes, photoB);
      expect((shownImage(tester)! as MemoryImage).bytes, photoB);
    });

    testWidgets('canvi a un compte sense foto: no queda la de l\'anterior', (
      tester,
    ) async {
      final (avatar, _) = await pumpProfile(
        tester,
        photos: {'token-a': photoA},
      );
      await logout(tester);
      await loginAsB(tester);

      expect(find.text('compte_b'), findsOneWidget);
      expect(avatar.bytes, isNull);
      expect(shownImage(tester), isNull);
      expect(find.text('C'), findsOneWidget);
    });
  });

  group('AvatarRules', () {
    test('tipus permesos segons l\'extensió', () {
      expect(AvatarRules.contentTypeFor('foto.JPG'), 'image/jpeg');
      expect(AvatarRules.contentTypeFor('foto.png'), 'image/png');
      expect(AvatarRules.contentTypeFor('foto.webp'), 'image/webp');
      expect(AvatarRules.contentTypeFor('foto.gif'), isNull);
      expect(AvatarRules.contentTypeFor('sense_extensio'), isNull);
    });

    test('valida tipus i mida', () {
      expect(AvatarRules.validate(fileName: 'a.png', sizeBytes: 1000), isNull);
      expect(
        AvatarRules.validate(fileName: 'a.gif', sizeBytes: 1000),
        contains('Format no permès'),
      );
      expect(
        AvatarRules.validate(
          fileName: 'a.jpg',
          sizeBytes: AvatarRules.maxBytes + 1,
        ),
        contains('massa gran'),
      );
    });
  });

  group('MockAvatarApi', () {
    test('pujar-ne una de nova substitueix l\'anterior', () async {
      final api = _api(initial: Uint8List.fromList([1]));
      await api.uploadAvatar(Uint8List.fromList([2]), contentType: 'image/png');
      expect(await api.fetchAvatar(), [2]);
    });

    test('rebutja tipus no permesos i fitxers massa grans', () async {
      final api = _api();
      await expectLater(
        api.uploadAvatar(Uint8List(10), contentType: 'image/gif'),
        throwsA(
          isA<AvatarApiException>().having((e) => e.statusCode, 's', 400),
        ),
      );
      await expectLater(
        api.uploadAvatar(
          Uint8List(AvatarRules.maxBytes + 1),
          contentType: 'image/png',
        ),
        throwsA(
          isA<AvatarApiException>().having((e) => e.statusCode, 's', 413),
        ),
      );
    });

    test('sense sessió dona 401', () async {
      final api = MockAvatarApi(session: _NoSession(), latency: Duration.zero);
      await expectLater(
        api.uploadAvatar(_png, contentType: 'image/png'),
        throwsA(
          isA<AvatarApiException>().having((e) => e.isUnauthorized, 'u', true),
        ),
      );
    });
  });

  group('AvatarController', () {
    test('load llegeix la foto del servidor', () async {
      final controller = AvatarController(_api(initial: _png));
      await controller.load();
      expect(controller.bytes, _png);
    });

    test('si la pujada falla, es manté la foto anterior', () async {
      final controller = AvatarController(_FailingApi());
      await expectLater(
        controller.upload(_png, contentType: 'image/png'),
        throwsA(isA<AvatarApiException>()),
      );
      expect(controller.bytes, isNull);
      expect(controller.isUploading, isFalse);
    });
  });

  group('ProfileAvatar', () {
    testWidgets('sense foto mostra la inicial', (tester) async {
      await tester.pumpWidget(_app(AvatarController(_api())));
      expect(find.text('N'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(
        find.byKey(const Key('profile-avatar')),
      );
      expect(avatar.foregroundImage, isNull);
    });

    testWidgets('amb foto la mostra', (tester) async {
      final controller = AvatarController(_api(initial: _png));
      await controller.load();
      await tester.pumpWidget(_app(controller));
      final avatar = tester.widget<CircleAvatar>(
        find.byKey(const Key('profile-avatar')),
      );
      expect(avatar.foregroundImage, isA<MemoryImage>());
    });

    testWidgets('ofereix càmera i galeria', (tester) async {
      await tester.pumpWidget(_app(AvatarController(_api())));
      await tester.tap(find.byType(ProfileAvatar));
      await tester.pumpAndSettle();
      expect(find.text('Fes una foto'), findsOneWidget);
      expect(find.text('Tria de la galeria'), findsOneWidget);
    });

    testWidgets('fer una foto demana la càmera', (tester) async {
      ImageSource? asked;
      await tester.pumpWidget(
        _app(
          AvatarController(_api()),
          picker: (source) async {
            asked = source;
            return null;
          },
        ),
      );
      await tester.tap(find.byType(ProfileAvatar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fes una foto'));
      await tester.pumpAndSettle();
      expect(asked, ImageSource.camera);
    });

    testWidgets('un tipus no permès es rebutja sense retallar', (tester) async {
      await tester.pumpWidget(
        _app(
          AvatarController(_api()),
          picker: (_) async => XFile.fromData(_png, path: 'animacio.gif'),
        ),
      );
      await _chooseGallery(tester);
      expect(find.byType(SquareCropScreen), findsNothing);
      expect(find.textContaining('Format no permès'), findsOneWidget);
    });

    testWidgets('un fitxer massa gran es rebutja', (tester) async {
      await tester.pumpWidget(
        _app(
          AvatarController(_api()),
          picker: (_) async => XFile.fromData(
            Uint8List(AvatarRules.maxBytes + 1),
            path: 'enorme.jpg',
          ),
        ),
      );
      await _chooseGallery(tester);
      expect(find.byType(SquareCropScreen), findsNothing);
      expect(find.textContaining('massa gran'), findsOneWidget);
    });

    testWidgets('una imatge vàlida obre el retall; cancel·lar no puja res', (
      tester,
    ) async {
      final controller = AvatarController(_api());
      await tester.pumpWidget(
        _app(
          controller,
          picker: (_) async => XFile.fromData(_png, path: 'foto.png'),
        ),
      );
      await _chooseGallery(tester);
      expect(find.byType(SquareCropScreen), findsOneWidget);

      await tester.tap(find.text('Cancel·la'));
      await tester.pumpAndSettle();
      expect(find.byType(SquareCropScreen), findsNothing);
      expect(controller.bytes, isNull);
    });

    testWidgets('retallar i pujar: es mostra la foto nova', (tester) async {
      final api = _api();
      final controller = AvatarController(api);
      await tester.pumpWidget(
        _app(
          controller,
          picker: (_) async => XFile.fromData(_png, path: 'foto.png'),
        ),
      );
      await _chooseGallery(tester);

      // Capturar la imatge retallada necessita el motor real.
      await tester.runAsync(() async {
        await tester.tap(find.text('Fet'));
        for (var i = 0; i < 20 && controller.bytes == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      expect(find.byType(SquareCropScreen), findsNothing);
      expect(controller.bytes, isNotNull);
      expect(await api.fetchAvatar(), controller.bytes);
      expect(find.text('Foto de perfil actualitzada'), findsOneWidget);
    });
  });
}
