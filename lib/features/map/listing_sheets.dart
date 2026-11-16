import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../chat/chat_thread_screen.dart' show openChatWith;
import '../privacy/privacy_repository.dart';
import '../profile/profile_models.dart';
import '../profile/profile_repository.dart';
import '../profile/public_profile_screen.dart';
import 'listing_form_screen.dart' show ListingPhotoView;
import 'listing_models.dart';
import 'listing_repository.dart';
import 'listing_share.dart';
import 'listing_social_panel.dart';
import 'social_models.dart' show missingLabel;
import 'social_repository.dart';

/// Servizi usati dalla scheda di un annuncio altrui.
class ListingSheetServices {
  const ListingSheetServices({
    required this.listings,
    this.profiles,
    this.privacy,
    this.social,
    this.share = shareWithSystem,
  });

  final MapListingRepository listings;

  /// Eventi, reazioni, commenti (Blocco 4); null finché il server non c'è.
  final SocialRepository? social;
  final ShareListing share;

  /// Profilo pubblico dell'autore (nome abbreviato, @username, social).
  final ProfileRepository? profiles;

  /// «Blocca» dal profilo dell'autore.
  final PrivacyRepository? privacy;
}

/// Apre la scheda di un annuncio (R3.8): autore, foto, testo, distanza approssimata,
/// «Contatta» e «Segnala annuncio». Restituisce true se l'autore è stato bloccato.
Future<bool?> showListingSheet(
  BuildContext context, {
  required NearbyListing listing,
  required ListingSheetServices services,
  DateTime Function() now = DateTime.now,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (BuildContext ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.62,
    minChildSize: 0.35,
    maxChildSize: 0.95,
    builder: (BuildContext ctx, ScrollController scroll) => ListingDetail(
      listing: listing,
      services: services,
      now: now(),
      scrollController: scroll,
    ),
  ),
);

class ListingDetail extends StatelessWidget {
  const ListingDetail({
    super.key,
    required this.listing,
    required this.services,
    required this.now,
    this.scrollController,
  });

  final NearbyListing listing;
  final ListingSheetServices services;
  final DateTime now;
  final ScrollController? scrollController;

  /// «Contatta»: chat cifrata con l'autore (Fase 4, Blocco 1).
  Future<void> _contact(BuildContext context) =>
      openChatWith(context, userId: listing.ownerId, name: listing.ownerPublicName);

  Future<void> _report(BuildContext context) async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ReportListingForm(listingId: listing.id, report: services.listings.report),
      ),
    );
    if ((sent ?? false) && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Grazie: la segnalazione è stata inviata alla moderazione.')),
        );
    }
  }

  Future<void> _openProfile(BuildContext context) async {
    final ProfileRepository? profiles = services.profiles;
    if (profiles == null) return;
    final NavigatorState nav = Navigator.of(context);
    final PublicProfile? profile = await profiles.fetchPublic(listing.ownerId);
    if (profile == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilo non disponibile.')),
        );
      }
      return;
    }
    final PrivacyRepository? privacy = services.privacy;
    bool blocked = false;
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfileScreen(
          profile: profile,
          repository: profiles,
          title: 'Profilo',
          onBlock: privacy == null
              ? null
              : () async {
                  await privacy.block(profile.id);
                  blocked = true;
                },
        ),
      ),
    );
    // Dopo un blocco l'annuncio sparisce: si chiude anche la scheda.
    if (blocked && nav.mounted) nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        _OwnerRow(listing: listing, profiles: services.profiles, onTap: () => _openProfile(context)),
        const SizedBox(height: AppSpacing.md),
        if (listing.photos.isNotEmpty) ...[
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: listing.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int i) => ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: listing.photos.length == 1 ? 320 : 240,
                  child: ListingPhotoView(path: listing.photos[i], repository: services.listings),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(listing.title, style: theme.textTheme.titleLarge),
        if (listing.details.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(listing.details, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (listing.groupSpots != null)
              _InfoChip(
                icon: Icons.groups_rounded,
                text: missingLabel(listing.groupSpots!, listing.participants),
                color: AppColors.brandMint,
              ),
            if (listing.availableNow)
              const _InfoChip(
                icon: Icons.bolt_rounded,
                text: 'Disponibile ora',
                color: AppColors.brandMint,
              ),
            _InfoChip(
              icon: Icons.near_me_outlined,
              text: distanceLabel(listing.distanceBandMeters),
              color: AppColors.brandCyan,
            ),
            _InfoChip(
              icon: listing.place == ListingPlace.chosenPoint
                  ? Icons.place_rounded
                  : Icons.blur_on_rounded,
              text: listing.place == ListingPlace.chosenPoint ? 'Punto d\'incontro' : 'Zona approssimata',
              color: AppColors.brandAmber,
            ),
            _InfoChip(
              icon: Icons.schedule_rounded,
              text: expiryLabel(listing.expiresAt, now),
              color: scheme.outline,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          publishedLabel(listing.createdAt, now),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        ListingSocialPanel(
          listing: SocialTarget.fromNearby(listing),
          downloadPhoto: services.listings.downloadPhoto,
          social: services.social,
          share: services.share,
        ),
        const SizedBox(height: AppSpacing.md),
        if (listing.isMine)
          Text(
            'È un tuo annuncio: lo gestisci da «I miei annunci».',
            key: const ValueKey<String>('annuncio_mio'),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          )
        else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _contact(context),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Contatta'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton.icon(
              onPressed: () => _report(context),
              icon: Icon(Icons.flag_outlined, color: scheme.error),
              label: Text('Segnala annuncio', style: TextStyle(color: scheme.error)),
            ),
          ),
        ],
      ],
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.listing, required this.profiles, required this.onTap});

  final NearbyListing listing;
  final ProfileRepository? profiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? thumb = listing.ownerAvatarThumbPath;
    final Widget initial = CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.brandOrange,
      foregroundColor: Colors.white,
      child: Text(listing.initial, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
    return InkWell(
      key: const ValueKey<String>('autore_annuncio'),
      borderRadius: BorderRadius.circular(16),
      onTap: profiles == null ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (thumb != null && profiles != null)
              FutureBuilder<Uint8List?>(
                future: profiles!.downloadAvatar(thumb),
                builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) =>
                    snap.data == null
                        ? initial
                        : CircleAvatar(radius: 24, backgroundImage: MemoryImage(snap.data!)),
              )
            else
              initial,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.ownerPublicName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${listing.ownerUsername}'
                    '${listing.ownerIsBusiness ? ' · Attività' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (profiles != null) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// Segnalazione di un annuncio: motivo da un elenco chiuso e dettagli facoltativi.
class ReportListingForm extends StatefulWidget {
  const ReportListingForm({
    super.key,
    required this.listingId,
    required this.report,
    this.title = 'Segnala annuncio',
  });

  /// «Segnala annuncio» o «Segnala commento» (Fase 5, Blocco 5).
  final String title;

  final String listingId;

  /// Invio al server (Mappa o Scambia & Vendi: stessa funzione).
  final Future<void> Function(String id, ReportReason reason, {String? details}) report;

  @override
  State<ReportListingForm> createState() => _ReportListingFormState();
}

class _ReportListingFormState extends State<ReportListingForm> {
  ReportReason? _reason;
  final TextEditingController _details = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ReportReason? reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Scegli un motivo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.report(widget.listingId, reason, details: _details.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'La segnalazione arriva alla moderazione. L\'autore non sa chi l\'ha inviata.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: (ReportReason? v) => setState(() => _reason = v),
            child: Column(
              children: [
                for (final ReportReason r in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: r,
                    title: Text(r.label),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          TextField(
            key: const ValueKey<String>('segnalazione_dettagli'),
            controller: _details,
            maxLength: 1000,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Dettagli (facoltativo)'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey<String>('invia_segnalazione'),
              onPressed: _busy ? null : _send,
              child: Text(_busy ? 'Invio…' : 'Invia segnalazione'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtri della Mappa (R3.11): distanza, orario, «Disponibile ora». La categoria è la
/// scheda di «Ultimi annunci» (Annunci / Promozioni).
class MapFiltersForm extends StatefulWidget {
  const MapFiltersForm({super.key, required this.initial});

  final MapFilters initial;

  @override
  State<MapFiltersForm> createState() => _MapFiltersFormState();
}

class _MapFiltersFormState extends State<MapFiltersForm> {
  late MapFilters _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtri', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Text('Distanza', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final int km in MapFilters.radiusOptions)
                ChoiceChip(
                  label: Text('Entro $km km'),
                  selected: _f.radiusKm == km,
                  onSelected: (_) => setState(() => _f = _f.copyWith(radiusKm: km)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Pubblicati', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final PublishedWithin p in PublishedWithin.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _f.published == p,
                  onSelected: (_) => setState(() => _f = _f.copyWith(published: p)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            key: const ValueKey<String>('filtro_disponibile_ora'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo «Disponibile ora»'),
            subtitle: const Text('Persone pronte a vedersi adesso'),
            value: _f.availableNowOnly,
            onChanged: (bool v) => setState(() => _f = _f.copyWith(availableNowOnly: v)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _f = MapFilters(radiusKm: _f.radiusKm)),
                child: const Text('Azzera'),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey<String>('applica_filtri'),
                onPressed: () => Navigator.of(context).pop(_f),
                child: const Text('Applica'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<MapFilters?> showMapFilters(BuildContext context, MapFilters current) =>
    showModalBottomSheet<MapFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => MapFiltersForm(initial: current),
    );
