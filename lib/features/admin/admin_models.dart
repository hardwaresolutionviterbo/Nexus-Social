/// Gestionale degli amministratori (Fase 7): modelli condivisi dalle schermate e dal server.
library;

class AdminFailure implements Exception {
  const AdminFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Il ban definitivo arriva dal server come «infinity».
DateTime? _until(Object? v) => v == 'infinity' ? DateTime(9999) : _date(v);

String twoDigits(int n) => n.toString().padLeft(2, '0');

String adminDate(DateTime d) => '${twoDigits(d.day)}/${twoDigits(d.month)}/${d.year}';

String adminDateTime(DateTime d) => '${adminDate(d)} ${twoDigits(d.hour)}:${twoDigits(d.minute)}';

/// «fino al 12/12/2026» oppure «definitivo».
String banLabel(DateTime until) => until.year >= 9999 ? 'definitivo' : 'fino al ${adminDateTime(until)}';

/// Stato per aprire il gestionale.
class AdminAccess {
  const AdminAccess({this.admin = false, this.role, this.pin = false});

  factory AdminAccess.fromJson(Map<String, dynamic> j) =>
      AdminAccess(admin: j['admin'] == true, role: j['role'] as String?, pin: j['pin'] == true);

  final bool admin;
  final String? role;

  /// Verifica in due passaggi (PIN) attiva: senza, il server non apre il gestionale.
  final bool pin;
}

enum ReportKind {
  listing('listing', 'Annuncio'),
  comment('comment', 'Commento'),
  chat('chat', 'Chat');

  const ReportKind(this.key, this.label);

  final String key;
  final String label;

  static ReportKind? of(Object? v) {
    for (final ReportKind k in values) {
      if (k.key == v) return k;
    }
    return null;
  }
}

/// Motivi delle segnalazioni (annunci, commenti e chat) in italiano.
String reasonLabel(String key) => switch (key) {
  'spam' => 'Spam',
  'truffa' => 'Truffa',
  'contenuto_inappropriato' || 'contenuti' => 'Contenuto inappropriato',
  'pericolo' => 'Pericolo',
  'falso' => 'Falso',
  'molestie' => 'Molestie',
  'minore' => 'Riguarda un minore',
  'altro' => 'Altro',
  _ => key,
};

/// Persona come la vede il gestionale: mai numero di telefono, nome completo o data di nascita.
class AdminPerson {
  const AdminPerson({
    required this.id,
    required this.username,
    required this.name,
    this.business = false,
    this.bannedUntil,
  });

  factory AdminPerson.fromJson(Map<String, dynamic> j) => AdminPerson(
    id: j['id'] as String? ?? '',
    username: j['username'] as String? ?? '',
    name: j['name'] as String? ?? '',
    business: j['account_type'] == 'business',
    bannedUntil: _until(j['banned_until']),
  );

  final String id;
  final String username;
  final String name;
  final bool business;
  final DateTime? bannedUntil;

  bool bannedAt(DateTime now) => bannedUntil != null && bannedUntil!.isAfter(now);
}

/// Messaggio allegato a una segnalazione di chat, scelto da chi ha segnalato.
class ReportedMessage {
  const ReportedMessage({required this.text, required this.fromReporter, this.at});

  factory ReportedMessage.fromJson(Map<String, dynamic> j) => ReportedMessage(
    text: j['t'] as String? ?? '',
    fromReporter: j['da'] == 'io',
    at: _date(j['a']),
  );

  final String text;
  final bool fromReporter;
  final DateTime? at;
}

/// Una voce della coda: tutte le segnalazioni dello stesso annuncio o commento, oppure una chat.
class AdminReport {
  const AdminReport({
    required this.kind,
    required this.id,
    required this.count,
    required this.reasons,
    this.details = const <String>[],
    required this.lastAt,
    this.status = 'open',
    this.title,
    this.text,
    this.contextTitle,
    this.state,
    this.hidden = false,
    this.group = false,
    this.messages = const <ReportedMessage>[],
    this.author,
  });

  factory AdminReport.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> p = j['preview'] is Map<String, dynamic>
        ? j['preview'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminReport(
      kind: ReportKind.of(j['kind']) ?? ReportKind.listing,
      id: j['id'] as String? ?? '',
      count: (j['reports'] as num?)?.toInt() ?? 1,
      reasons: <String>[for (final Object? r in (j['reasons'] as List<dynamic>? ?? const <dynamic>[])) '$r'],
      details: <String>[for (final Object? d in (j['details'] as List<dynamic>? ?? const <dynamic>[])) '$d'],
      lastAt: _date(j['last_at']) ?? DateTime.now(),
      status: j['status'] as String? ?? 'open',
      title: p['title'] as String?,
      text: p['text'] as String?,
      contextTitle: p['listing_title'] as String?,
      state: p['state'] as String?,
      hidden: p['hidden'] == true,
      group: p['group'] == true,
      messages: <ReportedMessage>[
        for (final Object? m in (p['messages'] as List<dynamic>? ?? const <dynamic>[]))
          if (m is Map<String, dynamic>) ReportedMessage.fromJson(m),
      ],
      author: j['author'] is Map<String, dynamic> ? AdminPerson.fromJson(j['author'] as Map<String, dynamic>) : null,
    );
  }

  final ReportKind kind;
  final String id;
  final int count;
  final List<String> reasons;
  final List<String> details;
  final DateTime lastAt;
  final String status;

  /// Annuncio: titolo e testo. Commento: testo e titolo dell'annuncio.
  final String? title;
  final String? text;
  final String? contextTitle;

  /// Stato dell'annuncio (active, removed…) o commento nascosto.
  final String? state;
  final bool hidden;

