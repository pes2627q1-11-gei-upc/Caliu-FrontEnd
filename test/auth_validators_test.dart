import 'package:caliu/data/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthValidators.username', () {
    test('accepta límits de 3 i 30 caràcters Unicode', () {
      expect(AuthValidators.username('abc'), isNull);
      expect(AuthValidators.username(List.filled(30, 'a').join()), isNull);
      expect(AuthValidators.username('àéç'), isNull);
    });

    test('rebutja longitud inferior o superior als límits', () {
      expect(AuthValidators.username('ab'), isNotNull);
      expect(AuthValidators.username(List.filled(31, 'a').join()), isNotNull);
    });

    test('retalla espais exteriors i rebutja espais interiors o símbols', () {
      expect(AuthValidators.username('  Usuari_1  '), isNull);
      expect(AuthValidators.username('usuari nou'), isNotNull);
      expect(AuthValidators.username('nom!'), isNotNull);
    });
  });

  group('AuthValidators.password', () {
    test('rebutja menys de 8 caràcters Unicode', () {
      expect(AuthValidators.password('1234567'), isNotNull);
    });

    test('accepta 72 bytes UTF-8 i rebutja 73', () {
      final seventyTwoBytes = List.filled(36, 'é').join();
      expect(AuthValidators.password(seventyTwoBytes), isNull);
      expect(AuthValidators.password('${seventyTwoBytes}a'), isNotNull);
    });

    test('compta caràcters multibyte i rebutja controls', () {
      expect(AuthValidators.password('àéçàéçàé'), isNull);
      expect(AuthValidators.password('contras\u0000enya'), isNotNull);
      expect(AuthValidators.password('        '), isNotNull);
    });

    test('comprova que la confirmació sigui idèntica', () {
      expect(AuthValidators.passwordConfirmation('secret12', 'secret12'), isNull);
      expect(
        AuthValidators.passwordConfirmation('secret13', 'secret12'),
        isNotNull,
      );
    });
  });
}
