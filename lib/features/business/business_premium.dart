import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/piazly_ui.dart';
import 'business_models.dart';
import 'business_repository.dart';

/// Pagina Premium (Fase 6): cosa si ottiene, prova gratuita di 7 giorni e stato dell'abbonamento.
/// Il pagamento con Google Play si collegherà quando l'app sarà pubblicata.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key, required this.repository, required this.me, this.now = DateTime.now});

  final BusinessRepository repository;

  /// null: chi guarda non ha ancora registrato un'attività.
  final MyBusiness? me;
  final DateTime Function() now;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  late BusinessSubscription _sub = widget.me?.subscription ?? const BusinessSubscription();
  bool _busy = false;
  String? _error;

  static const List<(IconData, String, String)> _benefits = <(IconData, String, String)>[
    (Icons.verified_rounded, 'Badge «Verificato»', 'Con la verifica di Piazly, accanto al nome e sulla Mappa.'),
    (Icons.campaign_rounded, 'Promozioni sulla Mappa', 'Fino a 5 al giorno, ognuna visibile fino a 7 giorni.'),
    (Icons.qr_code_2_rounded, 'Coupon con QR', 'I clienti li mostrano in cassa: vedi quanti sono arrivati.'),
    (Icons.notifications_active_rounded, 'Avvisi a chi passa vicino', 'Solo a chi ha scelto di riceverli.'),
    (Icons.event_rounded, 'Eventi anche fuori sede', 'Con un luogo diverso: la sede resta ferma.'),
  ];

  Future<void> _trial() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final BusinessSubscription s = await widget.repository.startTrial();
      if (!mounted) return;
      setState(() => _sub = s);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prova gratuita attiva per 7 giorni. Nessun pagamento richiesto.')),
      );
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = widget.now();
    final MyBusiness? me = widget.me;
    final bool active = _sub.isActive(now);
    return Scaffold(
      appBar: AppBar(title: const Text('Piazly Premium')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: PiazlyColors.violetGradient, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 10),
                Text('Fatti trovare da chi è vicino',
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  '${BusinessSubscription.price} al mese · i primi ${BusinessSubscription.trialDays} giorni sono gratis',
                  key: const ValueKey<String>('premium_prezzo'),
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          if (me != null)
            SoftCard(
              key: ValueKey<String>(active ? 'premium_attivo' : 'premium_non_attivo'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(
                    active ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: active ? PiazlyColors.green : const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active
                              ? (_sub.isTrial ? 'Prova gratuita attiva' : 'Premium attivo')
                              : (_sub.periodEnd == null ? 'Premium non attivo' : 'Premium scaduto'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          active
                              ? 'Fino al ${shortDate(_sub.periodEnd!)} (${_sub.daysLeft(now) == 1 ? 'manca 1 giorno' : 'mancano ${_sub.daysLeft(now)} giorni'}). '
                                    'Non si rinnova da solo.'
                              : _sub.periodEnd == null
                              ? 'Prova tutto gratis per 7 giorni.'
                              : 'Scaduto il ${shortDate(_sub.periodEnd!)}: il badge e le promozioni non si vedono più.',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (active && me.status != VerificationStatus.verified) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Il badge «Verificato» comparirà quando un amministratore avrà approvato i dati.',
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cosa ottieni', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final (IconData, String, String) b in _benefits)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(b.$1, color: PiazlyColors.violet),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(b.$3, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, key: const ValueKey<String>('premium_errore'),
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (me == null)
                  Text(
                    'Prima registra la tua attività da «La mia attività».',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  )
                else if (!active && !_sub.trialUsed)
                  FilledButton.icon(
                    key: const ValueKey<String>('premium_prova'),
                    onPressed: _busy ? null : () => unawaited(_trial()),
                    icon: const Icon(Icons.card_giftcard_rounded),
                    label: Text(_busy ? 'Attivazione…' : 'Prova gratis per 7 giorni'),
                  ),
                if (me != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('premium_abbonati'),
                    onPressed: null,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text(
                      'Abbonati · ${BusinessSubscription.price}/mese',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Il pagamento con Google Play sarà disponibile quando Piazly sarà pubblicata sul Play Store. '
                    'Fino ad allora l\'abbonamento può essere attivato dagli amministratori di Piazly.',
                    key: const ValueKey<String>('premium_pagamento_in_arrivo'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}
