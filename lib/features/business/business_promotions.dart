import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/widgets/piazly_ui.dart';
import '../chat/chat_rich_widgets.dart' show openInMaps;
import '../places/place_search.dart';
import 'business_models.dart';
import 'business_repository.dart';
import 'business_screens.dart';
import 'promo_alerts.dart';
import 'promotion_models.dart';

const List<String> _giorni = <String>['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];
const List<String> _mesi = <String>['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// «sab 22 nov 18:00».
String promoDate(DateTime t) => '${_giorni[t.weekday - 1]} ${t.day} ${_mesi[t.month - 1]} ${_hm(t)}';

/// «Fino a dom 23 nov 02:00» oppure «Da sab 22 nov 18:00 a dom 23 nov 02:00».
String promoWhen(Promotion p, DateTime now) =>
    p.startsAt.isAfter(now) ? 'Da ${promoDate(p.startsAt)} a ${promoDate(p.endsAt)}' : 'Fino a ${promoDate(p.endsAt)}';

/// Testo per «Condividi» (SMS, WhatsApp…): titolo, attività, quando, dove e mappa.
String promoShareText(Promotion p, DateTime now) {
  final String lat = p.lat.toStringAsFixed(5);
  final String lng = p.lng.toStringAsFixed(5);
  return <String>[
    '${p.kind == PromotionKind.evento ? '📅' : '🏷️'} ${p.title} · ${p.businessName}',
    promoWhen(p, now),
    if (p.hasCoupon) 'Coupon: ${p.couponText} (lo prendi gratis su Piazly)',
    'Dove: ${p.whereLabel}',
    'Mappa: https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng',
  ].join('\n');
}

double _km(double lat1, double lng1, double lat2, double lng2) {
  double r(double d) => d * math.pi / 180;
  final double a = math.pow(math.sin(r(lat2 - lat1) / 2), 2) +
      math.cos(r(lat1)) * math.cos(r(lat2)) * math.pow(math.sin(r(lng2 - lng1) / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(a));
}

String _distance(double km) => km < 1 ? '${(km * 1000 / 50).round() * 50} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Riquadro di una promozione (liste, scheda attività).
class PromotionTile extends StatelessWidget {
  const PromotionTile({super.key, required this.promotion, required this.now, this.onTap, this.distanceKm, this.trailing});

  final Promotion promotion;
  final DateTime now;
  final VoidCallback? onTap;
  final double? distanceKm;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Promotion p = promotion;
    return SoftCard(
      key: ValueKey<String>('promo_${p.id}'),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              p.kind == PromotionKind.evento ? Icons.event_rounded : Icons.local_offer_rounded,
              color: const Color(0xFFDB2777),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(p.businessName, style: theme.textTheme.bodyMedium),
                      if (p.verified) const VerifiedBadge(small: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      if (p.isOver(now)) (p.canceled ? 'Annullata' : 'Finita') else promoWhen(p, now),
                      if (distanceKm != null) _distance(distanceKm!),
                      if (!p.atSite) 'fuori sede',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (p.hasCoupon)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCE7F3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '🎟️ ${p.couponText}${p.myCoupon != null ? (p.myCouponUsed ? ' · usato' : ' · preso') : ''}',
                          style: const TextStyle(color: Color(0xFFBE185D), fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- dettaglio

class PromotionDetailScreen extends StatefulWidget {
  const PromotionDetailScreen({
    super.key,
    required this.repository,
    required this.promotion,
    this.now = DateTime.now,
    this.shareText,
  });

  final BusinessRepository repository;
  final Promotion promotion;
  final DateTime Function() now;

  /// Condivisione (nei test: finta).
  final Future<void> Function(String text)? shareText;

  @override
  State<PromotionDetailScreen> createState() => _PromotionDetailScreenState();
}

class _PromotionDetailScreenState extends State<PromotionDetailScreen> {
  late String? _code = widget.promotion.myCoupon;
  bool _busy = false;

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      final String code = await widget.repository.claimCoupon(widget.promotion.id);
      if (mounted) setState(() => _code = code);
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final String text = promoShareText(widget.promotion, widget.now());
    final Future<void> Function(String)? custom = widget.shareText;
    if (custom != null) {
      await custom(text);
    } else {
      await SharePlus.instance.share(ShareParams(text: text, subject: widget.promotion.title));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Promotion p = widget.promotion;
    final DateTime now = widget.now();
    final String? code = _code;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.kind.label),
        actions: [
          IconButton(
            key: const ValueKey<String>('promo_condividi'),
            tooltip: 'Condividi',
            onPressed: () => unawaited(_share()),
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: <Color>[Color(0xFFDB2777), Color(0xFF7C3AED)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(p.kind == PromotionKind.evento ? Icons.event_rounded : Icons.local_offer_rounded,
                    color: Colors.white, size: 32),
                const SizedBox(height: 8),
                Text(p.title,
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  p.isOver(now) ? (p.canceled ? 'Annullata' : 'Finita') : promoWhen(p, now),
                  key: const ValueKey<String>('promo_quando'),
                  style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(p.category.icon, color: PiazlyColors.violet),
                    Text(p.businessName, style: theme.textTheme.titleMedium),
                    if (p.verified) const VerifiedBadge(small: true),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_rounded, size: 20, color: Color(0xFFDB2777)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.atSite ? 'Nella sede: ${p.businessAddress}' : 'Fuori sede: ${p.whereLabel}',
                        key: const ValueKey<String>('promo_dove'),
                      ),
                    ),
                  ],
                ),
                if (p.description.isNotEmpty) ...[const SizedBox(height: 10), Text(p.description)],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey<String>('promo_indicazioni'),
                      onPressed: () => unawaited(openInMaps(p.lat, p.lng, p.atSite ? p.businessName : p.whereLabel)),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Indicazioni'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('promo_attivita'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => BusinessProfileScreen(
                            repository: widget.repository,
                            id: p.businessId,
                            now: widget.now,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.storefront_rounded),
                      label: const Text('Vai all\'attività'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (p.hasCoupon)
            SoftCard(
              key: const ValueKey<String>('promo_coupon'),
              child: Column(
                children: [
                  Text('🎟️ ${p.couponText}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (code != null) ...[
                    CouponQr(code: code),
                    const SizedBox(height: 8),
                    Text(
                      p.myCouponUsed
                          ? 'Coupon già usato.'
                          : 'Mostralo in cassa: lo convalidano con la fotocamera o scrivendo il codice.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else if (p.mine)
                    Text('I tuoi clienti lo prendono da qui. Coupon presi: ${p.claimed}.',
                        style: theme.textTheme.bodySmall)
                  else if (p.startsAt.isAfter(now))
                    Text('Il coupon si potrà prendere da ${promoDate(p.startsAt)}.', style: theme.textTheme.bodySmall)
                  else if (p.couponsLeft == 0)
                    Text('Coupon esauriti.', style: theme.textTheme.bodySmall)
                  else ...[
                    if (p.couponsLeft != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Ne restano ${p.couponsLeft}.', style: theme.textTheme.bodySmall),
                      ),
                    FilledButton.icon(
                      key: const ValueKey<String>('promo_prendi_coupon'),
                      onPressed: _busy ? null : () => unawaited(_claim()),
                      icon: const Icon(Icons.confirmation_number_rounded),
                      label: Text(_busy ? 'Un attimo…' : 'Prendi il coupon gratis'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// QR del coupon con il codice scritto sotto (per chi non può usare la fotocamera).
class CouponQr extends StatelessWidget {
  const CouponQr({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: QrImageView(
          key: const ValueKey<String>('coupon_qr'),
          data: PromotionRules.qrData(code),
          size: 190,
          backgroundColor: Colors.white,
        ),
      ),
      const SizedBox(height: 6),
      SelectableText(
        '${code.substring(0, 4)} ${code.substring(4)}',
        key: const ValueKey<String>('coupon_codice'),
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4),
      ),
    ],
  );
}

// ---------------------------------------------------------------- elenco intorno

/// Promozioni intorno (dalla Mappa), dalla più vicina.
class PromotionsListScreen extends StatelessWidget {
  const PromotionsListScreen({
    super.key,
    required this.repository,
    required this.promotions,
    this.originLat,
    this.originLng,
    this.now = DateTime.now,
  });

  final BusinessRepository repository;
  final List<Promotion> promotions;
  final double? originLat;
  final double? originLng;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final DateTime t = now();
    final List<(Promotion, double?)> rows = <(Promotion, double?)>[
      for (final Promotion p in promotions)
        (p, originLat == null ? null : _km(originLat!, originLng!, p.lat, p.lng)),
    ]..sort(((Promotion, double?) a, (Promotion, double?) b) => (a.$2 ?? 0).compareTo(b.$2 ?? 0));
    return Scaffold(
      appBar: AppBar(title: const Text('Promozioni ed eventi')),
      body: rows.isEmpty
          ? const Column(
              children: [
                PromoAlertsTile(),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nessuna promozione qui intorno, per ora.', textAlign: TextAlign.center),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const PromoAlertsTile(),
                for (final (Promotion, double?) r in rows)
                  PromotionTile(
                    promotion: r.$1,
                    now: t,
                    distanceKm: r.$2,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => PromotionDetailScreen(repository: repository, promotion: r.$1, now: now),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// I miei coupon (Profilo).
class MyCouponsScreen extends StatefulWidget {
  const MyCouponsScreen({super.key, required this.repository, this.now = DateTime.now});

  final BusinessRepository repository;
  final DateTime Function() now;

  @override
  State<MyCouponsScreen> createState() => _MyCouponsScreenState();
}

class _MyCouponsScreenState extends State<MyCouponsScreen> {
  List<Promotion>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<Promotion> items = await widget.repository.myCoupons();
      if (mounted) setState(() => _items = items);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Promotion>? items = _items;
    final DateTime now = widget.now();
    return Scaffold(
      appBar: AppBar(title: const Text('I miei coupon')),
      body: items == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : items.isEmpty
          ? const Column(
              children: [
                PromoAlertsTile(),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Non hai coupon. Li trovi nelle promozioni sulla Mappa (pulsante con l\'etichetta).',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const PromoAlertsTile(),
                for (final Promotion p in items)
                  PromotionTile(
                    promotion: p,
                    now: now,
                    onTap: () => Navigator.of(context)
                        .push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PromotionDetailScreen(repository: widget.repository, promotion: p, now: widget.now),
                          ),
                        )
                        .then((_) => _load()),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- titolare

/// Le promozioni della mia attività: nuove, conteggi e convalida dei coupon.
class MyPromotionsScreen extends StatefulWidget {
  const MyPromotionsScreen({
    super.key,
    required this.repository,
    required this.premiumActive,
    this.now = DateTime.now,
    this.lookup,
    this.scanner,
  });

  final BusinessRepository repository;
  final bool premiumActive;
  final DateTime Function() now;
  final PlaceLookup? lookup;

  /// Fotocamera per i QR (nei test: finta).
  final CouponScannerBuilder? scanner;

  @override
  State<MyPromotionsScreen> createState() => _MyPromotionsScreenState();
}

class _MyPromotionsScreenState extends State<MyPromotionsScreen> {
  List<Promotion>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<Promotion> items = await widget.repository.myPromotions();
      if (mounted) setState(() => _items = items);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  int get _today => (_items ?? const <Promotion>[]).where((Promotion p) => p.createdToday).length;

  Future<void> _new() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PromotionFormScreen(repository: widget.repository, now: widget.now, lookup: widget.lookup),
      ),
    );
    if (ok ?? false) await _load();
  }

  Future<void> _redeem() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CouponRedeemScreen(repository: widget.repository, scanner: widget.scanner),
      ),
    );
    await _load();
  }

  Future<void> _cancel(Promotion p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Annullare «${p.title}»?'),
        content: const Text('Sparisce dalla Mappa. I coupon già presi non si potranno più usare.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          FilledButton(
            key: const ValueKey<String>('promo_annulla_conferma'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Annulla promozione'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    try {
      await widget.repository.cancelPromotion(p.id);
      await _load();
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Promotion>? items = _items;
    final DateTime now = widget.now();
    final bool canCreate = widget.premiumActive && _today < PromotionRules.maxPerDay;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promozioni'),
        actions: [
          IconButton(
            key: const ValueKey<String>('promo_convalida'),
            tooltip: 'Convalida un coupon',
            onPressed: _redeem,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              key: const ValueKey<String>('promo_nuova'),
              onPressed: _new,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuova'),
            )
          : null,
      body: items == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                SoftCard(
                  key: const ValueKey<String>('promo_oggi'),
                  tint: PiazlyColors.violetSoft,
                  child: Text(
                    !widget.premiumActive
                        ? 'Le promozioni sono una funzione Premium: attiva la prova gratuita da «Piazly Premium».'
                        : 'Oggi: $_today di ${PromotionRules.maxPerDay} promozioni. Ognuna dura al massimo 7 giorni. '
                              'Con il pulsante in alto convalidi i coupon dei clienti.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nessuna promozione ancora.', textAlign: TextAlign.center),
                  ),
                for (final Promotion p in items)
                  Column(
                    children: [
                      PromotionTile(
                        promotion: p,
                        now: now,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PromotionDetailScreen(repository: widget.repository, promotion: p, now: widget.now),
                          ),
                        ),
                        trailing: p.isOver(now)
                            ? null
                            : IconButton(
                                key: ValueKey<String>('promo_annulla_${p.id}'),
                                tooltip: 'Annulla',
                                onPressed: () => _cancel(p),
                                icon: const Icon(Icons.cancel_outlined),
                              ),
                      ),
                      if (p.hasCoupon)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Coupon presi: ${p.claimed} · Clienti arrivati: ${p.redeemed}',
                              key: ValueKey<String>('promo_conti_${p.id}'),
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// Nuova promozione o evento.
class PromotionFormScreen extends StatefulWidget {
  const PromotionFormScreen({super.key, required this.repository, this.now = DateTime.now, this.lookup});

  final BusinessRepository repository;
  final DateTime Function() now;
  final PlaceLookup? lookup;

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _place = TextEditingController();
  final TextEditingController _coupon = TextEditingController();
  final TextEditingController _limit = TextEditingController();
  PromotionKind _kind = PromotionKind.offerta;
  bool _elsewhere = false;
  bool _withCoupon = false;
  PlaceSuggestion? _spot;
  late DateTime _start;
  late DateTime _end;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final DateTime n = widget.now();
    _start = DateTime(n.year, n.month, n.day, n.hour, n.minute - n.minute % 5);
    _end = _start.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_title, _desc, _place, _coupon, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final DateTime n = widget.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(n.year, n.month, n.day),
      lastDate: n.add(const Duration(days: 38)),
    );
    if (d == null || !mounted) return null;
    final TimeOfDay? t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final PlaceSuggestion? spot = _kind == PromotionKind.evento && _elsewhere ? _spot : null;
    if (_kind == PromotionKind.evento && _elsewhere && spot == null) {
      setState(() => _error = 'Scegli il luogo dell\'evento dai suggerimenti.');
      return;
    }
    final int? limit = _limit.text.trim().isEmpty ? null : int.tryParse(_limit.text.trim());
    if (_withCoupon && _limit.text.trim().isNotEmpty && (limit == null || limit < 1 || limit > 10000)) {
      setState(() => _error = 'Numero di coupon non valido (da 1 a 10.000).');
      return;
    }
    if (_withCoupon && _coupon.text.trim().length < 2) {
      setState(() => _error = 'Scrivi cosa dà il coupon (es. «Sconto 10%»).');
      return;
    }
    final PromotionDraft d = PromotionDraft(
      kind: _kind,
      title: _title.text,
      description: _desc.text,
      startsAt: _start,
      endsAt: _end,
      lat: spot?.lat,
      lng: spot?.lng,
      placeLabel: spot?.label ?? '',
      couponText: _withCoupon ? _coupon.text : '',
      couponLimit: _withCoupon ? limit : null,
    );
    final String? err = d.check(widget.now());
    setState(() => _error = err);
    if (err != null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.createPromotion(d);
      if (mounted) Navigator.of(context).pop(true);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nuova promozione')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<PromotionKind>(
              key: const ValueKey<String>('promo_tipo'),
              segments: const <ButtonSegment<PromotionKind>>[
                ButtonSegment<PromotionKind>(
                  value: PromotionKind.offerta,
                  label: Text('Offerta'),
                  icon: Icon(Icons.local_offer_rounded),
                ),
                ButtonSegment<PromotionKind>(
                  value: PromotionKind.evento,
                  label: Text('Evento'),
                  icon: Icon(Icons.event_rounded),
                ),
              ],
              selected: <PromotionKind>{_kind},
              onSelectionChanged: (Set<PromotionKind> s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('promo_titolo'),
              controller: _title,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Titolo',
                hintText: _kind == PromotionKind.evento ? 'Per esempio «Musica dal vivo»' : 'Per esempio «Colazione -20%»',
              ),
            ),
            TextField(
              key: const ValueKey<String>('promo_descrizione'),
              controller: _desc,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descrizione (facoltativa)'),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('promo_inizio'),
                    onPressed: () async {
                      final DateTime? d = await _pick(_start);
                      if (d != null && mounted) {
                        setState(() {
                          _start = d;
                          if (!_end.isAfter(_start) || _end.difference(_start) > PromotionRules.maxDuration) {
                            _end = _start.add(const Duration(days: 1));
                          }
                        });
                      }
                    },
                    child: Text('Inizio\n${promoDate(_start)}', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('promo_fine'),
                    onPressed: () async {
                      final DateTime? d = await _pick(_end);
                      if (d != null && mounted) setState(() => _end = d);
                    },
                    child: Text('Fine\n${promoDate(_end)}', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Al massimo 7 giorni.', style: theme.textTheme.bodySmall),
            if (_kind == PromotionKind.evento) ...[
              SwitchListTile(
                key: const ValueKey<String>('promo_fuori_sede'),
                contentPadding: EdgeInsets.zero,
                value: _elsewhere,
                onChanged: (bool v) => setState(() => _elsewhere = v),
                title: const Text('In un altro luogo'),
                subtitle: const Text('La sede della tua attività resta dov\'è.'),
              ),
              if (_elsewhere)
                PlaceField(
                  fieldKey: const ValueKey<String>('promo_luogo'),
                  controller: _place,
                  lookup: widget.lookup,
                  label: 'Luogo dell\'evento',
                  onSelected: (PlaceSuggestion? s) => _spot = s,
                ),
            ],
            SwitchListTile(
              key: const ValueKey<String>('promo_con_coupon'),
              contentPadding: EdgeInsets.zero,
              value: _withCoupon,
              onChanged: (bool v) => setState(() => _withCoupon = v),
              title: const Text('Con coupon (codice QR)'),
              subtitle: const Text('I clienti lo prendono gratis e lo mostrano in cassa.'),
            ),
            if (_withCoupon) ...[
              TextField(
                key: const ValueKey<String>('promo_coupon_testo'),
                controller: _coupon,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Cosa dà il coupon', hintText: 'Per esempio «Sconto 10%»'),
              ),
              TextField(
                key: const ValueKey<String>('promo_coupon_limite'),
                controller: _limit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quanti coupon al massimo (facoltativo)'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, key: const ValueKey<String>('promo_errore'),
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey<String>('promo_pubblica'),
              onPressed: _busy ? null : () => unawaited(_save()),
              child: Text(_busy ? 'Pubblicazione…' : 'Pubblica sulla Mappa'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fotocamera che legge i QR: chiama [onCode] con il testo letto.
typedef CouponScannerBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

Widget _realScanner(BuildContext context, ValueChanged<String> onCode) => MobileScanner(
  onDetect: (BarcodeCapture capture) {
    for (final Barcode b in capture.barcodes) {
      final String? v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        onCode(v);
        return;
      }
    }
  },
);

/// Convalida in cassa: inquadra il QR del cliente oppure scrivi il codice.
class CouponRedeemScreen extends StatefulWidget {
  const CouponRedeemScreen({super.key, required this.repository, this.scanner});

  final BusinessRepository repository;
  final CouponScannerBuilder? scanner;

  @override
  State<CouponRedeemScreen> createState() => _CouponRedeemScreenState();
}

class _CouponRedeemScreenState extends State<CouponRedeemScreen> {
  final TextEditingController _code = TextEditingController();
  bool _camera = false;
  bool _busy = false;
  CouponCheck? _ok;
  String? _error;
  String _last = '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// [fromCamera]: la fotocamera legge lo stesso QR molte volte al secondo: si controlla una volta.
  Future<void> _check(String raw, {bool fromCamera = false}) async {
    final String code = PromotionRules.normalizeCode(raw);
    if (_busy || (fromCamera && code == _last)) return;
    if (code.length != 8) {
      setState(() => _error = 'Il codice ha 8 caratteri.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _ok = null;
      _last = code;
      _camera = false;
    });
    try {
      final CouponCheck r = await widget.repository.redeemCoupon(code);
      if (mounted) setState(() => _ok = r);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CouponCheck? ok = _ok;
    return Scaffold(
      appBar: AppBar(title: const Text('Convalida coupon')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_camera)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 300,
                child: (widget.scanner ?? _realScanner)(context, (String v) => unawaited(_check(v, fromCamera: true))),
              ),
            )
          else
            FilledButton.icon(
              key: const ValueKey<String>('convalida_fotocamera'),
              onPressed: () => setState(() => _camera = true),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Inquadra il QR del cliente'),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('convalida_codice'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            decoration: const InputDecoration(labelText: 'Oppure scrivi il codice', hintText: 'ABCD 2345'),
          ),
          OutlinedButton(
            key: const ValueKey<String>('convalida_controlla'),
            onPressed: _busy ? null : () => unawaited(_check(_code.text)),
            child: const Text('Convalida'),
          ),
          const SizedBox(height: 16),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (ok != null)
            SoftCard(
              key: const ValueKey<String>('convalida_ok'),
              margin: EdgeInsets.zero,
              tint: PiazlyColors.greenSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded, color: PiazlyColors.green, size: 36),
                  const SizedBox(height: 6),
                  Text('Coupon valido: ${ok.couponText}', style: theme.textTheme.titleMedium),
                  Text(ok.title),
                  const SizedBox(height: 6),
                  Text('Clienti arrivati con questa promozione: ${ok.redeemed}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (_error != null)
            SoftCard(
              key: const ValueKey<String>('convalida_errore'),
              margin: EdgeInsets.zero,
              tint: const Color(0xFFFDECEC),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFE53935)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
