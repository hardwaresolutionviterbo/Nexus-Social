import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'listing_models.dart';
import 'social_models.dart';

/// Condivisione di un annuncio sui social e nelle altre app (anticipata dalla fase finale
/// del PDF, decisione del titolare). Mai la posizione: né punto, né zona, né distanza.
/// Il link che apre l'annuncio nell'app arriverà con la pagina web (F10: niente link
/// diretti all'app per ora).
abstract final class ListingShare {
  static String text(NearbyListing listing, {ListingSocial? social}) {
    final StringBuffer b = StringBuffer('«${listing.title}»');
    if (listing.details.trim().isNotEmpty) b.write('\n${listing.details.trim()}');
    final int? spots = social?.groupSpots;
    if (spots != null) b.write('\n${missingLabel(spots, social!.participants)}');
    b.write('\n\nL\'ho trovato su Piazly, la mappa sociale della tua zona.');
    return b.toString();
  }
}

/// Apre il foglio di condivisione del telefono. Nei test si sostituisce.
typedef ShareListing = Future<void> Function(String text, {Uint8List? photo});

Future<void> shareWithSystem(String text, {Uint8List? photo}) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: 'Annuncio su Piazly',
      files: photo == null
          ? null
          : <XFile>[XFile.fromData(photo, mimeType: 'image/jpeg', name: 'piazly.jpg')],
    ),
  );
}
