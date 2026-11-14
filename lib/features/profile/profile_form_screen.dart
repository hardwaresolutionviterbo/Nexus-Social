
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../onboarding/registration_rules.dart';
import 'avatar_view.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Sceglie un'immagine dalla galleria. Nei test si sostituisce.
typedef PickImage = Future<Uint8List?> Function();

Future<Uint8List?> pickFromGallery() async {
  final XFile? file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
  );
  return file?.readAsBytes();
}

/// Creazione (dopo il primo accesso) e modifica del profilo (Fase 2, Blocco 2).
///
/// - Creazione: tipo di account e data di nascita arrivano dalla registrazione; se l'app è
///   stata chiusa nel frattempo, si chiedono di nuovo qui (restano solo in memoria fino
///   al salvataggio). Il server ripete tutti i controlli (età, Azienda 18+, partita IVA).
/// - Modifica: data di nascita, tipo di account e partita IVA non si cambiano.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({
    super.key,
    required this.repository,
    required this.onSaved,
    this.initial,
    this.draft,
    this.onSignOut,
    this.pickImage = pickFromGallery,
    this.today,
  });

  final ProfileRepository repository;

  /// Chiamata dopo il salvataggio riuscito.
  final VoidCallback onSaved;

  /// Profilo esistente: se presente, la schermata è in modifica.
  final MyProfile? initial;

  /// Dati della registrazione ancora in memoria (tipo di account, data di nascita).
  final RegistrationDraft? draft;

  /// Solo in creazione: permette di uscire senza completare il profilo.
  final Future<void> Function()? onSignOut;
  final PickImage pickImage;
  final DateTime Function()? today;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  late final TextEditingController _username;
  late final TextEditingController _fullName;
  late final TextEditingController _bio;
  late final TextEditingController _businessName;
  late final TextEditingController _vat;
  late final TextEditingController _birth;
  late final Map<SocialNetwork, TextEditingController> _social;

  late AccountKind _kind;
  late bool _showBio;
  late bool _showSocial;
  Uint8List? _newPhoto;
  bool _removePhoto = false;
  bool _busy = false;
  bool _created = false;
  String? _error;
  final Map<String, String> _fieldErrors = <String, String>{};

  bool get _editing => widget.initial != null;
  bool get _askBirth => !_editing && widget.draft == null;
  DateTime get _today => (widget.today ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final MyProfile? p = widget.initial;
    _username = TextEditingController(text: p?.username ?? '');
    _fullName = TextEditingController(text: p?.fullName ?? '');
    _bio = TextEditingController(text: p?.bio ?? '');
    _businessName = TextEditingController(text: p?.businessName ?? '');
    _vat = TextEditingController(text: p?.vatNumber ?? '');
    _birth = TextEditingController();
    _social = <SocialNetwork, TextEditingController>{
      for (final SocialNetwork n in SocialNetwork.values)
        n: TextEditingController(text: p?.social[n] ?? ''),
    };
    _kind = p != null
        ? (p.isBusiness ? AccountKind.business : AccountKind.private)
        : (widget.draft?.kind ?? AccountKind.private);
    _showBio = p?.showBio ?? true;
    _showSocial = p?.showSocial ?? true;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _username, _fullName, _bio, _businessName, _vat, _birth, ..._social.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final Uint8List? bytes = await widget.pickImage();
      if (bytes != null && mounted) {
        setState(() {
          _newPhoto = bytes;
          _removePhoto = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Non è stato possibile aprire la galleria.');
    }
  }

  /// Controlli sul telefono: messaggi immediati, il server li ripete comunque.
  bool _validate() {
    _fieldErrors.clear();
    void put(String key, String? message) {
      if (message != null) _fieldErrors[key] = message;
    }

    put('username', ProfileRules.usernameError(_username.text));
    put('nome', ProfileRules.fullNameError(_fullName.text));
    put('bio', ProfileRules.bioError(_bio.text));
    for (final MapEntry<SocialNetwork, TextEditingController> e in _social.entries) {
      if (ProfileRules.normalizeSocialHandle(e.value.text) == null) {
        _fieldErrors['social_${e.key.key}'] = 'Scrivi solo il nome utente, senza link.';
      }
    }
    if (_kind == AccountKind.business) {
      put('ragione_sociale', ProfileRules.businessNameError(_businessName.text));
      if (!_editing && !ProfileRules.isValidPartitaIva(_vat.text)) {
        _fieldErrors['partita_iva'] = 'Partita IVA non valida (11 cifre).';
      }
    }
    if (_askBirth) {
      final DateTime? birth = RegistrationRules.parseBirthDate(_birth.text);
      switch (RegistrationRules.checkBirthDate(birth, _kind, _today)) {
        case BirthDateCheck.ok:
          break;
        case BirthDateCheck.invalid:
          _fieldErrors['nascita'] = 'Scrivi la data come GG/MM/AAAA.';
        case BirthDateCheck.tooYoung:
          _fieldErrors['nascita'] = 'Per usare Piazly devi avere almeno 14 anni.';
        case BirthDateCheck.businessNeedsAdult:
          _fieldErrors['nascita'] = 'L\'account Azienda è solo per maggiorenni.';
      }
    }
    return _fieldErrors.isEmpty;
  }

  Map<SocialNetwork, String> _socialValues() => <SocialNetwork, String>{
    for (final MapEntry<SocialNetwork, TextEditingController> e in _social.entries)
      if (ProfileRules.normalizeSocialHandle(e.value.text)?.isNotEmpty ?? false)
        e.key: ProfileRules.normalizeSocialHandle(e.value.text)!,
  };

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _validate();
    });
    if (_fieldErrors.isNotEmpty) return;
    setState(() => _busy = true);
    final String username = ProfileRules.normalizeUsername(_username.text)!;
    final bool business = _kind == AccountKind.business;
    try {
      if (username != widget.initial?.username &&
          !_created &&
          !await widget.repository.isUsernameAvailable(username)) {
        setState(() {
          _busy = false;
          _fieldErrors['username'] = 'Questo nome utente è già preso: scegline un altro.';
        });
        return;
      }
      if (!_editing && !_created) {
        final DateTime birth = widget.draft?.birthDate ??
            RegistrationRules.parseBirthDate(_birth.text)!;
        await widget.repository.create(
          NewProfile(
            username: username,
            fullName: _fullName.text.trim(),
            birthDate: birth,
            isBusiness: business,
            businessName: business ? _businessName.text.trim() : null,
            vatNumber: business ? _vat.text.replaceAll(' ', '') : null,
          ),
        );
        _created = true;
      }
      await widget.repository.update(
        ProfileUpdate(
          username: username,
          fullName: _fullName.text.trim(),
          bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
          social: _socialValues(),
          showBio: _showBio,
          showSocial: _showSocial,
          businessName: business ? _businessName.text.trim() : null,
        ),
      );
      if (_newPhoto != null) {
        await widget.repository.setAvatar(_newPhoto!);
      } else if (_removePhoto) {
        await widget.repository.removeAvatar();
      }
      if (!_editing) RegistrationDraftStore.current = null;
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSaved();
    } on ProfileFailure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Qualcosa non ha funzionato. Riprova.';
        });
      }
    }
  }

  InputDecoration _decoration(String key, String label, {String? helper, String? prefix}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        prefixText: prefix,
        errorText: _fieldErrors[key],
        errorMaxLines: 3,
        helperMaxLines: 3,
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool business = _kind == AccountKind.business;
    final String displayName = _fullName.text.trim().isEmpty
        ? _username.text
        : _fullName.text;
    final bool hasPhoto = _newPhoto != null ||
        (!_removePhoto && widget.initial?.avatarThumbPath != null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifica profilo' : 'Completa il profilo'),
        automaticallyImplyLeading: _editing,
        actions: [
          if (!_editing && widget.onSignOut != null)
            TextButton(onPressed: widget.onSignOut, child: const Text('Esci')),
        ],
      ),
      body: Stack(
        children: [
          NexusBackdrop(isDark: theme.brightness == Brightness.dark),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (!_editing) ...[
                  Text(
                    'Ultimo passo: scegli come ti vedranno gli altri.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Center(
                  child: Column(
                    children: [
                      AvatarView(
                        name: displayName,
                        repository: widget.repository,
                        path: _removePhoto ? null : widget.initial?.avatarThumbPath,
                        bytes: _newPhoto,
                        size: 96,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton.icon(
                            key: const ValueKey<String>('scegli_foto'),
                            onPressed: _busy ? null : _choosePhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(hasPhoto ? 'Cambia foto' : 'Aggiungi foto'),
                          ),
                          if (hasPhoto)
                            TextButton(
                              key: const ValueKey<String>('togli_foto'),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _newPhoto = null;
                                      _removePhoto = true;
                                    }),
                              child: const Text('Togli foto'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chi sei', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      if (_askBirth) ...[
                        SegmentedButton<AccountKind>(
                          segments: const <ButtonSegment<AccountKind>>[
                            ButtonSegment<AccountKind>(
                              value: AccountKind.private,
                              label: Text('Privato'),
                              icon: Icon(Icons.person_outline_rounded),
                            ),
                            ButtonSegment<AccountKind>(
                              value: AccountKind.business,
                              label: Text('Azienda'),
                              icon: Icon(Icons.storefront_outlined),
                            ),
                          ],
                          selected: <AccountKind>{_kind},
                          onSelectionChanged: (Set<AccountKind> s) =>
                              setState(() => _kind = s.first),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const ValueKey<String>('nascita'),
                          controller: _birth,
                          keyboardType: TextInputType.datetime,
                          decoration: _decoration(
                            'nascita',
                            'Data di nascita',
                            helper: 'GG/MM/AAAA · resta privata, serve solo per l\'età',
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        key: const ValueKey<String>('username'),
                        controller: _username,
                        autocorrect: false,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          LengthLimitingTextInputFormatter(25),
                        ],
                        decoration: _decoration(
                          'username',
                          'Nome utente',
                          prefix: '@',
                          helper: 'Unico. Lettere minuscole, numeri, punto e trattino basso',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey<String>('nome'),
                        controller: _fullName,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          'nome',
                          'Nome e cognome',
                          helper: _fullName.text.trim().contains(' ')
                              ? 'In pubblico vedranno solo «'
                                    '${ProfileRules.shortPublicName(_fullName.text)}»'
                              : 'In pubblico vedranno solo nome e iniziale del cognome',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                if (business) ...[
                  const SizedBox(height: 14),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dati Azienda', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey<String>('ragione_sociale'),
                          controller: _businessName,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration(
                            'ragione_sociale',
                            'Ragione sociale',
                            helper: 'Visibile nel profilo pubblico',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const ValueKey<String>('partita_iva'),
                          controller: _vat,
                          enabled: !_editing,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: _decoration(
                            'partita_iva',
                            'Partita IVA',
                            helper: 'Privata: non compare mai nel profilo pubblico',
                          ),
                        ),
                        if (_editing && widget.initial?.businessStatus != null) ...[
                          const SizedBox(height: 12),
                          _StatusLine(status: widget.initial!.businessStatus!),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bio', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>('bio'),
                        controller: _bio,
                        maxLines: 4,
                        minLines: 2,
                        maxLength: ProfileRules.bioMaxLength,
                        decoration: _decoration('bio', 'Qualcosa su di te (facoltativo)'),
                      ),
                      SwitchListTile(
                        key: const ValueKey<String>('mostra_bio'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostra nel profilo pubblico'),
                        value: _showBio,
                        onChanged: (bool v) => setState(() => _showBio = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Social', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Facoltativi: scrivi solo il tuo nome utente.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final SocialNetwork n in SocialNetwork.values)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            key: ValueKey<String>('social_${n.key}'),
                            controller: _social[n],
                            autocorrect: false,
                            decoration: _decoration('social_${n.key}', n.label, prefix: '@'),
                          ),
                        ),
                      SwitchListTile(
                        key: const ValueKey<String>('mostra_social'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostra nel profilo pubblico'),
                        value: _showSocial,
                        onChanged: (bool v) => setState(() => _showSocial = v),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBox(message: _error!),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey<String>('salva_profilo'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: AppColors.brandOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                        )
                      : Text(_editing ? 'Salva' : 'Crea il profilo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final BusinessStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, String text) = switch (status) {
      BusinessStatus.pending => (Icons.hourglass_top_rounded, 'Azienda in verifica'),
      BusinessStatus.verified => (Icons.verified_rounded, 'Azienda verificata'),
      BusinessStatus.rejected => (Icons.info_outline_rounded, 'Verifica non superata'),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: 8),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.error;
    return Container(
      key: const ValueKey<String>('errore_profilo'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
