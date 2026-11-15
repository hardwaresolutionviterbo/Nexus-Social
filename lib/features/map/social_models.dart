import 'package:flutter/foundation.dart';

/// Reazione a un annuncio: una sola per persona, sostituibile o rimovibile.
enum Reaction {
  like('like', 'Mi piace'),
  dislike('dislike', 'Non mi piace');

  const Reaction(this.serverValue, this.label);

  final String serverValue;
  final String label;

  static Reaction? fromServer(Object? value) => switch (value) {
    'like' => Reaction.like,
    'dislike' => Reaction.dislike,
    _ => null,
  };
}

/// Elenchi di persone di un annuncio: chi ha messo Mi piace / Non mi piace, chi partecipa.
enum PeopleList {
  likes('like', 'Mi piace'),
  dislikes('dislike', 'Non mi piace'),
  participants('participant', 'Partecipano');

  const PeopleList(this.serverValue, this.title);

  final String serverValue;
  final String title;
}

/// Regole dell'interazione (il server le ripete).
abstract final class SocialRules {
  static const int commentMax = 1000;
  static const int maxGroupSpots = 50;
}

/// Conteggi e stato personale di un annuncio (`listing_social`).
@immutable
class ListingSocial {
  const ListingSocial({
    this.likes = 0,
    this.dislikes = 0,
    this.comments = 0,
    this.participants = 0,
    this.groupSpots,
    this.myReaction,
    this.iParticipate = false,
    this.following = false,
    this.muted = false,
  });

  factory ListingSocial.fromJson(Map<String, dynamic> json) => ListingSocial(
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    dislikes: (json['dislikes'] as num?)?.toInt() ?? 0,
    comments: (json['comments'] as num?)?.toInt() ?? 0,
    participants: (json['participants'] as num?)?.toInt() ?? 0,
    groupSpots: (json['group_spots'] as num?)?.toInt(),
    myReaction: Reaction.fromServer(json['my_reaction']),
    iParticipate: json['i_participate'] as bool? ?? false,
    following: json['following'] as bool? ?? false,
    muted: json['muted'] as bool? ?? false,
  );

  final int likes;
  final int dislikes;
  final int comments;
  final int participants;

  /// Persone cercate oltre all'autore; null se non è un evento di gruppo.
  final int? groupSpots;
  final Reaction? myReaction;
  final bool iParticipate;
  final bool following;
  final bool muted;

  bool get isEvent => groupSpots != null;
  int get missing => isEvent ? (groupSpots! - participants).clamp(0, groupSpots!) : 0;
  bool get full => isEvent && missing == 0;

  /// Cambia la reazione come fa il pulsante: stessa reazione = togli.
  ListingSocial withReaction(Reaction? r) {
    int likes = this.likes;
    int dislikes = this.dislikes;
    if (myReaction == Reaction.like) likes--;
    if (myReaction == Reaction.dislike) dislikes--;
    if (r == Reaction.like) likes++;
    if (r == Reaction.dislike) dislikes++;
    return ListingSocial(
      likes: likes,
      dislikes: dislikes,
      comments: comments,
      participants: participants,
      groupSpots: groupSpots,
      myReaction: r,
      iParticipate: iParticipate,
      following: following,
      muted: muted,
    );
  }

  ListingSocial copyWith({int? participants, bool? iParticipate, bool? muted, int? comments}) =>
      ListingSocial(
        likes: likes,
        dislikes: dislikes,
        comments: comments ?? this.comments,
        participants: participants ?? this.participants,
        groupSpots: groupSpots,
        myReaction: myReaction,
        iParticipate: iParticipate ?? this.iParticipate,
        following: following,
        muted: muted ?? this.muted,
      );
}

/// «mancano 3 persone», «manca 1 persona», «al completo».
String missingLabel(int groupSpots, int participants) {
  final int missing = (groupSpots - participants).clamp(0, groupSpots);
  if (missing == 0) return 'Al completo';
  return missing == 1 ? 'Manca 1 persona' : 'Mancano $missing persone';
}

/// Una persona in un elenco (profilo pubblico essenziale).
@immutable
class PersonRef {
  const PersonRef({
    required this.id,
    required this.username,
    required this.publicName,
    this.avatarThumbPath,
  });

  final String id;
  final String username;
  final String publicName;
  final String? avatarThumbPath;

  String get initial {
    final String s = publicName.trim().isNotEmpty ? publicName.trim() : username;
    return s.isEmpty ? '?' : s.substring(0, 1).toUpperCase();
  }
}

@immutable
class ListingComment {
  const ListingComment({
    required this.id,
    this.parentId,
    required this.body,
    required this.createdAt,
    required this.author,
    this.likes = 0,
    this.likedByMe = false,
    this.isMine = false,
    this.canDelete = false,
  });

