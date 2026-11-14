import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_social/features/onboarding/registration_rules.dart';

/// Regole della registrazione: età (D1, M2, M6), data, numero (+39, L3), codice.
void main() {
  final DateTime oggi = DateTime(2026, 11, 14);

  test('età compiuta: prima e dopo il compleanno', () {
    expect(RegistrationRules.ageOn(DateTime(2012, 11, 14), oggi), 14);
    expect(RegistrationRules.ageOn(DateTime(2012, 11, 15), oggi), 13);
    expect(RegistrationRules.ageOn(DateTime(2008, 11, 14), oggi), 18);
    expect(RegistrationRules.ageOn(DateTime(2008, 11, 15), oggi), 17);
  });

  test('data di nascita: formati accettati e date inesistenti', () {
    expect(RegistrationRules.parseBirthDate('24/05/2001'), DateTime(2001, 5, 24));
    expect(RegistrationRules.parseBirthDate('1-2-1999'), DateTime(1999, 2, 1));
    expect(RegistrationRules.parseBirthDate('24.05.2001'), DateTime(2001, 5, 24));
    expect(RegistrationRules.parseBirthDate('31/02/2001'), isNull);
    expect(RegistrationRules.parseBirthDate('2001-05-24'), isNull);
    expect(RegistrationRules.parseBirthDate(''), isNull);
  });

  test('M2: sotto i 14 anni registrazione bloccata (Privato e Azienda)', () {
    for (final AccountKind kind in AccountKind.values) {
      expect(
        RegistrationRules.checkBirthDate(DateTime(2012, 11, 15), kind, oggi),
        BirthDateCheck.tooYoung,
      );
    }
    expect(
      RegistrationRules.checkBirthDate(DateTime(2012, 11, 14), AccountKind.private, oggi),
      BirthDateCheck.ok,
    );
  });

  test('M6: Azienda solo maggiorenni', () {
    expect(
      RegistrationRules.checkBirthDate(DateTime(2008, 11, 15), AccountKind.business, oggi),
      BirthDateCheck.businessNeedsAdult,
    );
    expect(
      RegistrationRules.checkBirthDate(DateTime(2008, 11, 14), AccountKind.business, oggi),
      BirthDateCheck.ok,
    );
    expect(
      RegistrationRules.checkBirthDate(DateTime(2008, 11, 15), AccountKind.private, oggi),
      BirthDateCheck.ok,
    );
  });

  test('date future, troppo vecchie o assenti: non valide', () {
    expect(
      RegistrationRules.checkBirthDate(DateTime(2027, 1, 1), AccountKind.private, oggi),
      BirthDateCheck.invalid,
    );
    expect(
      RegistrationRules.checkBirthDate(DateTime(1899, 1, 1), AccountKind.private, oggi),
      BirthDateCheck.invalid,
    );
    expect(RegistrationRules.checkBirthDate(null, AccountKind.private, oggi), BirthDateCheck.invalid);
  });

  test('L3: solo cellulari italiani, in formato +39', () {
    expect(RegistrationRules.italianMobile('333 123 4567'), '+393331234567');
    expect(RegistrationRules.italianMobile('+39 300 000 0001'), '+393000000001');
    expect(RegistrationRules.italianMobile('0039 333-1234567'), '+393331234567');
    expect(RegistrationRules.italianMobile('06 1234567'), isNull);
    expect(RegistrationRules.italianMobile('+44 7700 900123'), isNull);
    expect(RegistrationRules.italianMobile('33312'), isNull);
  });

  test('codice SMS: esattamente 6 cifre', () {
    expect(RegistrationRules.isSmsCode('123456'), isTrue);
    expect(RegistrationRules.isSmsCode('12345'), isFalse);
    expect(RegistrationRules.isSmsCode('12a456'), isFalse);
  });
}
