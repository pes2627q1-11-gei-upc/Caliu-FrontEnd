import 'package:caliu/data/password_reset_api.dart';
import 'package:caliu/forgot_password_screen.dart';
import 'package:caliu/login_screen.dart';
import 'package:caliu/new_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2026, 11, 20, 10);

MockPasswordResetApi _api({
  Map<String, DateTime>? tokens,
  DateTime Function()? clock,
  int maxRequests = 5,
}) => MockPasswordResetApi(
  accounts: {'prova@example.cat'},
  tokens: tokens,
  latency: Duration.zero,
  clock: clock ?? () => _start,
  maxRequestsPerWindow: maxRequests,
);

Matcher _resetError(int status) => throwsA(
  isA<PasswordResetException>().having((e) => e.statusCode, 'status', status),
);

Future<void> _fillNewPassword(
  WidgetTester tester, {
  required String token,
  String password = 'NovaClau123',
  String? confirm,
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Codi del correu'),
    token,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Contrasenya nova'),
    password,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Repeteix la contrasenya nova'),
    confirm ?? password,
  );
  await tester.tap(find.text('Canvia la contrasenya'));
  await tester.pumpAndSettle();
}

void main() {
  group('Enllaç amagat fins que hi hagi backend (revisió PR #33)', () {
    test('per defecte, la recuperació no està disponible', () {
      expect(passwordResetAvailable, isFalse);
    });

    testWidgets('el login no mostra «He oblidat la contrasenya»', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      expect(find.text('He oblidat la contrasenya'), findsNothing);
      expect(find.text('Correu electrònic'), findsOneWidget);
    });
  });

  group('MockPasswordResetApi', () {
    test('envia un token als comptes que existeixen', () async {
      final api = _api();
      await api.requestReset('  Prova@Example.cat ');
      expect(api.lastIssuedToken, isNotNull);
      expect(api.lastIssuedToken, hasLength(8));
    });

    test(
      'no revela si el correu té compte: respon igual però no envia res',
      () async {
        final api = _api();
        await api.requestReset('ningu@example.cat');
        expect(api.lastIssuedToken, isNull);
      },
    );

    test('amb un token vàlid canvia la contrasenya, i només un cop', () async {
      final api = _api();
      await api.requestReset('prova@example.cat');
      final token = api.lastIssuedToken!;

      await api.resetPassword(token: token, password: 'NovaClau123');
      await expectLater(
        api.resetPassword(token: token, password: 'UnaAltra123'),
        _resetError(400),
      );
    });

    test('un token invàlid és rebutjat', () async {
      await expectLater(
        _api().resetPassword(token: 'INVENTAT', password: 'NovaClau123'),
        _resetError(400),
      );
    });

    test('un token caducat és rebutjat', () async {
      var now = _start;
      final api = MockPasswordResetApi(
        accounts: {'prova@example.cat'},
        latency: Duration.zero,
        tokenLifetime: const Duration(minutes: 30),
        clock: () => now,
      );
      await api.requestReset('prova@example.cat');
      now = _start.add(const Duration(minutes: 31));
      await expectLater(
        api.resetPassword(token: api.lastIssuedToken!, password: 'NovaClau1'),
        throwsA(
          isA<PasswordResetException>().having(
            (e) => e.message,
            'message',
            contains('caducat'),
          ),
        ),
      );
    });

    test(
      'rate limit: massa peticions donen 429 fins que passa la finestra',
      () async {
        var now = _start;
        final api = _api(maxRequests: 2, clock: () => now);
        await api.requestReset('prova@example.cat');
        await api.requestReset('prova@example.cat');
        await expectLater(
          api.requestReset('prova@example.cat'),
          _resetError(429),
        );

        now = _start.add(const Duration(minutes: 16));
        await api.requestReset('prova@example.cat');
      },
    );
  });

  group('ForgotPasswordScreen', () {
    testWidgets('valida el correu abans d\'enviar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(api: _api())),
      );
      await tester.enterText(find.byType(TextFormField), 'no-es-un-correu');
      await tester.tap(find.text('Envia les instruccions'));
      await tester.pumpAndSettle();
      expect(find.text('Revisa el teu correu'), findsNothing);
    });

    testWidgets('en enviar, mostra un missatge que no revela el compte', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            api: _api(),
            initialEmail: 'ningu@example.cat',
          ),
        ),
      );
      await tester.tap(find.text('Envia les instruccions'));
      await tester.pumpAndSettle();

      expect(find.text('Revisa el teu correu'), findsOneWidget);
      expect(
        find.textContaining('Si ningu@example.cat correspon a un compte'),
        findsOneWidget,
      );
    });

    testWidgets('rate limit: mostra l\'error a la pantalla', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            api: _api(maxRequests: 0),
            initialEmail: 'prova@example.cat',
          ),
        ),
      );
      await tester.tap(find.text('Envia les instruccions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Massa intents'), findsOneWidget);
    });
  });

  group('NewPasswordScreen', () {
    testWidgets('token invàlid: l\'error es mostra a la pantalla', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: NewPasswordScreen(api: _api())),
      );
      await _fillNewPassword(tester, token: 'INVENTAT');
      expect(find.textContaining('El codi no és vàlid'), findsOneWidget);
    });

    testWidgets('token caducat: l\'error es mostra a la pantalla', (
      tester,
    ) async {
      final api = _api(
        tokens: {'CADUCAT1': _start.subtract(const Duration(minutes: 1))},
      );
      await tester.pumpWidget(MaterialApp(home: NewPasswordScreen(api: api)));
      await _fillNewPassword(tester, token: 'CADUCAT1');
      expect(find.textContaining('ha caducat'), findsOneWidget);
    });

    testWidgets('valida la contrasenya i la confirmació', (tester) async {
      final api = _api(
        tokens: {'VALID123': _start.add(const Duration(minutes: 10))},
      );
      await tester.pumpWidget(MaterialApp(home: NewPasswordScreen(api: api)));
      await _fillNewPassword(
        tester,
        token: 'VALID123',
        password: 'curta',
        confirm: 'altra',
      );
      expect(
        find.text('La contrasenya ha de tenir almenys 8 caràcters.'),
        findsOneWidget,
      );
      expect(find.text('Les contrasenyes no coincideixen.'), findsOneWidget);
    });
  });

  testWidgets('flux complet des del login fins a la contrasenya canviada', (
    tester,
  ) async {
    final api = _api();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(passwordResetApi: api, showForgotPassword: true),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correu electrònic'),
      'prova@example.cat',
    );
    await tester.tap(find.text('He oblidat la contrasenya'));
    await tester.pumpAndSettle();

    // El correu del login ja ve escrit.
    expect(find.text('prova@example.cat'), findsOneWidget);
    await tester.tap(find.text('Envia les instruccions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Introdueix el codi'));
    await tester.pumpAndSettle();

    await _fillNewPassword(tester, token: api.lastIssuedToken!);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.text('Contrasenya canviada. Ja pots iniciar sessió amb la nova.'),
      findsOneWidget,
    );
  });
}
