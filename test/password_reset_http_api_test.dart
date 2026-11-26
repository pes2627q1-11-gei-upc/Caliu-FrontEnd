import 'dart:convert';

import 'package:caliu/data/password_reset_api.dart';
import 'package:caliu/data/password_reset_http_api.dart';
import 'package:caliu/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'http://127.0.0.1:3000';
const _token = '0123456789abcdef0123456789abcdef0123456789abcdef';

(HttpPasswordResetApi, List<http.Request>) _api(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final api = HttpPasswordResetApi(
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    baseUrl: _baseUrl,
  );
  return (api, requests);
}

Matcher _error({int? status, Object? message}) => throwsA(
  isA<PasswordResetException>()
      .having((e) => e.statusCode, 'statusCode', status)
      .having((e) => e.message, 'message', message ?? isA<String>()),
);

void main() {
  group('forgot-password', () {
    test('envia el correu i accepta el 202, sense token', () async {
      final (api, requests) = _api((_) async => http.Response('', 202));

      await api.requestReset('  prova@example.cat ');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$_baseUrl/auth/forgot-password');
      expect(request.headers['authorization'], isNull);
      expect(jsonDecode(request.body), {'email': 'prova@example.cat'});
    });

    test('503: servei de correu no disponible', () async {
      final (api, _) = _api((_) async => http.Response('', 503));
      await expectLater(
        api.requestReset('prova@example.cat'),
        _error(status: 503, message: contains('no està disponible')),
      );
    });

    test('429: massa intents', () async {
      final (api, _) = _api((_) async => http.Response('', 429));
      await expectLater(
        api.requestReset('prova@example.cat'),
        _error(status: 429, message: contains('Massa intents')),
      );
    });

    test('sense connexió', () async {
      final (api, _) = _api((_) async => throw const _NetworkError());
      await expectLater(
        api.requestReset('prova@example.cat'),
        _error(message: contains('No s\'ha pogut connectar')),
      );
    });
  });

  group('reset-password', () {
    test(
      'envia el codi en minúscules i la contrasenya; accepta el 204',
      () async {
        final (api, requests) = _api((_) async => http.Response('', 204));

        await api.resetPassword(
          token: '  ${_token.toUpperCase()} ',
          password: 'NovaClau123',
        );

        final request = requests.single;
        expect(request.url.path, '/auth/reset-password');
        expect(jsonDecode(request.body), {
          'token': _token,
          'password': 'NovaClau123',
        });
      },
    );

    test('400: mostra el missatge del servidor', () async {
      final (api, _) = _api(
        (_) async => http.Response('{"error":"Codi invàlid o caducat"}', 400),
      );
      await expectLater(
        api.resetPassword(token: _token, password: 'NovaClau123'),
        _error(status: 400, message: 'Codi invàlid o caducat'),
      );
    });

    test('400 sense missatge: missatge per defecte', () async {
      final (api, _) = _api((_) async => http.Response('', 400));
      await expectLater(
        api.resetPassword(token: _token, password: 'NovaClau123'),
        _error(status: 400, message: contains('no és vàlid o ha caducat')),
      );
    });

    test('429: massa intents', () async {
      final (api, _) = _api((_) async => http.Response('', 429));
      await expectLater(
        api.resetPassword(token: _token, password: 'NovaClau123'),
        _error(status: 429),
      );
    });

    test('error del servidor', () async {
      final (api, _) = _api((_) async => http.Response('', 500));
      await expectLater(
        api.resetPassword(token: _token, password: 'NovaClau123'),
        _error(status: 500),
      );
    });
  });

  testWidgets('la pantalla mostra el 503 del servidor', (tester) async {
    final (api, _) = _api((_) async => http.Response('', 503));
    await tester.pumpWidget(
      MaterialApp(
        home: ForgotPasswordScreen(api: api, initialEmail: 'prova@example.cat'),
      ),
    );

    await tester.tap(find.text('Envia les instruccions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no està disponible'), findsOneWidget);
    expect(find.text('Revisa el teu correu'), findsNothing);
  });
}

class _NetworkError implements Exception {
  const _NetworkError();
}