  factory ListingComment.fromJson(Map<String, dynamic> json) => ListingComment(
    id: json['id'] as String,
    parentId: json['parent_id'] as String?,
    body: json['body'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    author: PersonRef(
      id: json['author_id'] as String,
      username: json['author_username'] as String? ?? '',
      publicName: json['author_public_name'] as String? ?? '',
      avatarThumbPath: json['author_avatar_thumb_path'] as String?,
    ),
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    likedByMe: json['liked_by_me'] as bool? ?? false,
    isMine: json['is_mine'] as bool? ?? false,
    canDelete: json['can_delete'] as bool? ?? false,
  );

  final String id;

  /// Commento principale a cui risponde; null per un commento principale.
  final String? parentId;
  final String body;
  final DateTime createdAt;
  final PersonRef author;
  final int likes;
  final bool likedByMe;
  final bool isMine;
  final bool canDelete;
}

/// Commenti principali seguiti dalle loro risposte, in ordine di tempo (come Facebook).
List<(ListingComment, List<ListingComment>)> threadComments(List<ListingComment> all) {
  final List<ListingComment> roots = <ListingComment>[
    for (final ListingComment c in all)
      if (c.parentId == null) c,
  ]..sort((ListingComment a, ListingComment b) => a.createdAt.compareTo(b.createdAt));
  return <(ListingComment, List<ListingComment>)>[
    for (final ListingComment root in roots)
      (
        root,
        <ListingComment>[
          for (final ListingComment c in all)
            if (c.parentId == root.id) c,
        ]..sort((ListingComment a, ListingComment b) => a.createdAt.compareTo(b.createdAt)),
      ),
  ];
}

enum NotificationKind {
  listingLike('listing_like'),
  listingComment('listing_comment'),
  commentReply('comment_reply'),
  followedComment('followed_comment'),
  commentLike('comment_like');

  const NotificationKind(this.serverValue);

  final String serverValue;

  static NotificationKind fromServer(String? v) => NotificationKind.values.firstWhere(
    (NotificationKind k) => k.serverValue == v,
    orElse: () => NotificationKind.listingComment,
  );
}

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.listingId,
    required this.listingTitle,
    this.commentId,
    this.commentExcerpt,
    required this.actor,
    this.actorCount = 1,
    required this.createdAt,
    this.read = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    kind: NotificationKind.fromServer(json['kind'] as String?),
    listingId: json['listing_id'] as String,
    listingTitle: json['listing_title'] as String? ?? '',
    commentId: json['comment_id'] as String?,
    commentExcerpt: json['comment_excerpt'] as String?,
    actor: PersonRef(
      id: json['actor_id'] as String,
      username: json['actor_username'] as String? ?? '',
      publicName: json['actor_public_name'] as String? ?? '',
      avatarThumbPath: json['actor_avatar_thumb_path'] as String?,
    ),
    actorCount: (json['actor_count'] as num?)?.toInt() ?? 1,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    read: json['read'] as bool? ?? false,
  );

  final String id;
  final NotificationKind kind;
  final String listingId;
  final String listingTitle;
  final String? commentId;
  final String? commentExcerpt;

  /// Ultima persona che ha agito; per i Mi piace raggruppati [actorCount] è il totale.
  final PersonRef actor;
  final int actorCount;
  final DateTime createdAt;
  final bool read;

  AppNotification markedRead() => AppNotification(
    id: id,
    kind: kind,
    listingId: listingId,
    listingTitle: listingTitle,
    commentId: commentId,
    commentExcerpt: commentExcerpt,
    actor: actor,
    actorCount: actorCount,
    createdAt: createdAt,
    read: true,
  );

  /// Testo della notifica, senza dati oltre al nome abbreviato.
  String get text {
    final String who = actorCount > 1
        ? '${actor.publicName} e ${actorCount - 1 == 1 ? 'un\'altra persona' : 'altre ${actorCount - 1} persone'}'
        : actor.publicName;
    return switch (kind) {
      NotificationKind.listingLike => '$who ${actorCount > 1 ? 'hanno' : 'ha'} messo Mi piace al tuo annuncio «$listingTitle»',
      NotificationKind.listingComment => '$who ha commentato il tuo annuncio «$listingTitle»',
      NotificationKind.commentReply => '$who ha risposto al tuo commento su «$listingTitle»',
      NotificationKind.followedComment => '$who ha commentato «$listingTitle», che segui',
      NotificationKind.commentLike => '$who ${actorCount > 1 ? 'hanno' : 'ha'} messo Mi piace al tuo commento su «$listingTitle»',
    };
  }
}
