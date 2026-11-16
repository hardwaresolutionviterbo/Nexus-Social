import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../map/listing_repository.dart' show ListingFailure;
import 'market_models.dart';
import 'market_publish_screen.dart' show MarketPhoto;
import 'market_repository.dart';

/// Proposta o controproposta di scambio (Blocco 3): da 1 a 5 annunci di chi chiede
/// l'oggetto, un eventuale conguaglio con la direzione, un messaggio.
/// Restituisce true se la proposta è stata inviata.
class SwapOfferScreen extends StatefulWidget {
  const SwapOfferScreen({
    super.key,
    required this.repository,
    required this.targetTitle,
    required this.cashAllowed,
    this.targetListingId,
    this.counterOf,
  }) : assert((targetListingId == null) != (counterOf == null));

  final MarketRepository repository;
  final String targetTitle;

  /// L'annuncio accetta un conguaglio.
  final bool cashAllowed;

  /// Nuova proposta per questo annuncio…
  final String? targetListingId;

  /// …oppure controproposta a questa proposta.
  final SwapProposal? counterOf;

  @override
  State<SwapOfferScreen> createState() => _SwapOfferScreenState();
}

class _SwapOfferScreenState extends State<SwapOfferScreen> {
  List<SwapItem>? _candidates;
  final Set<String> _chosen = <String>{};
  bool _cash = false;
  CashDirection _direction = CashDirection.requesterPays;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _message = TextEditingController();
  bool _busy = false;
  String? _error;

  SwapProposal? get _counter => widget.counterOf;

  /// Chi scrive è chi chiede l'annuncio (nella proposta lo è sempre).
  bool get _iAmRequester => _counter == null || !_counter!.iAmOwner;

  @override
  void initState() {
    super.initState();
    final SwapProposal? c = _counter;
    if (c != null) {
      _chosen.addAll(c.items.where((SwapItem i) => i.available).map((SwapItem i) => i.id));
      if (c.cashCents != null && widget.cashAllowed) {
        _cash = true;
        _amount.text = '${c.cashCents! ~/ 100}';
        _direction = c.direction ?? CashDirection.requesterPays;
      }
    }
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<SwapItem> items = await widget.repository.swapCandidates(proposalId: _counter?.id);
      if (!mounted) return;
      setState(() {
        _candidates = items;
        _chosen.retainAll(items.map((SwapItem i) => i.id));
      });
    } on ListingFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  void _toggle(String id, bool on) {
    setState(() {
      _error = null;
      if (!on) {
        _chosen.remove(id);
      } else if (_chosen.length >= SwapRules.maxItems) {
        _error = 'Al massimo ${SwapRules.maxItems} annunci per proposta.';
      } else {
        _chosen.add(id);
      }
    });
  }

  Future<void> _send() async {
    if (_chosen.isEmpty) {
      setState(() => _error = _iAmRequester
          ? 'Scegli almeno un tuo annuncio da offrire.'
          : 'Scegli almeno un annuncio dell\'altra persona.');
      return;
    }
    int? cents;
    if (_cash) {
      try {
        cents = MarketRules.parsePriceCents(_amount.text);
      } on FormatException {
        cents = null;
      }
      if (cents == null || cents < SwapRules.minCashCents || cents > SwapRules.maxCashCents) {
        setState(() => _error = 'Conguaglio da 1 a 999.999 €.');
        return;
      }
    }
    final SwapOffer offer = SwapOffer(
      itemIds: _chosen.toList(),
      cashCents: cents,
      direction: cents == null ? null : _direction,
      message: _message.text,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final SwapProposal? c = _counter;
      if (c == null) {
        await widget.repository.proposeSwap(widget.targetListingId!, offer);
      } else {
        await widget.repository.counterSwap(c.id, offer);
      }
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
    final List<SwapItem>? items = _candidates;
    final bool counter = _counter != null;
    final String other = _counter?.otherPublicName ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(counter ? 'Controproposta' : 'Proponi uno scambio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Per «${widget.targetTitle}»', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Text(
            _iAmRequester
                ? 'Cosa offri (da 1 a ${SwapRules.maxItems} tuoi annunci)'
                : 'Cosa chiedi a $other (da 1 a ${SwapRules.maxItems} suoi annunci)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items == null && _error == null)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (items != null && items.isEmpty)
            Text(
              _iAmRequester
                  ? 'Non hai annunci attivi da offrire. Pubblicane uno in Scambia o in Vendita, '
                      'poi torna qui.'
                  : 'L\'altra persona non ha più annunci attivi.',
              key: const ValueKey<String>('offerta_nessun_annuncio'),
              style: theme.textTheme.bodyMedium,
            )
          else if (items != null)
            for (final SwapItem i in items)
              CheckboxListTile(
                key: ValueKey<String>('offerta_${i.id}'),
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(i.id),
                onChanged: (bool? v) => _toggle(i.id, v ?? false),
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: i.photo == null
                        ? const ColoredBox(color: Color(0x14000000))
                        : MarketPhoto(path: i.photo!, repository: widget.repository),
                  ),
                ),
                title: Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: i.priceCents == null ? Text(i.type.label) : Text(MarketRules.formatPrice(i.priceCents!)),
              ),
          if (widget.cashAllowed) ...[
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              key: const ValueKey<String>('offerta_conguaglio'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Aggiungi un conguaglio in denaro'),
              subtitle: const Text('Accordi e pagamento tra voi: l\'app non gestisce i soldi'),
              value: _cash,
              onChanged: (bool v) => setState(() => _cash = v),
            ),
            if (_cash) ...[
              TextField(
                key: const ValueKey<String>('offerta_importo'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Importo (€)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<CashDirection>(
                key: const ValueKey<String>('offerta_direzione'),
                segments: [
                  ButtonSegment<CashDirection>(
                    value: _iAmRequester ? CashDirection.requesterPays : CashDirection.ownerPays,
                    label: const Text('Lo aggiungo io'),
                  ),
                  ButtonSegment<CashDirection>(
                    value: _iAmRequester ? CashDirection.ownerPays : CashDirection.requesterPays,
                    label: const Text('Lo chiedo io'),
                  ),
                ],
                selected: <CashDirection>{_direction},
                onSelectionChanged: (Set<CashDirection> v) => setState(() => _direction = v.first),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey<String>('offerta_messaggio'),
            controller: _message,
            maxLength: SwapRules.messageMax,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Messaggio (facoltativo)'),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey<String>('offerta_errore'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: FilledButton(
          key: const ValueKey<String>('offerta_invia'),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Invio…' : (counter ? 'Invia controproposta' : 'Invia proposta')),
        ),
      ),
    );
  }
}
