import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/nexus_ui.dart';
import '../profile/profile_repository.dart';
import 'privacy_controller.dart';
import 'privacy_sections.dart';

/// Percorso guidato «Controllo privacy» (R2.9, `PRIVACY_IMPOSTAZIONI.md` §4).
///
/// Otto passi: le sette sezioni della pagina Privacy e un riepilogo con «Modifica».
/// Ogni scelta si salva subito (P15); si può uscire in qualsiasi momento. Alla fine della
/// registrazione viene proposto e si può saltare (P14).
class PrivacyCheckupScreen extends StatefulWidget {
  const PrivacyCheckupScreen({
    super.key,
    required this.controller,
    required this.onDone,
    this.profiles,
    this.onPreview,
    this.offeredAfterSignUp = false,
  });

  final PrivacyController controller;
  final VoidCallback onDone;
  final ProfileRepository? profiles;
  final VoidCallback? onPreview;

  /// Proposto subito dopo la registrazione: il pulsante d'uscita dice «Salta».
  final bool offeredAfterSignUp;

  static const int stepCount = 8;

  static const List<String> explanations = <String>[
    'Ecco cosa vedono gli altri utenti di te. Bio e social si possono nascondere.',
    'Scegli chi può vedere il tuo numero di telefono.',
    'La rubrica serve a trovare chi conosci. È facoltativa e la puoi revocare.',
    'Come funziona la posizione dei tuoi annunci.',
    'La condivisione della posizione in tempo reale e come interromperla.',
    'Le persone che hai bloccato e come sbloccarle.',
    'I permessi del telefono e i consensi che hai dato a Piazly.',
    'Le tue scelte attuali in una schermata.',
  ];

  @override
  State<PrivacyCheckupScreen> createState() => _PrivacyCheckupScreenState();
}

class _PrivacyCheckupScreenState extends State<PrivacyCheckupScreen> {
  int _step = 0;

  bool get _last => _step == PrivacyCheckupScreen.stepCount - 1;

  void _go(int step) => setState(() => _step = step);

  String get _title => _last ? 'Riepilogo' : PrivacySection.values[_step].title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controllo privacy'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            key: const ValueKey<String>('esci_controllo'),
            onPressed: widget.onDone,
            child: Text(widget.offeredAfterSignUp && _step == 0 ? 'Salta' : 'Esci'),
          ),
        ],
      ),
      body: Stack(
        children: [
          NexusBackdrop(isDark: theme.brightness == Brightness.dark),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (_step + 1) / PrivacyCheckupScreen.stepCount,
                            minHeight: 6,
                            color: AppColors.brandOrange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Passo ${_step + 1} di ${PrivacyCheckupScreen.stepCount}',
                        key: const ValueKey<String>('passo_controllo'),
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    children: [
                      Text(_title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        PrivacyCheckupScreen.explanations[_step],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_last)
                        _Summary(controller: widget.controller, onEdit: _go)
                      else
                        PrivacySectionBody(
                          section: PrivacySection.values[_step],
                          controller: widget.controller,
                          profiles: widget.profiles,
                          onPreview: widget.onPreview,
                        ),
                      ListenableBuilder(
                        listenable: widget.controller,
                        builder: (BuildContext context, _) => widget.controller.error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  widget.controller.error!,
                                  style: TextStyle(color: theme.colorScheme.error),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      if (_step > 0)
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey<String>('indietro_controllo'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            onPressed: () => _go(_step - 1),
                            child: const Text('Indietro'),
                          ),
                        ),
                      if (_step > 0) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey<String>('avanti_controllo'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: AppColors.brandOrange,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _last ? widget.onDone : () => _go(_step + 1),
                          child: Text(_last ? 'Fatto' : 'Avanti'),
                        ),
                      ),
                    ],
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

class _Summary extends StatelessWidget {
  const _Summary({required this.controller, required this.onEdit});

  final PrivacyController controller;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            for (final PrivacySection s in PrivacySection.values)
              ListTile(
                key: ValueKey<String>('riepilogo_${s.name}'),
                leading: Icon(s.icon, color: s.color),
                title: Text(s.title),
                subtitle: Text(s.summary(controller)),
                trailing: TextButton(
                  onPressed: () => onEdit(s.index),
                  child: const Text('Modifica'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
