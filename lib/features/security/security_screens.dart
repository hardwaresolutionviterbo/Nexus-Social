import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../profile/profile_repository.dart' show ProfileFailure;
import 'app_lock.dart';
import 'security_repository.dart';

String _dateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    'alle ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Campo per un PIN di 6 cifre, nascosto.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, letterSpacing: 14, fontWeight: FontWeight.w700),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(labelText: label, errorText: errorText, counterText: ''),
      onSubmitted: onSubmitted,
    );
  }
}

/// Telefono nuovo con la verifica in due passaggi attiva: prima di entrare serve il PIN.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({
    super.key,
    required this.repository,
    required this.initialStatus,
    required this.onVerified,
    required this.onSignOut,
  });

  final SecurityRepository repository;
  final SecurityStatus initialStatus;
  final VoidCallback onVerified;
  final Future<void> Function() onSignOut;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final TextEditingController _pin = TextEditingController();
  late SecurityStatus _status = widget.initialStatus;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!PinRules.isValid(_pin.text)) {
      setState(() => _error = 'Il PIN ha 6 cifre.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bool ok = await widget.repository.verifyPin(_pin.text);
      if (!mounted) return;
      if (ok) {
        widget.onVerified();
        return;
      }
      final SecurityStatus s = await widget.repository.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _busy = false;
        _pin.clear();
        _error = s.lockedUntil != null
            ? 'Troppi tentativi. Riprova dopo il ${_dateTime(s.lockedUntil!)}.'
            : 'PIN errato. Riprova.';
      });
    } on ProfileFailure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message;
        });
      }
    }
  }

  Future<void> _forgot() async {
    final DateTime? available = _status.resetAvailableAt;
    if (available != null && !available.isAfter(DateTime.now())) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Togliere il PIN?'),
          content: const Text(
            'Sono passati 7 giorni dalla richiesta: puoi entrare e impostare un nuovo PIN '
            'dalle impostazioni di sicurezza.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              key: const ValueKey<String>('conferma_ripristino'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Togli il PIN'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await widget.repository.completeReset();
        widget.onVerified();
      } on ProfileFailure catch (f) {
        if (mounted) setState(() => _error = f.message);
      }
      return;
    }
    try {
      final DateTime? at = await widget.repository.requestReset();
      final SecurityStatus s = await widget.repository.status();
      if (!mounted) return;
      setState(() => _status = s);
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('PIN dimenticato'),
          content: Text(
            'Per proteggere il tuo account il PIN si può togliere solo dopo 7 giorni dalla '
            'richiesta${at != null ? ': dal ${_dateTime(at)}' : ''}. Se nel frattempo ricordi '
            'il PIN, puoi inserirlo come sempre.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
    } on ProfileFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? locked = _status.lockedUntil;
    final bool isLocked = locked != null && locked.isAfter(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifica in due passaggi'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: widget.onSignOut, child: const Text('Esci')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            const Center(child: NexusMark(size: 56)),
            const SizedBox(height: 18),
            Text(
              'Inserisci il PIN',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Stai entrando da un telefono nuovo. Inserisci il PIN di 6 cifre che hai scelto '
              'per la verifica in due passaggi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            PinField(
              key: const ValueKey<String>('pin_accesso'),
              controller: _pin,
              label: 'PIN',
              errorText: _error,
              autofocus: true,
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey<String>('verifica_pin'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy || isLocked ? null : _verify,
              child: const Text('Conferma'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey<String>('pin_dimenticato'),
              onPressed: _busy ? null : _forgot,
              child: const Text('PIN dimenticato?'),
            ),
            if (_status.resetAvailableAt != null)
              Text(
                'Ripristino richiesto: disponibile dal ${_dateTime(_status.resetAvailableAt!)}.',
                key: const ValueKey<String>('ripristino_richiesto'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Impostazioni «Sicurezza dell'account»: PIN (S2) e impronta o volto (S3).
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key, required this.repository, required this.lock});

  final SecurityRepository repository;
  final BiometricLock lock;

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  SecurityStatus? _status;
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final SecurityStatus s = await widget.repository.status();
      final bool available = await widget.lock.isAvailable();
      final bool enabled = await widget.lock.isEnabled();
      if (!mounted) return;
      setState(() {
        _status = s;
        _bioAvailable = available;
        _bioEnabled = enabled;
        _error = null;
      });
    } on ProfileFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  Future<void> _openPinFlow(_PinFlow flow) async {
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _PinFlowScreen(flow: flow, repository: widget.repository),
      ),
    );
    if (done == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(flow.doneMessage)),
      );
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final bool ok = await widget.lock.authenticate('Conferma per attivare lo sblocco');
      if (!ok) {
        if (mounted) setState(() => _error = 'Impronta o volto non confermati.');
        return;
      }
    }
    await widget.lock.setEnabled(value);
    if (mounted) {
      setState(() {
        _bioEnabled = value;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SecurityStatus? s = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Sicurezza dell\'account')),
      body: s == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verifica in due passaggi', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        'Un PIN di 6 cifre, chiesto quando entri da un telefono nuovo. '
                        'Protegge l\'account anche se qualcuno riceve il tuo codice SMS.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s?.pinEnabled ?? false ? 'Attiva' : 'Non attiva',
                        key: const ValueKey<String>('stato_pin'),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (!(s?.pinEnabled ?? false))
                        FilledButton(
                          key: const ValueKey<String>('attiva_pin'),
                          onPressed: () => _openPinFlow(_PinFlow.enable),
                          child: const Text('Attiva'),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              key: const ValueKey<String>('cambia_pin'),
                              onPressed: () => _openPinFlow(_PinFlow.change),
                              child: const Text('Cambia PIN'),
                            ),
                            TextButton(
                              key: const ValueKey<String>('disattiva_pin'),
                              onPressed: () => _openPinFlow(_PinFlow.disable),
                              child: const Text('Disattiva'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  child: SwitchListTile(
                    key: const ValueKey<String>('sblocco_impronta'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sblocco con impronta o volto'),
                    subtitle: Text(
                      _bioAvailable
                          ? 'Facoltativo: se attivo, serve per aprire Piazly'
                          : 'Non disponibile su questo telefono',
                    ),
                    value: _bioEnabled,
                    onChanged: _bioAvailable || _bioEnabled ? _toggleBiometric : null,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
    );
  }
}

enum _PinFlow {
  enable('Attiva il PIN', 'Verifica in due passaggi attivata.'),
  change('Cambia PIN', 'PIN cambiato.'),
  disable('Disattiva il PIN', 'Verifica in due passaggi disattivata.');

  const _PinFlow(this.title, this.doneMessage);

  final String title;
  final String doneMessage;
}

class _PinFlowScreen extends StatefulWidget {
  const _PinFlowScreen({required this.flow, required this.repository});

  final _PinFlow flow;
  final SecurityRepository repository;

  @override
  State<_PinFlowScreen> createState() => _PinFlowScreenState();
}

class _PinFlowScreenState extends State<_PinFlowScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  final Map<String, String> _errors = <String, String>{};
  bool _busy = false;
  String? _error;

  bool get _needsCurrent => widget.flow != _PinFlow.enable;
  bool get _needsNew => widget.flow != _PinFlow.disable;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _errors.clear();
    if (_needsCurrent && !PinRules.isValid(_current.text)) {
      _errors['attuale'] = 'Il PIN ha 6 cifre.';
    }
    if (_needsNew) {
      if (!PinRules.isValid(_new.text)) {
        _errors['nuovo'] = 'Scegli 6 cifre.';
      } else if (_repeat.text != _new.text) {
        _errors['ripeti'] = 'I due PIN non coincidono.';
      }
    }
    setState(() => _error = null);
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      switch (widget.flow) {
        case _PinFlow.enable:
          await widget.repository.setPin(_new.text);
        case _PinFlow.change:
          await widget.repository.setPin(_new.text, currentPin: _current.text);
        case _PinFlow.disable:
          await widget.repository.disablePin(_current.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ProfileFailure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.flow.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          if (widget.flow == _PinFlow.enable)
            Text(
              'Scegli un PIN di 6 cifre che ricorderai. Ti verrà chiesto quando entri da un '
              'telefono nuovo. Se lo dimentichi, potrai toglierlo solo dopo 7 giorni.',
              style: theme.textTheme.bodyMedium,
            ),
          if (_needsCurrent)
            PinField(
              key: const ValueKey<String>('pin_attuale'),
              controller: _current,
              label: 'PIN attuale',
              errorText: _errors['attuale'],
            ),
          if (_needsNew) ...[
            const SizedBox(height: 12),
            PinField(
              key: const ValueKey<String>('pin_nuovo'),
              controller: _new,
              label: 'Nuovo PIN',
              errorText: _errors['nuovo'],
            ),
            const SizedBox(height: 12),
            PinField(
              key: const ValueKey<String>('pin_ripeti'),
              controller: _repeat,
              label: 'Ripeti il PIN',
              errorText: _errors['ripeti'],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 22),
          FilledButton(
            key: const ValueKey<String>('conferma_pin'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: AppColors.brandOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : _submit,
            child: Text(widget.flow == _PinFlow.disable ? 'Disattiva' : 'Salva'),
          ),
        ],
      ),
    );
  }
}
