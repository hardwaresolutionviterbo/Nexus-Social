import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// Avviso di sicurezza della Mappa (M3): al primo accesso e sempre dall'icona dello scudo.
class SafetyNoticeCard extends StatelessWidget {
  const SafetyNoticeCard({super.key, required this.onAcknowledge});

  final VoidCallback onAcknowledge;

  static const List<(IconData, String)> tips = <(IconData, String)>[
    (Icons.groups_2_outlined, 'Incontra le persone conosciute qui in luoghi pubblici e frequentati.'),
    (Icons.share_location_outlined, 'Prima di vederti con qualcuno, avvisa una persona di fiducia: dove vai, con chi e a che ora.'),
    (Icons.lock_outline, 'Non condividere indirizzo di casa, documenti, codici o dati bancari.'),
    (Icons.blur_on_rounded, 'La tua posizione esatta non è mai mostrata: gli annunci compaiono in una zona approssimata.'),
    (Icons.flag_outlined, 'Se qualcosa non ti convince, interrompi, blocca e segnala la persona.'),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Material(
        key: const ValueKey<String>('avviso_sicurezza'),
        color: scheme.surface,
        borderRadius: BorderRadius.circular(26),
        elevation: 8,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.health_and_safety_rounded, color: scheme.primary, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Sicurezza sulla mappa', style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final (IconData icon, String text) in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onAcknowledge, child: const Text('Ho capito')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