  /// Chat: di gruppo e messaggi allegati.
  final bool group;
  final List<ReportedMessage> messages;

  final AdminPerson? author;

  /// Il contenuto non c'è più (cancellato dall'autore).
  bool get gone => kind != ReportKind.chat && title == null && text == null;

  bool get removed => state == 'removed' || hidden;

  String get headline => switch (kind) {
    ReportKind.listing => title ?? 'Annuncio non più presente',
    ReportKind.comment => text ?? 'Commento non più presente',
    ReportKind.chat => group ? 'Chat di gruppo' : 'Chat a due',
  };
}

/// Azioni sulla segnalazione.
enum ReportAction {
  ignore('ignore', 'Ignora'),
  remove('remove', 'Elimina'),
  warn('warn', 'Avvisa'),
  ban('ban', 'Banna');

  const ReportAction(this.key, this.label);

  final String key;
  final String label;
}

/// Durata del ban: 1, 7, 30 giorni o definitivo (regole iniziali, 24/11/2026).
enum BanLength {
  day(1, '1 giorno'),
  week(7, '7 giorni'),
  month(30, '30 giorni'),
  forever(null, 'Definitivo');

  const BanLength(this.days, this.label);

  final int? days;
  final String label;
}

/// Testi pronti per avvisi e ban: si possono correggere prima di inviare.
const List<(String, String)> moderationTemplates = <(String, String)>[
  ('Spam', 'Hai pubblicato contenuti ripetuti o pubblicitari. Rispetta le regole della community.'),
  ('Truffa', 'Abbiamo ricevuto segnalazioni di comportamenti ingannevoli. Non sono ammessi su Piazly.'),
  ('Contenuti', 'Hai pubblicato contenuti inappropriati. Rispetta le regole della community.'),
  ('Molestie', 'Abbiamo ricevuto segnalazioni di messaggi molesti verso altre persone.'),
];

class HistoryEntry {
  const HistoryEntry({required this.action, this.target, this.reason, this.until, this.at, this.by});

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    action: j['action'] as String? ?? '',
    target: j['target'] as String?,
    reason: j['reason'] as String?,
    until: _until(j['until']),
    at: _date(j['at']),
    by: j['by'] as String?,
  );

  final String action;
  final String? target;
  final String? reason;
  final DateTime? until;
  final DateTime? at;
  final String? by;

  String get label {
    final String what = switch (target) {
      'listing' => ' (annuncio)',
      'comment' => ' (commento)',
      'chat' => ' (chat)',
      _ => '',
    };
    return switch (action) {
      'ignore' => 'Segnalazione ignorata$what',
      'remove' => 'Contenuto tolto$what',
      'warn' => 'Avviso$what',
      'ban' => 'Ban ${until == null ? '' : banLabel(until!)}$what',
      'unban' => 'Sblocco',
      _ => action,
    };
  }
}

class AdminUserDetail {
  const AdminUserDetail({
    required this.person,
    this.createdAt,
    this.bio,
    this.isAdmin = false,
    this.banReason,
    this.listings = 0,
    this.comments = 0,
    this.reportsOpen = 0,
    this.reportsTotal = 0,
    this.history = const <HistoryEntry>[],
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) => AdminUserDetail(
    person: AdminPerson.fromJson(j['person'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
    createdAt: _date(j['created_at']),
    bio: j['bio'] as String?,
    isAdmin: j['is_admin'] == true,
    banReason: j['ban_reason'] as String?,
    listings: (j['listings'] as num?)?.toInt() ?? 0,
    comments: (j['comments'] as num?)?.toInt() ?? 0,
    reportsOpen: (j['reports_open'] as num?)?.toInt() ?? 0,
    reportsTotal: (j['reports_total'] as num?)?.toInt() ?? 0,
    history: <HistoryEntry>[
      for (final Object? h in (j['history'] as List<dynamic>? ?? const <dynamic>[]))
        if (h is Map<String, dynamic>) HistoryEntry.fromJson(h),
    ],
  );

  final AdminPerson person;
  final DateTime? createdAt;
  final String? bio;
  final bool isAdmin;
  final String? banReason;
  final int listings;
  final int comments;
  final int reportsOpen;
  final int reportsTotal;
  final List<HistoryEntry> history;
}

/// Per la persona: avvisi del Team Piazly e ban in corso.
class ModerationNotice {
  const ModerationNotice({required this.id, required this.kind, required this.message, this.until});

  factory ModerationNotice.fromJson(Map<String, dynamic> j) => ModerationNotice(
    id: j['id'] as String? ?? '',
    kind: j['kind'] as String? ?? 'warning',
    message: j['message'] as String? ?? '',
    until: _until(j['until']),
  );

  final String id;
  final String kind;
  final String message;
  final DateTime? until;

  String get title => switch (kind) {
    'ban' => 'Account sospeso',
    'unban' => 'Account di nuovo attivo',
    'removed' => 'Contenuto tolto',
    _ => 'Avviso del Team Piazly',
  };
}

class ModerationState {
  const ModerationState({this.bannedUntil, this.banReason, this.notices = const <ModerationNotice>[]});

  factory ModerationState.fromJson(Map<String, dynamic> j) => ModerationState(
    bannedUntil: _until(j['banned_until']),
    banReason: j['ban_reason'] as String?,
    notices: <ModerationNotice>[
      for (final Object? n in (j['notices'] as List<dynamic>? ?? const <dynamic>[]))
        if (n is Map<String, dynamic>) ModerationNotice.fromJson(n),
    ],
  );

  final DateTime? bannedUntil;
  final String? banReason;
  final List<ModerationNotice> notices;

  bool bannedAt(DateTime now) => bannedUntil != null && bannedUntil!.isAfter(now);
}
