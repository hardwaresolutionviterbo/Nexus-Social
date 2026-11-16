import 'package:nexus_social/features/map/listing_models.dart' show ReportReason;
import 'package:nexus_social/features/map/listing_repository.dart';
import 'package:nexus_social/features/map/social_models.dart';
import 'package:nexus_social/features/map/social_repository.dart';

/// Interazioni finte in memoria: nessun server. Io sono «me».
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository({ListingSocial? initial}) : state = initial ?? const ListingSocial();

  ListingSocial state;
  final List<ListingComment> items = <ListingComment>[];
  final List<AppNotification> inbox = <AppNotification>[];
  final List<String> calls = <String>[];
  final Map<PeopleList, List<PersonRef>> lists = <PeopleList, List<PersonRef>>{};
  String? failWith;
  int _next = 0;

  static const PersonRef me = PersonRef(id: 'me', username: 'io_prova', publicName: 'Io P.');

  void _maybeFail() {
    final String? f = failWith;
    if (f != null) {
      failWith = null;
      throw ListingFailure(f);
    }
  }

  @override
  Future<ListingSocial> social(String listingId) async {
    calls.add('social:$listingId');
    return state.copyWith(comments: items.length);
  }

  @override
  Future<void> react(String listingId, Reaction? reaction) async {
    calls.add('react:${reaction?.serverValue}');
    _maybeFail();
    state = state.withReaction(reaction);
  }

  @override
  Future<List<PersonRef>> people(String listingId, PeopleList list) async {
    calls.add('people:${list.serverValue}');
    return lists[list] ?? const <PersonRef>[];
  }

  @override
  Future<void> join(String listingId) async {
    calls.add('join');
    _maybeFail();
    state = state.copyWith(participants: state.participants + 1, iParticipate: true);
  }

  @override
  Future<void> leave(String listingId) async {
    calls.add('leave');
    state = state.copyWith(participants: state.participants - 1, iParticipate: false);
  }

  @override
  Future<List<ListingComment>> comments(String listingId) async => List<ListingComment>.of(items);

  @override
  Future<String> addComment(String listingId, String body, {String? parentId}) async {
    _maybeFail();
    final String id = 'c${++_next}';
    String? parent = parentId;
    // Un livello solo, come il server.
    final ListingComment? p = items.where((ListingComment c) => c.id == parentId).firstOrNull;
    if (p?.parentId != null) parent = p!.parentId;
    items.add(ListingComment(
      id: id,
      parentId: parent,
      body: body,
      createdAt: DateTime(2026, 11, 15, 10, 30).add(Duration(minutes: _next)),
      author: me,
      isMine: true,
      canDelete: true,
    ));
    calls.add('comment:$body:${parent ?? '-'}');
    state = state.copyWith(comments: items.length);
    return id;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    calls.add('delete:$commentId');
    items.removeWhere((ListingComment c) => c.id == commentId || c.parentId == commentId);
  }

  @override
  Future<void> likeComment(String commentId, bool like) async {
    calls.add('likeComment:$commentId:$like');
    final int i = items.indexWhere((ListingComment c) => c.id == commentId);
    final ListingComment c = items[i];
    items[i] = ListingComment(
      id: c.id,
      parentId: c.parentId,
      body: c.body,
      createdAt: c.createdAt,
      author: c.author,
      likes: c.likes + (like ? 1 : -1),
      likedByMe: like,
      isMine: c.isMine,
      canDelete: c.canDelete,
    );
  }

  @override
  Future<void> editComment(String commentId, String body) async {
    calls.add('edit:$commentId:$body');
    _maybeFail();
    final int i = items.indexWhere((ListingComment c) => c.id == commentId);
    items[i] = items[i].copyWith(body: body, edited: true);
  }

  @override
  Future<void> setCommentHidden(String commentId, bool hidden) async {
    calls.add('hidden:$commentId:$hidden');
    final int i = items.indexWhere((ListingComment c) => c.id == commentId);
    items[i] = items[i].copyWith(hidden: hidden);
  }

  @override
  Future<void> reportComment(String commentId, ReportReason reason, {String? details}) async {
    calls.add('reportComment:$commentId:${reason.serverValue}');
  }

  @override
  Future<void> setMuted(String listingId, bool muted) async {
    calls.add('muted:$muted');
    state = state.copyWith(muted: muted);
  }

  @override
  Future<List<AppNotification>> notifications() async => List<AppNotification>.of(inbox);

  @override
  Future<int> unreadCount() async => inbox.where((AppNotification n) => !n.read).length;

  @override
  Future<void> markAllRead() async {
    calls.add('markAllRead');
    for (int i = 0; i < inbox.length; i++) {
      inbox[i] = inbox[i].markedRead();
    }
  }
}

ListingComment commentBy(
  String id,
  String name,
  String body, {
  String? parentId,
  int minute = 0,
  int likes = 0,
  bool canDelete = false,
  bool isMine = false,
  bool edited = false,
  bool hidden = false,
  bool canHide = false,
}) => ListingComment(
  id: id,
  parentId: parentId,
  body: body,
  createdAt: DateTime(2026, 11, 15, 10, minute),
  author: PersonRef(id: 'u-$id', username: name.toLowerCase(), publicName: name),
  likes: likes,
  canDelete: canDelete,
  isMine: isMine,
  edited: edited,
  hidden: hidden,
  canHide: canHide,
);

AppNotification notificationOf(
  String id,
  NotificationKind kind, {
  int count = 1,
  String? commentId,
  bool read = false,
}) => AppNotification(
  id: id,
  kind: kind,
  listingId: 'n1',
  listingTitle: 'Calcetto stasera',
  commentId: commentId,
  actor: const PersonRef(id: 'u2', username: 'giulia_b', publicName: 'Giulia B.'),
  actorCount: count,
  createdAt: DateTime(2026, 11, 15, 10, 20),
  read: read,
);
