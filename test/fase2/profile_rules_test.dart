import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nexus_social/features/profile/avatar_images.dart';
import 'package:nexus_social/features/profile/profile_models.dart';
import 'package:nexus_social/features/profile/profile_repository.dart';

/// Regole del profilo (Fase 2, Blocco 2), uguali a quelle del server (migrazione 0003).
void main() {
  group('R2.3 · @username', () {
    test('normalizzato: minuscole, senza «@» e spazi', () {
      expect(ProfileRules.normalizeUsername('  @Carlo.Rossi_90 '), 'carlo.rossi_90');
    });

    test('rifiutati: troppo corti, caratteri non ammessi, punti ai bordi o doppi', () {
      for (final String bad in <String>['ab', 'carlo rossi', 'carlo-rossi', '.carlo', 'carlo.',
          'car..lo', 'àccento', 'a' * 25]) {
        expect(ProfileRules.normalizeUsername(bad), isNull, reason: bad);
        expect(ProfileRules.usernameError(bad), isNotNull, reason: bad);
      }
    });

    test('nomi riservati non disponibili (niente finti account ufficiali)', () {
      for (final String reserved in <String>['admin', 'Piazly', 'piazly_ufficiale', 'assistenza']) {
        expect(ProfileRules.usernameError(reserved), 'Questo nome utente non è disponibile.');
      }
      expect(ProfileRules.usernameError('carlo_r'), isNull);
    });
  });

  test('R2.3 · nome pubblico abbreviato come sul server («Carlo C.»)', () {
    expect(ProfileRules.shortPublicName('carlo   cattaneo'), 'carlo C.');
    expect(ProfileRules.shortPublicName('Carlo Cattaneo Rossi'), 'Carlo C.');
    expect(ProfileRules.shortPublicName('Carlo'), 'Carlo');
  });

  test('R2.4 · social: solo il nome utente, niente link', () {
    expect(ProfileRules.normalizeSocialHandle('@laura.b'), 'laura.b');
    expect(ProfileRules.normalizeSocialHandle(''), '');
    expect(ProfileRules.normalizeSocialHandle('https://evil.example/x'), isNull);
    expect(ProfileRules.normalizeSocialHandle('javascript:alert(1)'), isNull);
    expect(socialToJson(<SocialNetwork, String>{SocialNetwork.instagram: 'laura.b',
        SocialNetwork.x: ''}), <String, String>{'instagram': 'laura.b'});
  });

  test('S4 · partita IVA: 11 cifre con cifra di controllo', () {
    expect(ProfileRules.isValidPartitaIva('01234567897'), isTrue);
    expect(ProfileRules.isValidPartitaIva('01234567890'), isFalse);
    expect(ProfileRules.isValidPartitaIva('00000000000'), isFalse);
    expect(ProfileRules.isValidPartitaIva('1234567897'), isFalse);
  });

  test('P3 · anteprima pubblica: bio e social nascosti se spenti', () {
    final MyProfile me = MyProfile.fromJson(<String, dynamic>{
      'id': 'u1', 'account_type': 'private', 'username': 'laura_b', 'public_name': 'Laura B.',
      'full_name': 'Laura Bianchi', 'birth_date': '1985-11-20', 'bio': 'Ciao',
      'social_links': <String, dynamic>{'instagram': 'laura.b', 'sconosciuto': 'x'},
      'show_bio': false, 'show_social': true,
    });
    expect(me.social, <SocialNetwork, String>{SocialNetwork.instagram: 'laura.b'});
    final PublicProfile seen = me.asSeenByOthers();
    expect(seen.bio, isNull);
    expect(seen.social, isNotEmpty);
    expect(seen.publicName, 'Laura B.');
  });

  test('errori del server tradotti in messaggi chiari, senza dati tecnici', () {
    expect(SupabaseProfileRepository.failureFor('23505', 'duplicate key').message,
        'Questo nome utente è già preso: scegline un altro.');
    expect(SupabaseProfileRepository.failureFor('22023', 'Età minima 14 anni').message,
        'Età minima 14 anni.');
    expect(SupabaseProfileRepository.failureFor('XX000', 'stack trace interno').message,
        isNot(contains('stack')));
  });

  test('S5 · foto: quadrata 512 px e miniatura 128 px in JPEG', () {
    final img.Image source = img.Image(width: 900, height: 600);
    img.fill(source, color: img.ColorRgb8(255, 122, 26));
    final Uint8List png = img.encodePng(source);
    final AvatarImages out = AvatarImages.prepare(png);
    final img.Image big = img.decodeJpg(out.avatar)!;
    final img.Image small = img.decodeJpg(out.thumbnail)!;
    expect((big.width, big.height), (512, 512));
    expect((small.width, small.height), (128, 128));
    expect(out.avatar.length, lessThan(AvatarImages.maxBytes));
  });

  test('S5 · file che non è un\'immagine: messaggio chiaro', () {
    expect(() => AvatarImages.prepare(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<AvatarImageException>()));
  });
}
