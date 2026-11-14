/// Profilo (Fase 2, Blocco 2): dati, regole di validazione e reti social ammesse.
///
/// Le stesse regole le applica il server (migrazione 0003): qui servono a dare subito
/// all'utente un messaggio chiaro, senza aspettare la risposta.
library;

enum SocialNetwork {
  instagram('Instagram', 'https://instagram.com/'),
  tiktok('TikTok', 'https://www.tiktok.com/@'),
  facebook('Facebook', 'https://www.facebook.com/'),
  x('X', 'https://x.com/'),
  youtube('YouTube', 'https://www.youtube.com/@'),
  linkedin('LinkedIn', 'https://www.linkedin.com/in/');

  const SocialNetwork(this.label, this.urlPrefix);

  final String label;
  final String urlPrefix;

  /// Chiave usata dal server (`social_links`).
  String get key => name;

  String profileUrl(String handle) => '$urlPrefix$handle';

  static SocialNetwork? fromKey(String key) {
    for (final SocialNetwork n in values) {
      if (n.key == key) return n;
    }
    return null;
  }
}

abstract final class ProfileRules {
  static const int bioMaxLength = 300;

  static const Set<String> _reserved = <String>{
    'admin', 'administrator', 'amministratore', 'piazly', 'nexus', 'nexussocial',
    'support', 'supporto', 'assistenza', 'help', 'aiuto', 'staff', 'moderatore',
    'moderator', 'official', 'ufficiale', 'root', 'system', 'sistema',
  };

  /// @username in forma standard (minuscole, senza «@»), oppure null se non valido.
  static String? normalizeUsername(String input) {
    String v = input.trim().toLowerCase();
    if (v.startsWith('@')) v = v.substring(1);
    if (!RegExp(r'^[a-z0-9._]{3,24}$').hasMatch(v)) return null;
    if (v.startsWith('.') || v.endsWith('.') || v.contains('..')) return null;
    return v;
  }

  static bool isReservedUsername(String normalized) =>
      _reserved.contains(normalized) || normalized.startsWith('piazly');

  /// Messaggio d'errore per il nome utente, o null se va bene.
  static String? usernameError(String input) {
    final String? v = normalizeUsername(input);
    if (v == null) {
      return 'Da 3 a 24 caratteri: lettere minuscole, numeri, punto e trattino basso.';
    }
    if (isReservedUsername(v)) return 'Questo nome utente non è disponibile.';
    return null;
  }

  static String? fullNameError(String input) {
    final int n = input.trim().length;
    if (n < 2 || n > 80) return 'Scrivi nome e cognome (da 2 a 80 caratteri).';
    return null;
  }

  static String? bioError(String input) =>
      input.trim().length > bioMaxLength ? 'Massimo $bioMaxLength caratteri.' : null;

  /// Nome utente social: solo l'handle, non un link.
  static String? normalizeSocialHandle(String input) {
    String v = input.trim();
    if (v.startsWith('@')) v = v.substring(1);
    if (v.isEmpty) return '';
    if (!RegExp(r'^[A-Za-z0-9._-]{1,50}$').hasMatch(v)) return null;
    return v;
  }

  static String? businessNameError(String input) {
    final int n = input.trim().length;
    if (n < 2 || n > 100) return 'Scrivi la ragione sociale (da 2 a 100 caratteri).';
    return null;
  }

  /// Partita IVA italiana: 11 cifre con cifra di controllo.
  static bool isValidPartitaIva(String input) {
    final String v = input.replaceAll(' ', '');
    if (!RegExp(r'^\d{11}$').hasMatch(v) || v == '00000000000') return false;
    int sum = 0;
    for (int i = 0; i < 10; i++) {
      int d = int.parse(v[i]);
      if (i.isOdd) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return (10 - sum % 10) % 10 == int.parse(v[10]);
  }

  /// Nome mostrato in pubblico: nome e iniziale del cognome («Carlo C.»), come il server.
  static String shortPublicName(String fullName) {
    final List<String> parts =
        fullName.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.length < 2) return fullName.trim();
    return '${parts[0]} ${parts[1][0].toUpperCase()}.';
  }
}

Map<SocialNetwork, String> _socialFromJson(Object? raw) {
  final Map<SocialNetwork, String> out = <SocialNetwork, String>{};
  if (raw is Map) {
    raw.forEach((Object? k, Object? v) {
      final SocialNetwork? n = k is String ? SocialNetwork.fromKey(k) : null;
      if (n != null && v is String && v.isNotEmpty) out[n] = v;
    });
  }
  return out;
}

