import 'package:nexus_social/features/admin/admin_models.dart';
import 'package:nexus_social/features/admin/admin_repository.dart';

/// Gestionale finto: segue le stesse regole del server (migrazione 0038).
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({this.accessState = const AdminAccess(admin: true, role: 'owner', pin: true)});

  AdminAccess accessState;
  final List<AdminReport> open = <AdminReport>[];
  final List<AdminReport> closed = <AdminReport>[];
  final Map<String, AdminUserDetail> users = <String, AdminUserDetail>{};
  final List<String> calls = <String>[];
  final List<(String user, String message)> warnings = <(String, String)>[];

  void addUser(AdminPerson p, {int reportsOpen = 0}) {
    users[p.id] = AdminUserDetail(person: p, createdAt: DateTime(2026, 10, 1), reportsOpen: reportsOpen, listings: 2);
  }

  void _guard() {
    if (!accessState.admin) throw const AdminFailure('Operazione permessa solo agli amministratori.');
    if (!accessState.pin) throw const AdminFailure('Per il gestionale serve la verifica in due passaggi (PIN).');
  }

  void _log(String user, String action, {String? reason, DateTime? until}) {
    final AdminUserDetail? d = users[user];
    if (d == null) return;
    users[user] = AdminUserDetail(
      person: d.person,
      createdAt: d.createdAt,
      listings: d.listings,
      comments: d.comments,
      reportsOpen: d.reportsOpen,
      reportsTotal: d.reportsTotal,
      banReason: action == 'ban' ? reason : (action == 'unban' ? null : d.banReason),
      history: <HistoryEntry>[
        HistoryEntry(action: action, reason: reason, until: until, at: DateTime(2026, 11, 24, 10), by: 'madness88'),
        ...d.history,
      ],
    );
  }

  void _setBan(String user, DateTime? until) {
    final AdminUserDetail? d = users[user];
    if (d == null) return;
    final AdminPerson p = d.person;
    users[user] = AdminUserDetail(
      person: AdminPerson(id: p.id, username: p.username, name: p.name, business: p.business, bannedUntil: until),
      createdAt: d.createdAt,
      listings: d.listings,
      reportsOpen: d.reportsOpen,
      banReason: d.banReason,
      history: d.history,
    );
  }

  @override
  Future<AdminAccess> access() async => accessState;

  @override
  Future<List<AdminReport>> reports({bool closed = false}) async {
    _guard();
    return List<AdminReport>.of(closed ? this.closed : open);
  }

  @override
  Future<void> resolve(
    AdminReport report,
    ReportAction action, {
    String? message,
    BanLength? ban,
    bool removeContent = false,
  }) async {
    _guard();
    if (action == ReportAction.warn && (message ?? '').trim().length < 3) {
      throw const AdminFailure('Scrivi il testo dell\'avviso.');
    }
    calls.add('${action.key}:${report.id}${removeContent ? ':togli' : ''}${ban != null ? ':${ban.days}' : ''}');
    open.removeWhere((AdminReport r) => r.id == report.id);
    closed.insert(0, report);
    final String? author = report.author?.id;
    if (author != null && action == ReportAction.ban) {
      await this.ban(author, ban ?? BanLength.week, message ?? '');
    } else if (author != null && action == ReportAction.warn) {
      await warn(author, message!);
    }
  }

  @override
  Future<List<AdminPerson>> searchUsers(String query) async {
    _guard();
    final String q = query.trim().toLowerCase();
    return <AdminPerson>[
      for (final AdminUserDetail d in users.values)
        if (q.isEmpty || d.person.username.contains(q) || d.person.name.toLowerCase().contains(q)) d.person,
    ];
  }

  @override
  Future<AdminUserDetail?> user(String id) async {
    _guard();
    return users[id];
  }

  @override
  Future<DateTime?> ban(String id, BanLength length, String reason) async {
    _guard();
    final DateTime until = length.days == null
        ? DateTime(9999)
        : DateTime(2026, 11, 24, 10).add(Duration(days: length.days!));
    calls.add('ban:$id:${length.days}');
    _log(id, 'ban', reason: reason, until: until);
    _setBan(id, until);
    return until;
  }

  @override
  Future<void> unban(String id, {String? reason}) async {
    _guard();
    calls.add('unban:$id');
    _log(id, 'unban');
    _setBan(id, null);
  }

  @override
  Future<void> warn(String id, String message) async {
    _guard();
    calls.add('warn:$id');
    warnings.add((id, message));
    _log(id, 'warn', reason: message);
  }
}

class FakeModerationRepository implements ModerationRepository {
  FakeModerationRepository([this.state]);

  ModerationState? state;
  int reads = 0;

  @override
  Future<ModerationState?> mine() async => state;

  @override
  Future<void> markRead() async {
    reads++;
    final ModerationState? s = state;
    if (s != null) state = ModerationState(bannedUntil: s.bannedUntil, banReason: s.banReason);
  }
}

AdminPerson samplePerson({String id = 'u1', String username = 'luca.r', DateTime? bannedUntil}) =>
    AdminPerson(id: id, username: username, name: 'Luca R.', bannedUntil: bannedUntil);

AdminReport sampleListingReport({String id = 'r-annuncio', AdminPerson? author}) => AdminReport(
  kind: ReportKind.listing,
  id: id,
  count: 3,
  reasons: const <String>['truffa', 'spam'],
  details: const <String>['Chiede un anticipo con bonifico'],
  lastAt: DateTime(2026, 11, 24, 9, 30),
  title: 'iPhone nuovo a 100 €',
  text: 'Scrivimi in privato, pagamento anticipato.',
  state: 'active',
  author: author ?? samplePerson(),
);

AdminReport sampleCommentReport({String id = 'r-commento'}) => AdminReport(
  kind: ReportKind.comment,
  id: id,
  count: 1,
  reasons: const <String>['spam'],
  lastAt: DateTime(2026, 11, 24, 8),
  text: 'Guadagna 500 € al giorno, link in bio!',
  contextTitle: 'Calcetto stasera?',
  author: samplePerson(id: 'u2', username: 'promo.facile'),
);

AdminReport sampleChatReport({String id = 'r-chat'}) => AdminReport(
  kind: ReportKind.chat,
  id: id,
  count: 1,
  reasons: const <String>['molestie'],
  details: const <String>['Insiste dopo che ho detto no'],
  lastAt: DateTime(2026, 11, 23, 22),
  messages: <ReportedMessage>[
    ReportedMessage(text: 'Rispondi!', fromReporter: false, at: DateTime(2026, 11, 23, 21, 50)),
    ReportedMessage(text: 'Lasciami stare, grazie.', fromReporter: true, at: DateTime(2026, 11, 23, 21, 52)),
  ],
  author: samplePerson(id: 'u3', username: 'marco.b'),
);
