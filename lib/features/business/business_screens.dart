import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/piazly_ui.dart';
import '../chat/chat_rich_widgets.dart' show openInMaps;
import '../chat/chat_thread_screen.dart' show openChatWith;
import '../map/listing_models.dart' show GeoPoint;
import '../map/map_surface.dart';
import '../map/point_picker_screen.dart';
import '../market/comuni_italia.dart';
import '../places/place_search.dart';
import '../profile/profile_form_screen.dart' show PickImage, pickFromGallery;
import '../profile/profile_models.dart' show ProfileRules;
import 'business_models.dart';
import 'business_repository.dart';

/// Documento facoltativo: (byte, è un PDF?). Nei test: finto.
typedef PickDocument = Future<(Uint8List, bool)?> Function();

Future<(Uint8List, bool)?> pickBusinessDocument() async {
  final List<PlatformFile> picked = await FilePicker.pickFiles();
  final PlatformFile? f = picked.firstOrNull;
  if (f == null) return null;
  final String ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
  if (!const <String>{'pdf', 'jpg', 'jpeg'}.contains(ext)) {
    throw const BusinessFailure('Scegli un PDF o una foto JPG.');
  }
  return (await f.xFile.readAsBytes(), ext == 'pdf');
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Badge «Verificato» (solo aziende approvate dall'amministratore).
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey<String>('badge_verificato'),
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 4),
    decoration: BoxDecoration(color: const Color(0xFF1D9BF0), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: small ? 13 : 16, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          'Verificato',
          style: TextStyle(color: Colors.white, fontSize: small ? 11 : 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- La mia attività

/// «La mia attività» nel Profilo: registrazione, stato della verifica, documento e pagina.
class MyBusinessScreen extends StatefulWidget {
  const MyBusinessScreen({
    super.key,
    required this.repository,
    this.pickImage = pickFromGallery,
    this.pickDocument = pickBusinessDocument,
    this.surface,
    this.lookup,
    this.now = DateTime.now,
  });

  final BusinessRepository repository;
  final PickImage pickImage;
  final PickDocument pickDocument;

  /// Mappa per regolare il segnaposto (null nei test e nelle anteprime).
  final MapSurfaceBuilder? surface;
  final PlaceLookup? lookup;
  final DateTime Function() now;

  @override
  State<MyBusinessScreen> createState() => _MyBusinessScreenState();
}

class _MyBusinessScreenState extends State<MyBusinessScreen> {
  MyBusiness? _me;
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MyBusiness? me = await widget.repository.mine();
      if (mounted) setState(() => _me = me);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BusinessRegisterScreen(repository: widget.repository, initial: _me),
      ),
    );
    if (ok ?? false) await _load();
  }

  Future<void> _editPage() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BusinessPageEditScreen(
          repository: widget.repository,
          initial: _me?.page,
          pickImage: widget.pickImage,
          surface: widget.surface,
          lookup: widget.lookup,
        ),
      ),
    );
    if (ok ?? false) await _load();
  }

  Future<void> _document() async {
    final (Uint8List, bool)? doc;
    try {
      doc = await widget.pickDocument();
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
      return;
    }
    if (doc == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await widget.repository.setDocument(doc.$1, pdf: doc.$2);
      if (mounted) _toast(context, 'Documento caricato: lo vedono solo gli amministratori.');
      await _load();
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MyBusiness? me = _me;
    return Scaffold(
      appBar: AppBar(title: const Text('La mia attività')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _load, child: const Text('Riprova')),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: me == null
                  ? <Widget>[
                      SoftCard(
                        key: const ValueKey<String>('azienda_intro'),
                        tint: PiazlyColors.orangeSoft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconTile(Icons.storefront_rounded, color: Color(0xFFF97316)),
                            const SizedBox(height: 10),
                            Text('Porta la tua attività su Piazly', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 6),
                            const Text(
                              'Crea il profilo della tua attività con foto, indirizzo, orari e prenotazioni. '
                              'La sede compare sulla Mappa con un segnaposto fisso. Dopo la verifica '
                              'arriveranno il badge «Verificato», le promozioni e i coupon.',
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              key: const ValueKey<String>('azienda_registra'),
                              onPressed: _register,
                              icon: const Icon(Icons.add_business_rounded),
                              label: const Text('Registra la tua attività'),
                            ),
                          ],
                        ),
                      ),
                    ]
                  : <Widget>[
                      _StatusCard(me: me),
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dati dell\'azienda', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text('Visibili solo a te e agli amministratori.', style: theme.textTheme.bodySmall),
                            const SizedBox(height: 10),
                            _Row(label: 'Ragione sociale', value: me.businessName),
                            _Row(label: 'Partita IVA', value: me.vatNumber),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey<String>('azienda_modifica_dati'),
                                  onPressed: _register,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Correggi'),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey<String>('azienda_documento'),
                                  onPressed: _uploading ? null : _document,
                                  icon: Icon(me.hasDocument ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                                      size: 18),
                                  label: Text(_uploading
                                      ? 'Caricamento…'
                                      : me.hasDocument
                                      ? 'Documento caricato'
                                      : 'Documento (facoltativo)'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (me.page == null)
                        SoftCard(
                          key: const ValueKey<String>('azienda_senza_pagina'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Profilo attività', style: theme.textTheme.titleMedium),
                              const SizedBox(height: 6),
                              const Text('Aggiungi insegna, indirizzo della sede, orari e foto: è quello che '
                                  'vedono le persone sulla Mappa.'),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                key: const ValueKey<String>('azienda_crea_pagina'),
                                onPressed: _editPage,
                                icon: const Icon(Icons.storefront_rounded),
                                label: const Text('Crea il profilo attività'),
                              ),
                            ],
                          ),
                        )
                      else
                        SoftCard(
                          key: const ValueKey<String>('azienda_pagina'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconTile(me.page!.category.icon, color: PiazlyColors.violet),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(me.page!.displayName, style: theme.textTheme.titleMedium),
                                        Text(me.page!.address.label, style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                me.page!.published
                                    ? 'Visibile sulla Mappa · ${me.page!.hours.statusLabel(widget.now())}'
                                    : 'Nascosta: non compare sulla Mappa',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    key: const ValueKey<String>('azienda_modifica_pagina'),
                                    onPressed: _editPage,
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    label: const Text('Modifica'),
                                  ),
                                  OutlinedButton.icon(
                                    key: const ValueKey<String>('azienda_vedi_pagina'),
                                    onPressed: () => Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => BusinessProfileScreen(
                                          repository: widget.repository,
                                          id: me.page!.id,
                                          now: widget.now,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.visibility_outlined, size: 18),
                                    label: const Text('Come la vedono gli altri'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      SoftCard(
                        tint: PiazlyColors.violetSoft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.workspace_premium_rounded, color: PiazlyColors.violet),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'In arrivo: abbonamento Premium (9,99 € al mese, 7 giorni gratis), promozioni '
                                'sulla Mappa e coupon con QR. Il badge «Verificato» richiederà la verifica e '
                                'l\'abbonamento attivo.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.me});

  final MyBusiness me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (Color, IconData, String) look = switch (me.status) {
      VerificationStatus.pending => (
        const Color(0xFFF59E0B),
        Icons.hourglass_top_rounded,
        'Un amministratore controlla ragione sociale e partita IVA. Intanto puoi preparare il profilo '
            'attività: è già visibile sulla Mappa.',
      ),
      VerificationStatus.verified => (
        PiazlyColors.green,
        Icons.verified_rounded,
        'Dati controllati da Piazly. Con l\'abbonamento attivo comparirà il badge «Verificato».',
      ),
      VerificationStatus.rejected => (
        const Color(0xFFE53935),
        Icons.error_outline_rounded,
        'La verifica non è andata a buon fine. Correggi i dati: la richiesta ripartirà.',
      ),
    };
    return SoftCard(
      key: ValueKey<String>('azienda_stato_${me.status.name}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(look.$2, color: look.$1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verifica: ${me.status.label}', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(look.$3, style: theme.textTheme.bodySmall),
                if (me.reviewNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Nota: ${me.reviewNote}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

// ---------------------------------------------------------------- registrazione

/// Ragione sociale e partita IVA (private). Un account Privato diventa Azienda.
class BusinessRegisterScreen extends StatefulWidget {
  const BusinessRegisterScreen({super.key, required this.repository, this.initial});

  final BusinessRepository repository;
  final MyBusiness? initial;

  @override
  State<BusinessRegisterScreen> createState() => _BusinessRegisterScreenState();
}

class _BusinessRegisterScreenState extends State<BusinessRegisterScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.businessName ?? '');
  late final TextEditingController _vat = TextEditingController(text: widget.initial?.vatNumber ?? '');
  bool _declared = false;
  bool _busy = false;
  String? _nameError;
  String? _vatError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _vat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _nameError = ProfileRules.businessNameError(_name.text);
      _vatError = ProfileRules.isValidPartitaIva(_vat.text) ? null : 'Partita IVA non valida (11 cifre).';
      _error = !_declared ? 'Conferma la dichiarazione qui sopra.' : null;
    });
    if (_nameError != null || _vatError != null || _error != null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.register(businessName: _name.text, vatNumber: _vat.text);
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
      appBar: AppBar(title: Text(widget.initial == null ? 'Registra l\'attività' : 'Dati dell\'azienda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            key: const ValueKey<String>('azienda_ragione_sociale'),
            controller: _name,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Ragione sociale', errorText: _nameError),
          ),
          TextField(
            key: const ValueKey<String>('azienda_partita_iva'),
            controller: _vat,
            maxLength: 11,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Partita IVA', errorText: _vatError),
          ),
          Text(
            'Ragione sociale e partita IVA restano private: le vedono solo gli amministratori di Piazly per '
            'la verifica. In pubblico compaiono l\'insegna e la sede. Se cambi questi dati dopo la verifica, '
            'la verifica ricomincia.',
            style: theme.textTheme.bodySmall,
          ),
          if (widget.initial == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Il tuo account diventerà «Azienda». Chat, Stati e Mappa restano uguali.',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey<String>('azienda_dichiarazione'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _declared,
            onChanged: (bool? v) => setState(() => _declared = v ?? false),
            title: const Text('Sono maggiorenne e sono il titolare dell\'attività o ho il permesso di registrarla.'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, key: const ValueKey<String>('azienda_errore'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          FilledButton(
            key: const ValueKey<String>('azienda_invia'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Invio…' : 'Invia per la verifica'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- profilo attività (modifica)

class BusinessPageEditScreen extends StatefulWidget {
  const BusinessPageEditScreen({
    super.key,
    required this.repository,
    this.initial,
    this.pickImage = pickFromGallery,
    this.surface,
    this.lookup,
    this.comuni,
  });

  final BusinessRepository repository;
  final BusinessPage? initial;
  final PickImage pickImage;
  final MapSurfaceBuilder? surface;
  final PlaceLookup? lookup;
  final ComuniItalia? comuni;

  @override
  State<BusinessPageEditScreen> createState() => _BusinessPageEditScreenState();
}

/// Da dove viene il segnaposto della sede.
enum _PinSource { none, address, comune, map }

class _BusinessPageEditScreenState extends State<BusinessPageEditScreen> {
  late final BusinessPage? _p = widget.initial;
  late final TextEditingController _name = TextEditingController(text: _p?.displayName ?? '');
  late final TextEditingController _desc = TextEditingController(text: _p?.description ?? '');
  final TextEditingController _search = TextEditingController();
  late final TextEditingController _street = TextEditingController(text: _p?.address.street ?? '');
  late final TextEditingController _civic = TextEditingController(text: _p?.address.civic ?? '');
  late final TextEditingController _city = TextEditingController(
    text: _p == null ? '' : '${_p.address.city} (${_p.address.province})',
  );
  late final TextEditingController _cap = TextEditingController(text: _p?.address.cap ?? '');
  late final TextEditingController _phone = TextEditingController(text: _p?.phone ?? '');
  late final TextEditingController _booking = TextEditingController(text: _p?.bookingUrl ?? '');
  late BusinessCategory _category = _p?.category ?? BusinessCategory.negozio;
  late String _cityName = _p?.address.city ?? '';
  late String _province = _p?.address.province ?? '';
  late double? _lat = _p?.lat;
  late double? _lng = _p?.lng;
  late _PinSource _pin = _p == null ? _PinSource.none : _PinSource.map;
  late final Map<int, List<HourSlot>> _hours = <int, List<HourSlot>>{
    for (int d = 1; d <= 7; d++) d: List<HourSlot>.of(_p?.hours.of(d) ?? const <HourSlot>[]),
  };
  late final List<String> _kept = List<String>.of(_p?.photos ?? const <String>[]);
  final List<Uint8List> _added = <Uint8List>[];
  late bool _published = _p?.published ?? true;
  bool _busy = false;
  String? _error;

  ComuniItalia? get _comuni => widget.comuni ?? ComuniItalia.loaded;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _desc, _search, _street, _civic, _city, _cap, _phone, _booking,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Indirizzo scelto dai suggerimenti: compila via, civico, città, CAP e provincia.
  void _fromAddress(PlaceSuggestion? s) {
    if (s == null) return;
    setState(() {
      if (s.street.isNotEmpty) _street.text = s.street;
      if (s.houseNumber.isNotEmpty) _civic.text = s.houseNumber;
      if (s.postcode.isNotEmpty && RegExp(r'^[0-9]{5}$').hasMatch(s.postcode)) _cap.text = s.postcode;
      final Comune? c = s.comune ?? _findComune(s.city.isNotEmpty ? s.city : s.title);
      if (c != null) _setComune(c, movePin: false);
      _lat = s.lat;
      _lng = s.lng;
      _pin = s.street.isNotEmpty ? _PinSource.address : _PinSource.comune;
    });
  }

  Comune? _findComune(String name) {
    final String n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final Comune c in _comuni?.search(name) ?? const <Comune>[]) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  void _setComune(Comune c, {required bool movePin}) {
    _cityName = c.name;
    _province = c.provinceCode;
    _city.text = c.label;
    if (movePin || _lat == null) {
      _lat = c.point.latitude;
      _lng = c.point.longitude;
      _pin = _PinSource.comune;
    }
  }

  Future<void> _adjustOnMap() async {
    final MapSurfaceBuilder? surface = widget.surface;
    if (surface == null) return;
    final GeoPoint? p = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute<GeoPoint>(
        builder: (_) => PointPickerScreen(
          surface: surface,
          start: _lat == null ? null : GeoPoint(_lat!, _lng!),
        ),
      ),
    );
    if (p != null && mounted) {
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _pin = _PinSource.map;
      });
    }
  }

  Future<void> _addPhoto() async {
    final Uint8List? bytes = await widget.pickImage();
    if (bytes != null && mounted) setState(() => _added.add(bytes));
  }

  Future<void> _editDay(int day) async {
    final List<HourSlot>? r = await showModalBottomSheet<List<HourSlot>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DayEditor(day: day, slots: _hours[day] ?? const <HourSlot>[]),
    );
    if (r != null && mounted) setState(() => _hours[day] = r);
  }

  void _copyMondayToWeekdays() {
    setState(() {
      for (int d = 2; d <= 5; d++) {
        _hours[d] = List<HourSlot>.of(_hours[1] ?? const <HourSlot>[]);
      }
    });
  }

  Future<void> _save() async {
    String? err;
    if (_name.text.trim().length < 2 || _name.text.trim().length > 80) {
      err = 'Scrivi l\'insegna (da 2 a 80 caratteri).';
    } else if (BusinessAddress.streetError(_street.text) case final String e) {
      err = e;
    } else if (BusinessAddress.civicError(_civic.text) case final String e) {
      err = e;
    } else if (_cityName.isEmpty || _province.isEmpty) {
      err = 'Scegli il comune della sede dai suggerimenti.';
    } else if (BusinessAddress.capError(_cap.text) case final String e) {
      err = e;
    } else if (_lat == null || _lng == null) {
      err = 'Manca il punto della sede sulla mappa.';
    } else if (_phone.text.trim().isNotEmpty && !RegExp(r'^\+?[0-9 ]{6,20}$').hasMatch(_phone.text.trim())) {
      err = 'Telefono dell\'attività non valido.';
    } else if (_booking.text.trim().isNotEmpty && !RegExp(r'^https://\S{3,300}$').hasMatch(_booking.text.trim())) {
      err = 'Il link per prenotare deve iniziare con https://';
    }
    final BusinessPageDraft draft = BusinessPageDraft(
      displayName: _name.text,
      category: _category,
      address: BusinessAddress(
        street: _street.text,
        civic: _civic.text,
        city: _cityName,
        cap: _cap.text,
        province: _province,
      ),
      lat: _lat ?? 0,
      lng: _lng ?? 0,
      description: _desc.text,
      phone: _phone.text,
      bookingUrl: _booking.text,
      hours: BusinessHours(_hours),
      keptPhotos: _kept,
      published: _published,
    );
    if (err == null && !draft.inItaly) err = 'La sede deve essere in Italia.';
    setState(() => _error = err);
    if (err != null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.savePage(draft, newPhotos: _added);
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
    final int photoCount = _kept.length + _added.length;
    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(t, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(_p == null ? 'Profilo attività' : 'Modifica attività')),
      // Tutto costruito subito (modulo lungo ma leggero): niente campi «spariti» fuori schermo.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          title('L\'attività'),
          TextField(
            key: const ValueKey<String>('pagina_insegna'),
            controller: _name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Insegna (nome che vedono tutti)'),
          ),
          DropdownButtonFormField<BusinessCategory>(
            key: const ValueKey<String>('pagina_categoria'),
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: <DropdownMenuItem<BusinessCategory>>[
              for (final BusinessCategory c in BusinessCategory.values)
                DropdownMenuItem<BusinessCategory>(
                  value: c,
                  child: Row(
                    children: [
                      Icon(c.icon, size: 18),
                      const SizedBox(width: 8),
                      Flexible(child: Text(c.label, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
            onChanged: (BusinessCategory? c) => setState(() => _category = c ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('pagina_descrizione'),
            controller: _desc,
            maxLength: 600,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Descrizione (facoltativa)'),
          ),
          title('Sede (fissa sulla Mappa)'),
          PlaceField(
            fieldKey: const ValueKey<String>('pagina_cerca_indirizzo'),
            controller: _search,
            lookup: widget.lookup,
            comuni: widget.comuni,
            label: 'Cerca l\'indirizzo',
            hint: 'Per esempio «Via Roma 12 Porano»',
            onSelected: _fromAddress,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey<String>('pagina_via'),
                  controller: _street,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Via o piazza'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('pagina_civico'),
                  controller: _civic,
                  decoration: const InputDecoration(labelText: 'Civico'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PlaceField(
            fieldKey: const ValueKey<String>('pagina_comune'),
            controller: _city,
            onlyComuni: true,
            comuni: widget.comuni,
            label: 'Comune',
            hint: 'Per esempio «Porano»',
            onSelected: (PlaceSuggestion? s) {
              final Comune? c = s?.comune;
              if (c != null) setState(() => _setComune(c, movePin: _pin == _PinSource.none || _pin == _PinSource.comune));
            },
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey<String>('pagina_cap'),
            controller: _cap,
            maxLength: 5,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'CAP', counterText: ''),
          ),
          const SizedBox(height: 8),
          SoftCard(
            key: const ValueKey<String>('pagina_segnaposto'),
            margin: EdgeInsets.zero,
            child: Row(
              children: [
                Icon(
                  _lat == null ? Icons.location_off_outlined : Icons.location_on_rounded,
                  color: _lat == null ? theme.colorScheme.error : PiazlyColors.violet,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(switch (_pin) {
                    _PinSource.none => 'Cerca l\'indirizzo o scegli il comune per mettere la sede sulla Mappa.',
                    _PinSource.address => 'Segnaposto sull\'indirizzo. Resta fisso: non segue il tuo GPS.',
                    _PinSource.comune => 'Segnaposto al centro del comune: regolalo sulla mappa.',
                    _PinSource.map => 'Segnaposto scelto sulla mappa. Resta fisso: non segue il tuo GPS.',
                  }, style: theme.textTheme.bodySmall),
                ),
                if (widget.surface != null)
                  TextButton(
                    key: const ValueKey<String>('pagina_regola_mappa'),
                    onPressed: _lat == null ? null : _adjustOnMap,
                    child: const Text('Regola'),
                  ),
              ],
            ),
          ),
          title('Orari'),
          for (int d = 1; d <= 7; d++)
            ListTile(
              key: ValueKey<String>('orari_giorno_$d'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(BusinessHours.dayNames[d - 1]),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (_hours[d] ?? const <HourSlot>[]).isEmpty
                        ? 'Chiuso'
                        : _hours[d]!.map((HourSlot s) => s.label).join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              onTap: () => _editDay(d),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('orari_copia'),
              onPressed: _copyMondayToWeekdays,
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text('Copia il lunedì fino al venerdì'),
            ),
          ),
          title('Contatti e prenotazioni'),
          TextField(
            key: const ValueKey<String>('pagina_telefono'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefono dell\'attività (facoltativo)'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey<String>('pagina_prenota'),
            controller: _booking,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link per prenotare (facoltativo)',
              hintText: 'https://…',
            ),
          ),
          title('Foto (fino a 6)'),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (int i = 0; i < _kept.length; i++)
                  _PhotoThumb(
                    key: ValueKey<String>('foto_salvata_$i'),
                    child: _StoredPhoto(repository: widget.repository, path: _kept[i]),
                    onRemove: () => setState(() => _kept.removeAt(i)),
                  ),
                for (int i = 0; i < _added.length; i++)
                  _PhotoThumb(
                    key: ValueKey<String>('foto_nuova_$i'),
                    child: Image.memory(_added[i], fit: BoxFit.cover),
                    onRemove: () => setState(() => _added.removeAt(i)),
                  ),
                if (photoCount < 6)
                  InkWell(
                    key: const ValueKey<String>('pagina_aggiungi_foto'),
                    onTap: _addPhoto,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 96,
                      decoration: BoxDecoration(
                        color: PiazlyColors.violetSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined, color: PiazlyColors.violet),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey<String>('pagina_pubblicata'),
            contentPadding: EdgeInsets.zero,
            value: _published,
            onChanged: (bool v) => setState(() => _published = v),
            title: const Text('Visibile sulla Mappa'),
            subtitle: const Text('Se la spegni, la pagina resta salvata ma nessuno la vede.'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, key: const ValueKey<String>('pagina_errore'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          FilledButton(
            key: const ValueKey<String>('pagina_salva'),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Salvataggio…' : 'Salva'),
          ),
        ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({super.key, required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 96, height: 96, child: child)),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

class _StoredPhoto extends StatelessWidget {
  const _StoredPhoto({required this.repository, required this.path});

  final BusinessRepository repository;
  final String path;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: repository.photo(path),
    builder: (BuildContext context, AsyncSnapshot<Uint8List?> s) {
      final Uint8List? b = s.data;
      if (b == null) return Container(color: PiazlyColors.violetSoft);
      return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true);
    },
  );
}

/// Orari di un giorno: chiuso, oppure una o due fasce.
class _DayEditor extends StatefulWidget {
  const _DayEditor({required this.day, required this.slots});

  final int day;
  final List<HourSlot> slots;

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late final List<HourSlot> _slots = List<HourSlot>.of(widget.slots);
  String? _error;

  Future<int?> _pick(int minutes) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (minutes % 1440) ~/ 60, minute: minutes % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _change(int i, {required bool open}) async {
    final HourSlot s = _slots[i];
    final int? m = await _pick(open ? s.open : s.close);
    if (m == null || !mounted) return;
    setState(() {
      if (open) {
        _slots[i] = HourSlot(m, s.close);
      } else {
        // Chiusura prima dell'apertura: dopo mezzanotte (fino alle 6).
        _slots[i] = HourSlot(s.open, m <= s.open ? m + 1440 : m);
      }
    });
  }

  void _done() {
    for (int i = 0; i < _slots.length; i++) {
      if (!_slots[i].valid || (i > 0 && _slots[i].open < _slots[i - 1].close)) {
        setState(() => _error = 'Controlla le fasce: devono essere in ordine e chiudere entro le 6 del mattino.');
        return;
      }
    }
    Navigator.of(context).pop(_slots);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(BusinessHours.dayNames[widget.day - 1], style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_slots.isEmpty) const Text('Chiuso tutto il giorno.'),
            for (int i = 0; i < _slots.length; i++)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey<String>('fascia_${i}_apre'),
                      onPressed: () => _change(i, open: true),
                      child: Text('Apre ${HourSlot.hm(_slots[i].open)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey<String>('fascia_${i}_chiude'),
                      onPressed: () => _change(i, open: false),
                      child: Text('Chiude ${HourSlot.hm(_slots[i].close)}'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Togli',
                    onPressed: () => setState(() => _slots.removeAt(i)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            if (_slots.length < 2)
              TextButton.icon(
                key: const ValueKey<String>('fascia_aggiungi'),
                onPressed: () => setState(() {
                  _slots.add(_slots.isEmpty ? const HourSlot(9 * 60, 13 * 60) : const HourSlot(16 * 60, 19 * 60 + 30));
                }),
                icon: const Icon(Icons.add_rounded),
                label: Text(_slots.isEmpty ? 'Aperto: aggiungi gli orari' : 'Aggiungi il pomeriggio'),
              ),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            FilledButton(key: const ValueKey<String>('fascia_fatto'), onPressed: _done, child: const Text('Fatto')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- scheda pubblica

/// Scheda dell'attività come la vedono tutti: foto, sede, orari, contatti.
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key, required this.repository, required this.id, this.now = DateTime.now});

  final BusinessRepository repository;
  final String id;
  final DateTime Function() now;

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  BusinessPage? _page;
  bool _loading = true;
  String? _error;
  int _photo = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final BusinessPage? p = await widget.repository.page(widget.id);
      if (mounted) setState(() => _page = p);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BusinessPage? p = _page;
    if (_loading || p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Text(_error ?? 'Questa attività non è più disponibile.', key: const ValueKey<String>('attivita_assente')),
        ),
      );
    }
    final DateTime now = widget.now();
    final bool open = p.hours.isOpenAt(now);
    return Scaffold(
      appBar: AppBar(title: Text(p.displayName, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (p.photos.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                children: [
                  PageView(
                    key: const ValueKey<String>('attivita_foto'),
                    onPageChanged: (int i) => setState(() => _photo = i),
                    children: [
                      for (final String path in p.photos) _StoredPhoto(repository: widget.repository, path: path),
                    ],
                  ),
                  if (p.photos.length > 1)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: Text('${_photo + 1}/${p.photos.length}', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(p.displayName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    if (p.verified) const VerifiedBadge(),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(p.category.icon, size: 18, color: PiazlyColors.violet),
                    const SizedBox(width: 6),
                    Text(p.category.label),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p.hours.statusLabel(now),
                  key: const ValueKey<String>('attivita_aperto'),
                  style: TextStyle(
                    color: open ? PiazlyColors.green : const Color(0xFFE53935),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey<String>('attivita_indicazioni'),
                  onPressed: () => unawaited(openInMaps(p.lat, p.lng, p.displayName)),
                  icon: const Icon(Icons.directions_rounded),
                  label: const Text('Indicazioni'),
                ),
                if (p.bookingUrl.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('attivita_prenota'),
                    onPressed: () => unawaited(launchUrl(Uri.parse(p.bookingUrl), mode: LaunchMode.externalApplication)),
                    icon: const Icon(Icons.event_available_rounded),
                    label: const Text('Prenota'),
                  ),
                if (p.phone.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('attivita_chiama'),
                    onPressed: () => unawaited(launchUrl(Uri(scheme: 'tel', path: p.phone.replaceAll(' ', '')))),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Chiama'),
                  ),
                if (!p.mine)
                  OutlinedButton.icon(
                    key: const ValueKey<String>('attivita_scrivi'),
                    onPressed: () => unawaited(openChatWith(context, userId: p.id, name: p.displayName)),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Scrivi'),
                  ),
              ],
            ),
          ),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place_rounded, color: PiazlyColors.violet),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.address.label, key: const ValueKey<String>('attivita_indirizzo'))),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Sede ufficiale', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (p.description.isNotEmpty) SoftCard(child: Text(p.description)),
          SoftCard(
            key: const ValueKey<String>('attivita_orari'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Orari', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                if (p.hours.isEmpty)
                  const Text('Orari non indicati.')
                else
                  for (int d = 1; d <= 7; d++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              BusinessHours.dayNames[d - 1],
                              style: TextStyle(fontWeight: d == now.weekday ? FontWeight.w800 : FontWeight.w400),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              p.hours.of(d).isEmpty ? 'Chiuso' : p.hours.of(d).map((HourSlot s) => s.label).join(' · '),
                              style: TextStyle(fontWeight: d == now.weekday ? FontWeight.w800 : FontWeight.w400),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          SoftCard(
            tint: PiazlyColors.violetSoft,
            child: Row(
              children: [
                const Icon(Icons.reviews_outlined, color: PiazlyColors.violet),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recensioni verificate: in arrivo. Potrà scriverle solo chi è stato davvero cliente '
                    '(per esempio usando un coupon).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- verifica (amministratori)

class BusinessReviewScreen extends StatefulWidget {
  const BusinessReviewScreen({super.key, required this.repository});

  final BusinessRepository repository;

  @override
  State<BusinessReviewScreen> createState() => _BusinessReviewScreenState();
}

class _BusinessReviewScreenState extends State<BusinessReviewScreen> {
  List<BusinessReviewItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<BusinessReviewItem> items = await widget.repository.reviewQueue();
      if (mounted) setState(() => _items = items);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _decide(BusinessReviewItem it, bool approve) async {
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(approve ? 'Approvare ${it.businessName}?' : 'Rifiutare ${it.businessName}?'),
        content: TextField(
          key: const ValueKey<String>('verifica_nota'),
          controller: note,
          maxLength: 300,
          decoration: InputDecoration(labelText: approve ? 'Nota (facoltativa)' : 'Motivo (lo legge l\'azienda)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('verifica_conferma'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(approve ? 'Approva' : 'Rifiuta'),
          ),
        ],
      ),
    );
    final String text = note.text;
    note.dispose();
    if (!(ok ?? false)) return;
    try {
      await widget.repository.review(it.id, approve: approve, note: text);
      await _load();
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
    }
  }

  Future<void> _document(BusinessReviewItem it) async {
    final String? path = it.documentPath;
    if (path == null) return;
    final Uint8List? bytes = await widget.repository.document(path);
    if (!mounted) return;
    if (bytes == null) {
      _toast(context, 'Documento non disponibile.');
      return;
    }
    if (path.endsWith('.pdf')) {
      _toast(context, 'Il documento è un PDF: aprilo dal pannello di Supabase (Storage › aziende_documenti).');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<BusinessReviewItem>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Aziende da verificare')),
      body: items == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('Nessuna azienda registrata.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final BusinessReviewItem it in items)
                    SoftCard(
                      key: ValueKey<String>('verifica_${it.username}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(it.businessName, style: theme.textTheme.titleMedium)),
                              Text(it.status.label, style: theme.textTheme.labelMedium),
                            ],
                          ),
                          Text('@${it.username} · P.IVA ${it.vatNumber}'),
                          if (it.displayName.isNotEmpty) Text('${it.displayName} · ${it.city} (${it.province})'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (it.status != VerificationStatus.verified)
                                FilledButton(
                                  key: ValueKey<String>('verifica_approva_${it.username}'),
                                  onPressed: () => _decide(it, true),
                                  child: const Text('Approva'),
                                ),
                              if (it.status != VerificationStatus.rejected)
                                OutlinedButton(
                                  key: ValueKey<String>('verifica_rifiuta_${it.username}'),
                                  onPressed: () => _decide(it, false),
                                  child: const Text('Rifiuta'),
                                ),
                              if (it.documentPath != null)
                                TextButton.icon(
                                  onPressed: () => _document(it),
                                  icon: const Icon(Icons.description_outlined, size: 18),
                                  label: const Text('Documento'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
