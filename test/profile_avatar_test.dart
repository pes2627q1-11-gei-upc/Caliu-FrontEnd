import 'dart:convert';
import 'dart:typed_data';

import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/avatar_api.dart';
import 'package:caliu/data/avatar_controller.dart';
import 'package:caliu/square_crop_screen.dart';
import 'package:caliu/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
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
