import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import 'listing_models.dart' show ReportReason;
import 'listing_repository.dart';
import 'social_models.dart';

/// Eventi, reazioni, commenti e notifiche (migrazione 0009). Nei test: versione finta.
abstract class SocialRepository {
  Future<ListingSocial> social(String listingId);

  /// null = togli la reazione.
  Future<void> react(String listingId, Reaction? reaction);

  Future<List<PersonRef>> people(String listingId, PeopleList list);

  Future<void> join(String listingId);

  Future<void> leave(String listingId);

  Future<List<ListingComment>> comments(String listingId);

  Future<String> addComment(String listingId, String body, {String? parentId});

  Future<void> deleteComment(String commentId);

  Future<void> likeComment(String commentId, bool like);

  /// Modifica del proprio commento (Fase 5, Blocco 5).
  Future<void> editComment(String commentId, String body);

  /// Nascondi o rimostra: autore dell'annuncio o moderazione.
  Future<void> setCommentHidden(String commentId, bool hidden);

  Future<void> reportComment(String commentId, ReportReason reason, {String? details});

  /// «Disattiva notifiche per questo post».
  Future<void> setMuted(String listingId, bool muted);

  Future<List<AppNotification>> notifications();

  Future<int> unreadCount();

  Future<void> markAllRead();
}

class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String name, [Map<String, Object?>? params]) async {
    try {
      return await _client.rpc(name, params: params);
    } on PostgrestException catch (e) {
      throw failureFor(e.code, e.message);
    } catch (_) {
      throw const ListingFailure('Qualcosa non ha funzionato. Riprova.');
    }
  }

  static ListingFailure failureFor(String? code, String message) {
    if (code == '22023') return ListingFailure('$message.');
    if (message.contains('non trovato')) {
      return const ListingFailure('Annuncio o commento non più disponibile.');
    }
    return SupabaseMapListingRepository.failureFor(code, message);
  }

  static List<Map<String, dynamic>> _rows(Object? data) => <Map<String, dynamic>>[
    if (data is List)
      for (final Object? row in data)
        if (row is Map<String, dynamic>) row,
  ];

  @override
  Future<ListingSocial> social(String listingId) async {
    final Object? data = await _rpc('listing_social', <String, Object?>{'p_listing': listingId});
    return data is Map<String, dynamic> ? ListingSocial.fromJson(data) : const ListingSocial();
  }

  @override
  Future<void> react(String listingId, Reaction? reaction) async {
    await _rpc('set_listing_reaction', <String, Object?>{
      'p_listing': listingId,
      'p_kind': reaction?.serverValue,
    });
  }

  @override
  Future<List<PersonRef>> people(String listingId, PeopleList list) async {
    final Object? data = await _rpc('listing_people', <String, Object?>{
      'p_listing': listingId,
      'p_what': list.serverValue,
    });
    return <PersonRef>[
      for (final Map<String, dynamic> r in _rows(data))
        PersonRef(
          id: r['user_id'] as String,
          username: r['username'] as String? ?? '',
          publicName: r['public_name'] as String? ?? '',
          avatarThumbPath: r['avatar_thumb_path'] as String?,
        ),
    ];
  }

  @override
  Future<void> join(String listingId) async {
    await _rpc('join_listing', <String, Object?>{'p_listing': listingId});
  }

  @override
  Future<void> leave(String listingId) async {
    await _rpc('leave_listing', <String, Object?>{'p_listing': listingId});
  }

  @override
  Future<List<ListingComment>> comments(String listingId) async {
    final Object? data = await _rpc('listing_comments_list', <String, Object?>{
      'p_listing': listingId,
    });
    return <ListingComment>[for (final Map<String, dynamic> r in _rows(data)) ListingComment.fromJson(r)];
  }

  @override
  Future<String> addComment(String listingId, String body, {String? parentId}) async {
    final Object? id = await _rpc('add_listing_comment', <String, Object?>{
      'p_listing': listingId,
      'p_body': body.trim(),
      'p_parent': parentId,
    });
    return '$id';
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _rpc('delete_my_comment', <String, Object?>{'p_comment': commentId});
  }

  @override
  Future<void> likeComment(String commentId, bool like) async {
    await _rpc('set_comment_like', <String, Object?>{'p_comment': commentId, 'p_like': like});
  }

  @override
  Future<void> editComment(String commentId, String body) async {
    await _rpc('edit_my_comment', <String, Object?>{'p_comment': commentId, 'p_body': body.trim()});
  }

  @override
  Future<void> setCommentHidden(String commentId, bool hidden) async {
    await _rpc('set_comment_hidden', <String, Object?>{'p_comment': commentId, 'p_hidden': hidden});
  }

  @override
  Future<void> reportComment(String commentId, ReportReason reason, {String? details}) async {
    await _rpc('report_comment', <String, Object?>{
      'p_comment': commentId,
      'p_reason': reason.serverValue,
      'p_details': details?.trim().isEmpty ?? true ? null : details!.trim(),
    });
  }

  @override
  Future<void> setMuted(String listingId, bool muted) async {
    await _rpc('set_listing_muted', <String, Object?>{'p_listing': listingId, 'p_muted': muted});
  }

  @override
  Future<List<AppNotification>> notifications() async {
    final Object? data = await _rpc('my_notifications', <String, Object?>{'p_limit': 100});
    return <AppNotification>[
      for (final Map<String, dynamic> r in _rows(data)) AppNotification.fromJson(r),
    ];
  }

  @override
  Future<int> unreadCount() async {
    final Object? n = await _rpc('unread_notifications_count');
    return n is num ? n.toInt() : 0;
  }

  @override
  Future<void> markAllRead() async {
    await _rpc('mark_notifications_read');
  }
}