Map<String, String> socialToJson(Map<SocialNetwork, String> links) => <String, String>{
  for (final MapEntry<SocialNetwork, String> e in links.entries)
    if (e.value.isNotEmpty) e.key.key: e.value,
};

/// Profilo visto dagli altri (R2.10): mai nome completo, data di nascita o dati aziendali
/// (P4: ragione sociale e partita IVA protette fino alla decisione della Fase 6).
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.isBusiness,
    required this.username,
    required this.publicName,
    this.avatarPath,
    this.avatarThumbPath,
    this.bio,
    this.social = const <SocialNetwork, String>{},
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
    id: json['id'] as String,
    isBusiness: json['account_type'] == 'business',
    username: json['username'] as String,
    publicName: (json['public_name'] as String?) ?? '',
    avatarPath: json['avatar_path'] as String?,
    avatarThumbPath: json['avatar_thumb_path'] as String?,
    bio: json['bio'] as String?,
    social: _socialFromJson(json['social_links']),
  );

  final String id;
  final bool isBusiness;
  final String username;
  final String publicName;
  final String? avatarPath;
  final String? avatarThumbPath;

  /// Null se l'utente l'ha nascosta (P3) o non l'ha scritta.
  final String? bio;
  final Map<SocialNetwork, String> social;
}

enum BusinessStatus { pending, verified, rejected }

/// Il proprio profilo completo, dati privati compresi.
class MyProfile {
  const MyProfile({
    required this.id,
    required this.isBusiness,
    required this.username,
    required this.publicName,
    required this.fullName,
    this.birthDate,
    this.businessName,
    this.vatNumber,
    this.businessStatus,
    this.avatarPath,
    this.avatarThumbPath,
    this.bio,
    this.social = const <SocialNetwork, String>{},
    this.showBio = true,
    this.showSocial = true,
  });

  factory MyProfile.fromJson(Map<String, dynamic> json) => MyProfile(
    id: json['id'] as String,
    isBusiness: json['account_type'] == 'business',
    username: json['username'] as String,
    publicName: (json['public_name'] as String?) ?? '',
    fullName: (json['full_name'] as String?) ?? '',
    birthDate: json['birth_date'] == null
        ? null
        : DateTime.tryParse(json['birth_date'] as String),
    businessName: json['business_name'] as String?,
    vatNumber: json['vat_number'] as String?,
    businessStatus: switch (json['business_status']) {
      'verified' => BusinessStatus.verified,
      'rejected' => BusinessStatus.rejected,
      'pending' => BusinessStatus.pending,
      _ => null,
    },
    avatarPath: json['avatar_path'] as String?,
    avatarThumbPath: json['avatar_thumb_path'] as String?,
    bio: json['bio'] as String?,
    social: _socialFromJson(json['social_links']),
    showBio: json['show_bio'] as bool? ?? true,
    showSocial: json['show_social'] as bool? ?? true,
  );

  final String id;
  final bool isBusiness;
  final String username;
  final String publicName;
  final String fullName;
  final DateTime? birthDate;
  final String? businessName;
  final String? vatNumber;
  final BusinessStatus? businessStatus;
  final String? avatarPath;
  final String? avatarThumbPath;
  final String? bio;
  final Map<SocialNetwork, String> social;
  final bool showBio;
  final bool showSocial;

  /// Come gli altri vedono questo profilo, con gli interruttori applicati (P3).
  PublicProfile asSeenByOthers() => PublicProfile(
    id: id,
    isBusiness: isBusiness,
    username: username,
    publicName: publicName,
    avatarPath: avatarPath,
    avatarThumbPath: avatarThumbPath,
    bio: showBio ? bio : null,
    social: showSocial ? social : const <SocialNetwork, String>{},
  );
}

/// Dati della creazione del profilo (dopo l'accesso).
class NewProfile {
  const NewProfile({
    required this.username,
    required this.fullName,
    required this.birthDate,
    required this.isBusiness,
    this.businessName,
    this.vatNumber,
  });

  final String username;
  final String fullName;
  final DateTime birthDate;
  final bool isBusiness;
  final String? businessName;
  final String? vatNumber;
}

/// Dati modificabili del profilo.
class ProfileUpdate {
  const ProfileUpdate({
    required this.username,
    required this.fullName,
    this.bio,
    this.social = const <SocialNetwork, String>{},
    this.showBio = true,
    this.showSocial = true,
    this.businessName,
  });

  final String username;
  final String fullName;
  final String? bio;
  final Map<SocialNetwork, String> social;
  final bool showBio;
  final bool showSocial;
  final String? businessName;
}
