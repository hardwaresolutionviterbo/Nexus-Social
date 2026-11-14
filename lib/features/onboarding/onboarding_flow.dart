import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/services/auth_gateway.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import 'registration_rules.dart';

/// Registrazione e accesso (Fase 2, Blocco 1).
///
/// Ordine (piano della Fase 2, sezione 5): tipo di account → data di nascita, controllata
/// sul telefono prima di creare l'account (M2, M6) → Termini e Privacy in bozza (S7) →
/// numero (+39, L3) → codice SMS.
///
/// Fino all'invio del numero non viene salvato né inviato nulla. Tipo di account, data di
/// nascita e accettazione restano solo in memoria: si salvano con il profilo (Blocco 2).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.gateway,
    this.today,
    this.onDraftReady,
  });

  final AuthGateway gateway;

  /// Riceve i dati raccolti (tipo, data di nascita, accettazione) appena prima dell'invio
  /// del numero: restano in memoria per il Blocco 2.
  final ValueChanged<RegistrationDraft>? onDraftReady;

  /// Data di oggi; nei test si può fissare.
  final DateTime Function()? today;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { welcome, birthDate, blocked, terms, phone, code }

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.welcome;
  AccountKind _kind = AccountKind.private;
  DateTime? _birthDate;
  BirthDateCheck? _blockReason;
  bool _termsAccepted = false;
  String? _phone;
  CodeRequest? _codeRequest;
  bool _busy = false;
  String? _error;

  final TextEditingController _birthController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _birthController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  DateTime get _today => (widget.today ?? DateTime.now)();

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  /// Torna all'inizio cancellando tutto ciò che è stato inserito.
  void _restart() => setState(() {
    _step = _Step.welcome;
    _kind = AccountKind.private;
    _birthDate = null;
    _blockReason = null;
    _termsAccepted = false;
    _phone = null;
    _codeRequest = null;
    _error = null;
    _birthController.clear();
    _phoneController.clear();
    _codeController.clear();
  });

  void _chooseKind(AccountKind kind) {
    _kind = kind;
    _go(_Step.birthDate);
  }

  void _submitBirthDate() {
    final DateTime? date = RegistrationRules.parseBirthDate(_birthController.text);
    final BirthDateCheck check = RegistrationRules.checkBirthDate(date, _kind, _today);
    switch (check) {
      case BirthDateCheck.invalid:
        setState(() => _error = 'Scrivi una data valida, per esempio 24/05/2001.');
      case BirthDateCheck.tooYoung:
      case BirthDateCheck.businessNeedsAdult:
        // M2: nessun dato conservato, nemmeno in memoria.
        _birthController.clear();
        setState(() {
          _birthDate = null;
          _blockReason = check;
          _step = _Step.blocked;
          _error = null;
        });
      case BirthDateCheck.ok:
        _birthDate = date;
        _go(_Step.terms);
    }
  }

  Future<void> _sendCode() async {
    final String? phone = RegistrationRules.italianMobile(_phoneController.text);
    if (phone == null) {
      setState(() => _error = 'Scrivi un numero di cellulare italiano, per esempio 333 123 4567.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onDraftReady?.call(
      RegistrationDraft(kind: _kind, birthDate: _birthDate!, termsAcceptedAt: _today),
    );
    try {
      final CodeRequest request = await widget.gateway.sendCode(phone);
      if (!mounted) return;
      _phone = phone;
      _codeRequest = request;
      if (request.autoSignedIn) {
        // Codice letto in automatico: l'accesso è già fatto, ci pensa il controllo d'accesso.
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _step = _Step.code;
      });
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _confirmCode() async {
    final String code = _codeController.text.trim();
    if (!RegistrationRules.isSmsCode(code)) {
      setState(() => _error = 'Il codice ha 6 cifre.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.confirmCode(_codeRequest!, code);
      if (!mounted) return;
      setState(() => _busy = false);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final _StepView view = _view(theme);
    return Stack(
      children: [
        ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: const SizedBox.expand(),
        ),
        NexusBackdrop(isDark: isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 12, 0),
                  child: Row(
                    children: [
                      const NexusMark(size: 36),
                      const SizedBox(width: 12),
                      const Flexible(child: NexusWordmark()),
                      const Spacer(),
                      if (_step != _Step.welcome && _step != _Step.blocked)
                        TextButton(
                          onPressed: _busy ? null : _restart,
                          child: const Text('Ricomincia'),
                        ),
                    ],
                  ),
                ),
                if (view.progress != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                    child: _Progress(step: view.progress!, total: 4),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: KeyedSubtree(
                      key: ValueKey<_Step>(_step),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                        children: [
                          ...view.body,
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            _ErrorBox(message: _error!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (view.actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: view.actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  _StepView _view(ThemeData theme) {
    final Color muted = theme.colorScheme.onSurfaceVariant;
    switch (_step) {
      case _Step.welcome:
        return _StepView(
          body: [
            const FadeSlideIn(child: _WelcomeHero()),
            const SizedBox(height: 26),
            FadeSlideIn(
              delay: 0.12,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Il tuo mondo,\n'),
                    TextSpan(
                      text: 'vicino a te.',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
                style: theme.textTheme.headlineMedium?.copyWith(height: 1.1),
              ),
            ),
            const SizedBox(height: 10),
            FadeSlideIn(
              delay: 0.18,
              child: Text(
                'Chatta con chi conosci, scopri persone ed eventi sulla Mappa Social, '
                'scambia e vendi nella tua zona.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
            const SizedBox(height: 16),
            const FadeSlideIn(
              delay: 0.24,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FeatureChip(
                    icon: Icons.lock_rounded,
                    label: 'Chat cifrate',
                    color: AppColors.brandBlue,
                  ),
                  _FeatureChip(
                    icon: Icons.map_rounded,
                    label: 'Mappa Social',
                    color: AppColors.brandCyan,
                  ),
                  _FeatureChip(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Scambia e vendi',
                    color: AppColors.brandOrange,
                  ),
                ],
              ),
            ),
          ],
          actions: [
            _KindButton(
              primary: true,
              icon: Icons.person_rounded,
              title: 'Registrati come Privato',
              detail: 'Chat, Mappa Social, scambi e vendita tra privati',
              onTap: () => _chooseKind(AccountKind.private),
            ),
            const SizedBox(height: 10),
            _KindButton(
              icon: Icons.storefront_rounded,
              title: 'Registrati come Azienda',
              detail: 'Per attività commerciali · solo maggiorenni',
              onTap: () => _chooseKind(AccountKind.business),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Il tuo numero resta privato. Sempre.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ],
        );

      case _Step.birthDate:
        return _StepView(
          progress: 1,
          body: [
            _StepHeader(
              icon: Icons.cake_rounded,
              color: AppColors.brandBlue,
              title: 'Quando sei nato?',
              subtitle:
                  'Serve solo a verificare l\'età minima (14 anni'
                  '${_kind == AccountKind.business ? '; 18 per le aziende' : ''}). '
                  'Resta privata: nessuno la vede.',
            ),
            const SizedBox(height: 22),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey<String>('data-nascita'),
                    controller: _birthController,
                    keyboardType: TextInputType.datetime,
                    style: theme.textTheme.titleLarge,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9/.-]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Data di nascita',
                      hintText: 'GG/MM/AAAA',
                      prefixIcon: Icon(Icons.event_rounded),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitBirthDate(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _pickBirthDate,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: const Text('Scegli dal calendario'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          actions: [_PrimaryButton(label: 'Avanti', onPressed: _submitBirthDate)],
        );

      case _Step.blocked:
        final bool tooYoung = _blockReason == BirthDateCheck.tooYoung;
        return _StepView(
          body: [
            _StepHeader(
              icon: Icons.lock_rounded,
              color: AppColors.brandCoral,
              title: tooYoung
                  ? 'Non puoi ancora registrarti'
                  : 'Account Azienda solo per maggiorenni',
              subtitle: tooYoung
                  ? 'Per usare Nexus Social devi avere almeno 14 anni. '
                        'Non abbiamo salvato nessun dato.'
                  : 'La registrazione come Azienda è riservata ai maggiorenni. '
                        'Non abbiamo salvato nessun dato.',
            ),
          ],
          actions: [
            if (!tooYoung) ...[
              _PrimaryButton(
                label: 'Registrati come Privato',
                onPressed: () {
                  _kind = AccountKind.private;
                  _go(_Step.birthDate);
                },
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _restart,
              child: const Text('Torna all\'inizio'),
            ),
          ],
        );

      case _Step.terms:
        return _StepView(
          progress: 2,
          body: [
            const _StepHeader(
              icon: Icons.verified_user_rounded,
              color: AppColors.brandViolet,
              title: 'Termini e Privacy',
              subtitle: 'Leggi come funzionano Nexus Social e la tua privacy.',
            ),
            const SizedBox(height: 18),
            const _DraftNotice(),
            const SizedBox(height: 14),
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final (String title, String asset, IconData icon) in const [
                    ('Termini d\'uso', 'docs/fase0/BOZZA_TERMINI_USO.md', Icons.gavel_rounded),
                    ('Privacy Policy', 'docs/fase0/BOZZA_PRIVACY_POLICY.md', Icons.privacy_tip_rounded),
                    (
                      'Regole della community',
                      'docs/fase0/BOZZA_REGOLE_COMMUNITY.md',
                      Icons.diversity_3_rounded,
                    ),
                  ])
                    ListTile(
                      leading: Icon(icon),
                      title: Text(title),
                      subtitle: const Text('Bozza · tocca per leggere'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showDocument(title, asset),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: CheckboxListTile(
                key: const ValueKey<String>('accetto'),
                value: _termsAccepted,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Ho letto e accetto Termini d\'uso, Privacy Policy e Regole della community '
                  '(bozze non validate)',
                ),
                onChanged: (bool? value) => setState(() => _termsAccepted = value ?? false),
              ),
            ),
          ],
          actions: [
            _PrimaryButton(
              label: 'Accetta e continua',
              onPressed: _termsAccepted ? () => _go(_Step.phone) : null,
            ),
          ],
        );

      case _Step.phone:
        return _StepView(
          progress: 3,
          body: [
            const _StepHeader(
              icon: Icons.phone_iphone_rounded,
              color: AppColors.brandOrange,
              title: 'Il tuo numero',
              subtitle: 'Ti inviamo un codice via SMS per confermare che è tuo.',
            ),
            const SizedBox(height: 22),
            SectionCard(
              child: TextField(
                key: const ValueKey<String>('telefono'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                enabled: !_busy,
                style: theme.textTheme.titleLarge,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
                decoration: const InputDecoration(
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Text('🇮🇹  +39', style: TextStyle(fontSize: 18)),
                  ),
                  prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                  labelText: 'Numero di cellulare',
                  helperText: 'Solo numeri italiani',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _sendCode(),
              ),
            ),
            const SizedBox(height: 14),
            const _InfoRow(
              icon: Icons.visibility_off_rounded,
              text:
                  'Il numero resta privato: non compare mai sulla mappa, negli annunci, '
                  'nei commenti o nei gruppi.',
            ),
          ],
          actions: [
            _PrimaryButton(
              label: 'Invia codice',
              busy: _busy,
              onPressed: _busy ? null : _sendCode,
            ),
          ],
        );

      case _Step.code:
        return _StepView(
          progress: 4,
          body: [
            _StepHeader(
              icon: Icons.sms_rounded,
              color: AppColors.brandMint,
              title: 'Codice SMS',
              subtitle: 'Scrivi il codice di 6 cifre inviato a ${_maskedPhone()}.',
            ),
            const SizedBox(height: 22),
            SectionCard(
              child: TextField(
                key: const ValueKey<String>('codice'),
                controller: _codeController,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 10),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  hintText: '••••••',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _confirmCode(),
              ),
            ),
          ],
          actions: [
            _PrimaryButton(
              label: 'Conferma',
              busy: _busy,
              onPressed: _busy ? null : _confirmCode,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _codeController.clear();
                      _go(_Step.phone);
                    },
              child: const Text('Cambia numero'),
            ),
          ],
        );
    }
  }

  Future<void> _pickBirthDate() async {
    final DateTime today = _today;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(today.year - 20, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Data di nascita',
    );
    if (picked == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    _birthController.text = '${two(picked.day)}/${two(picked.month)}/${picked.year}';
  }

  /// Mostra solo le ultime cifre, per non esporre il numero sullo schermo.
  String _maskedPhone() {
    final String p = _phone ?? '';
    return p.length < 4 ? p : '+39 ••• ••• ${p.substring(p.length - 3)}';
  }

  Future<void> _showDocument(String title, String asset) async {
    final String text = await DefaultAssetBundle.of(context).loadString(asset);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (BuildContext context, ScrollController controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const _DraftNotice(),
            const SizedBox(height: 14),
            SelectableText(text, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StepView {
  const _StepView({this.progress, required this.body, this.actions = const []});

  final int? progress;
  final List<Widget> body;
  final List<Widget> actions;
}

/// Avanzamento della registrazione: «Passo 2 di 4» con barre colorate.
class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: [
        for (int i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: i <= step ? AppColors.orangeGradient : null,
                color: i <= step ? null : theme.colorScheme.outline.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        Text(
          'Passo $step di $total',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Titolo di un passo con icona in un riquadro colorato e luminoso.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FadeSlideIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient(color),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.40),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 20),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsante principale a tutta larghezza, arancio con bagliore.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.brandOrange.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: AppColors.brandOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
        ),
        onPressed: onPressed,
        child: busy ? const _Spinner() : Text(label),
      ),
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
      key: const ValueKey<String>('errore'),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Illustrazione della schermata iniziale: una piccola Mappa Social con persone,
/// luoghi ed eventi, disegnata con widget (nessuna immagine esterna).
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14204A), Color(0xFF1E2A6E), Color(0xFF3A1F5C)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.30),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
          // Persone (avatar rotondi) e luoghi (gocce colorate), come nel mockup.
          const Positioned(left: 34, top: 40, child: _Avatar(letter: 'G', color: AppColors.brandBlue)),
          const Positioned(right: 54, top: 30, child: _Pin(color: AppColors.brandOrange, icon: Icons.local_cafe_rounded)),
          const Positioned(left: 120, bottom: 46, child: _Pin(color: Color(0xFF22C55E), icon: Icons.celebration_rounded)),
          const Positioned(right: 36, bottom: 70, child: _Avatar(letter: 'M', color: AppColors.brandViolet)),
          const Positioned(left: 50, bottom: 104, child: _Pin(color: AppColors.brandCoral, icon: Icons.sell_rounded)),
          const Positioned(left: 156, top: 86, child: _Avatar(letter: 'S', color: AppColors.brandCyan, size: 52, me: true)),
          // Fumetto di chat.
          Positioned(
            right: 18,
            top: 98,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14),
                ],
              ),
              child: const Text(
                'Un caffè al bar? ☕',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          // Etichetta in basso.
          Positioned(
            left: 16,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.near_me_rounded, color: Colors.white, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'Persone ed eventi vicino a te',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Strade e isolati stilizzati della mappa illustrata.
class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint road = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final Paint lane = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 4;
    canvas
      ..drawLine(Offset(0, size.height * 0.62), Offset(size.width, size.height * 0.38), road)
      ..drawLine(Offset(size.width * 0.28, 0), Offset(size.width * 0.44, size.height), road)
      ..drawLine(Offset(size.width * 0.72, 0), Offset(size.width * 0.86, size.height), lane)
      ..drawLine(Offset(0, size.height * 0.2), Offset(size.width, size.height * 0.12), lane)
      ..drawLine(Offset(0, size.height * 0.9), Offset(size.width, size.height * 0.78), lane);
    // Zona approssimata intorno all'utente (posizione mai esatta).
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.46),
      70,
      Paint()..color = AppColors.brandCyan.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.letter,
    required this.color,
    this.size = 40,
    this.me = false,
  });

  final String letter;
  final Color color;
  final double size;
  final bool me;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradient(color),
        border: Border.all(color: me ? AppColors.brandOrange : Colors.white, width: me ? 3 : 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: me ? 24 : 14),
        ],
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 46,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 46,
            color: color,
            shadows: [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 14)],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fg = primary ? Colors.white : theme.colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: primary ? AppColors.orangeGradient : null,
        color: primary
            ? null
            : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
        border: Border.all(
          color: primary
              ? Colors.white.withValues(alpha: 0.25)
              : theme.colorScheme.outline,
        ),
        boxShadow: [
          BoxShadow(
            color: primary
                ? AppColors.brandOrange.withValues(alpha: 0.38)
                : Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: primary ? 24 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary
                        ? Colors.white.withValues(alpha: 0.22)
                        : AppColors.brandOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: primary ? Colors.white : AppColors.brandOrange),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(color: fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: primary
                              ? Colors.white.withValues(alpha: 0.85)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avviso obbligatorio sulle bozze legali (S7).
class _DraftNotice extends StatelessWidget {
  const _DraftNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandAmber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandAmber.withValues(alpha: 0.5)),
      ),
      child: Text(
        'Bozza non validata: questi testi non sono ancora stati verificati da un '
        'professionista e potranno cambiare prima della pubblicazione dell\'app.',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.4),
    );
  }
}
