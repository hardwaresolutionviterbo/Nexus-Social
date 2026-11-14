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
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey<_Step>(_step),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
              children: [
                Row(
                  children: [
                    const NexusMark(size: 34),
                    const SizedBox(width: 12),
                    const NexusWordmark(),
                    const Spacer(),
                    if (_step != _Step.welcome && _step != _Step.blocked)
                      TextButton(
                        onPressed: _busy ? null : _restart,
                        child: const Text('Ricomincia'),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                ..._content(theme),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    key: const ValueKey<String>('errore'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(ThemeData theme) {
    switch (_step) {
      case _Step.welcome:
        return [
          Text('Benvenuto', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Chat, Mappa Social, scambi e vendita vicino a te. Come vuoi registrarti?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _KindButton(
            icon: Icons.person_rounded,
            color: AppColors.brandBlue,
            title: 'Registrati come Privato',
            detail: 'Chat, Mappa Social, scambi e vendita tra privati',
            onTap: () => _chooseKind(AccountKind.private),
          ),
          const SizedBox(height: 12),
          _KindButton(
            icon: Icons.storefront_rounded,
            color: AppColors.brandOrange,
            title: 'Registrati come Azienda',
            detail: 'Per attività commerciali. Solo maggiorenni',
            onTap: () => _chooseKind(AccountKind.business),
          ),
        ];

      case _Step.birthDate:
        return [
          Text('Data di nascita', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Serve solo a verificare l\'età minima (14 anni'
            '${_kind == AccountKind.business ? '; 18 per le aziende' : ''}). '
            'Resta privata: nessuno la vede.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey<String>('data-nascita'),
            controller: _birthController,
            keyboardType: TextInputType.datetime,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9/.-]'))],
            decoration: const InputDecoration(
              labelText: 'GG/MM/AAAA',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submitBirthDate(),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _submitBirthDate, child: const Text('Avanti')),
        ];

      case _Step.blocked:
        final bool tooYoung = _blockReason == BirthDateCheck.tooYoung;
        return [
          Icon(Icons.lock_outline_rounded, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            tooYoung ? 'Non puoi ancora registrarti' : 'Account Azienda solo per maggiorenni',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            tooYoung
                ? 'Per usare Nexus Social devi avere almeno 14 anni. '
                      'Non abbiamo salvato nessun dato.'
                : 'La registrazione come Azienda è riservata ai maggiorenni. '
                      'Non abbiamo salvato nessun dato.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (!tooYoung) ...[
            FilledButton(
              onPressed: () {
                _kind = AccountKind.private;
                _go(_Step.birthDate);
              },
              child: const Text('Registrati come Privato'),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton(onPressed: _restart, child: const Text('Torna all\'inizio')),
        ];

      case _Step.terms:
        return [
          Text('Termini e Privacy', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          const _DraftNotice(),
          const SizedBox(height: 16),
          for (final (String title, String asset) in const [
            ('Termini d\'uso', 'docs/fase0/BOZZA_TERMINI_USO.md'),
            ('Privacy Policy', 'docs/fase0/BOZZA_PRIVACY_POLICY.md'),
            ('Regole della community', 'docs/fase0/BOZZA_REGOLE_COMMUNITY.md'),
          ])
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(title),
                subtitle: const Text('Bozza · tocca per leggere'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showDocument(title, asset),
              ),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey<String>('accetto'),
            value: _termsAccepted,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Ho letto e accetto Termini d\'uso, Privacy Policy e Regole della community '
              '(bozze non validate)',
            ),
            onChanged: (bool? value) => setState(() => _termsAccepted = value ?? false),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _termsAccepted ? () => _go(_Step.phone) : null,
            child: const Text('Accetta e continua'),
          ),
        ];

      case _Step.phone:
        return [
          Text('Il tuo numero', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Ti inviamo un codice via SMS. Il numero resta privato: non compare mai sulla mappa, '
            'negli annunci o nei gruppi.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey<String>('telefono'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_busy,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
            decoration: const InputDecoration(
              prefixText: '+39 ',
              labelText: 'Numero di cellulare',
              helperText: 'Solo numeri italiani',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _sendCode,
            child: _busy ? const _Spinner() : const Text('Invia codice'),
          ),
        ];

      case _Step.code:
        return [
          Text('Codice SMS', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Scrivi il codice di 6 cifre inviato a ${_maskedPhone()}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey<String>('codice'),
            controller: _codeController,
            keyboardType: TextInputType.number,
            enabled: !_busy,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Codice',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _confirmCode(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _confirmCode,
            child: _busy ? const _Spinner() : const Text('Conferma'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    _codeController.clear();
                    _go(_Step.phone);
                  },
            child: const Text('Cambia numero'),
          ),
        ];
    }
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

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient(color),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
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
