/// Regole della registrazione (Fase 2, Blocco 1), controllate sul telefono
/// PRIMA di creare l'account: sotto i 14 anni non si salva nulla (M2).
library;

/// Tipo di account scelto nella schermata iniziale (R2.1).
enum AccountKind { private, business }

abstract final class RegistrationRules {
  /// Età minima per usare Piazly (D1).
  static const int minimumAge = 14;

  /// Età minima per l'account Azienda (M6).
  static const int businessMinimumAge = 18;

  /// Età compiuta alla data [today].
  static int ageOn(DateTime birth, DateTime today) {
    int age = today.year - birth.year;
    final bool beforeBirthday =
        today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day);
    if (beforeBirthday) age--;
    return age;
  }

  /// Interpreta una data scritta come GG/MM/AAAA (anche con «-» o «.»).
  static DateTime? parseBirthDate(String input) {
    final RegExpMatch? m = RegExp(
      r'^\s*(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})\s*$',
    ).firstMatch(input);
    if (m == null) return null;
    final int day = int.parse(m.group(1)!);
    final int month = int.parse(m.group(2)!);
    final int year = int.parse(m.group(3)!);
    final DateTime date = DateTime(year, month, day);
    // Rifiuta date inesistenti (es. 31/02), che DateTime correggerebbe da solo.
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  /// Motivo per cui la data non consente la registrazione, oppure null se va bene.
  static BirthDateCheck checkBirthDate(
    DateTime? birth,
    AccountKind kind,
    DateTime today,
  ) {
    if (birth == null) return BirthDateCheck.invalid;
    final DateTime day = DateTime(today.year, today.month, today.day);
    if (birth.isAfter(day) || birth.year < 1900) return BirthDateCheck.invalid;
    final int age = ageOn(birth, day);
    if (age < minimumAge) return BirthDateCheck.tooYoung;
    if (kind == AccountKind.business && age < businessMinimumAge) {
      return BirthDateCheck.businessNeedsAdult;
    }
    return BirthDateCheck.ok;
  }

  /// Numero di cellulare italiano in formato internazionale (+39…), oppure null.
  /// Solo Italia nella prima versione (L3).
  static String? italianMobile(String input) {
    String digits = input.replaceAll(RegExp(r'[\s./()-]'), '');
    if (digits.startsWith('+39')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0039')) {
      digits = digits.substring(4);
    }
    if (!RegExp(r'^3\d{8,9}$').hasMatch(digits)) return null;
    return '+39$digits';
  }

  /// Codice SMS di 6 cifre.
  static bool isSmsCode(String input) => RegExp(r'^\d{6}$').hasMatch(input.trim());
}

enum BirthDateCheck { ok, invalid, tooYoung, businessNeedsAdult }

/// Dati raccolti prima dell'accesso. Restano SOLO in memoria e si salvano con il
/// profilo (Blocco 2); se l'app si chiude prima, vengono richiesti di nuovo.
class RegistrationDraft {
  const RegistrationDraft({
    required this.kind,
    required this.birthDate,
    required this.termsAcceptedAt,
  });

  final AccountKind kind;
  final DateTime birthDate;

  /// Accettazione delle bozze di Termini, Privacy e Regole (S7).
  final DateTime termsAcceptedAt;
}

/// Unico punto dove i dati della registrazione restano, in memoria, fino al Blocco 2.
abstract final class RegistrationDraftStore {
  static RegistrationDraft? current;
}
