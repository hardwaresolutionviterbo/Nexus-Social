import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/piazly_ui.dart';
import 'business_models.dart';
import 'business_repository.dart';

const Color _star = Color(0xFFF59E0B);

/// Stelle da 1 a 5 (sola lettura).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 18});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (int i = 1; i <= 5; i++)
        Icon(
          rating >= i
              ? Icons.star_rounded
              : rating >= i - 0.5
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          size: size,
          color: _star,
        ),
    ],
  );
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Sezione «Recensioni verificate» della scheda attività.
class BusinessReviewsSection extends StatefulWidget {
  const BusinessReviewsSection({super.key, required this.repository, required this.businessId, this.isAdmin = false});

  final BusinessRepository repository;
  final String businessId;
  final bool isAdmin;

  @override
  State<BusinessReviewsSection> createState() => _BusinessReviewsSectionState();
}

class _BusinessReviewsSectionState extends State<BusinessReviewsSection> {
  BusinessReviews? _r;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final BusinessReviews r = await widget.repository.reviews(widget.businessId);
      if (mounted) setState(() => _r = r);
    } on BusinessFailure {
      if (mounted) setState(() => _r = const BusinessReviews());
    }
  }

  Future<void> _write() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReviewFormScreen(
          repository: widget.repository,
          businessId: widget.businessId,
          initial: _r?.mine,
        ),
      ),
    );
    if (ok ?? false) await _load();
  }

  Future<void> _reply(BusinessReview r) async {
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _ReplyDialog(initial: r.reply),
    );
    if (text == null) return;
    try {
      await widget.repository.replyReview(r.id, text);
      await _load();
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
    }
  }

  Future<void> _adminDelete(BusinessReview r) async {
    try {
      await widget.repository.adminDeleteReview(r.id);
      await _load();
    } on BusinessFailure catch (f) {
      if (mounted) _toast(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BusinessReviews? r = _r;
    if (r == null) return const SizedBox.shrink();
    return SoftCard(
      key: const ValueKey<String>('attivita_recensioni'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Recensioni verificate', style: theme.textTheme.titleMedium)),
              if (r.count > 0 && r.average != null) ...[
                StarRow(rating: r.average!),
                const SizedBox(width: 6),
                Text(
                  '${r.average!.toStringAsFixed(1).replaceAll('.', ',')} (${r.count})',
                  key: const ValueKey<String>('recensioni_media'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Le scrive solo chi ha usato un coupon di questa attività in cassa.',
            style: theme.textTheme.bodySmall,
          ),
          if (r.count == 0)
            const Padding(padding: EdgeInsets.only(top: 10), child: Text('Ancora nessuna recensione.')),
          for (final BusinessReview item in r.items)
            Padding(
              key: ValueKey<String>('recensione_${item.id}'),
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StarRow(rating: item.rating.toDouble(), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item.author}${item.mine ? ' (tu)' : ''} · ${_date(item.createdAt)}',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isAdmin && !item.mine)
                        IconButton(
                          key: ValueKey<String>('recensione_togli_${item.id}'),
                          tooltip: 'Togli (amministratori)',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _adminDelete(item),
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        ),
                    ],
                  ),
                  if (item.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.body)),
                  if (item.reply.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6, left: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: PiazlyColors.violetSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Risposta dell\'attività: ${item.reply}', style: theme.textTheme.bodySmall),
                    ),
                  if (r.ownerView)
                    TextButton(
                      key: ValueKey<String>('recensione_rispondi_${item.id}'),
                      onPressed: () => _reply(item),
                      child: Text(item.reply.isEmpty ? 'Rispondi' : 'Modifica la risposta'),
                    ),
                ],
              ),
            ),
          if (r.canReview)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton.icon(
                key: const ValueKey<String>('recensione_scrivi'),
                onPressed: _write,
                icon: const Icon(Icons.rate_review_rounded),
                label: Text(r.mine == null ? 'Scrivi una recensione' : 'Modifica la tua recensione'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Risposta del titolare (il campo vive quanto la finestra, anche durante la chiusura).
class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog({required this.initial});

  final String initial;

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rispondi alla recensione'),
    content: TextField(
      key: const ValueKey<String>('recensione_risposta_testo'),
      controller: _c,
      maxLength: 300,
      minLines: 2,
      maxLines: 4,
      decoration: const InputDecoration(hintText: 'Grazie per…'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
      FilledButton(
        key: const ValueKey<String>('recensione_risposta_invia'),
        onPressed: () => Navigator.of(context).pop(_c.text),
        child: const Text('Pubblica'),
      ),
    ],
  );
}

class ReviewFormScreen extends StatefulWidget {
  const ReviewFormScreen({super.key, required this.repository, required this.businessId, this.initial});

  final BusinessRepository repository;
  final String businessId;
  final BusinessReview? initial;

  @override
  State<ReviewFormScreen> createState() => _ReviewFormScreenState();
}

class _ReviewFormScreenState extends State<ReviewFormScreen> {
  late int _rating = widget.initial?.rating ?? 0;
  late final TextEditingController _body = TextEditingController(text: widget.initial?.body ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating < 1) {
      setState(() => _error = 'Scegli da 1 a 5 stelle.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveReview(widget.businessId, rating: _rating, body: _body.text);
      if (mounted) Navigator.of(context).pop(true);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    try {
      await widget.repository.deleteMyReview(widget.businessId);
      if (mounted) Navigator.of(context).pop(true);
    } on BusinessFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('La tua recensione')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey<String>('stella_$i'),
                  iconSize: 40,
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(_rating >= i ? Icons.star_rounded : Icons.star_outline_rounded, color: _star),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey<String>('recensione_testo'),
            controller: _body,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Racconta com\'è andata (facoltativo)'),
          ),
          Text(
            'In pubblico compare il tuo nome pubblico. Puoi correggerla o cancellarla quando vuoi.',
            style: theme.textTheme.bodySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const ValueKey<String>('recensione_errore'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey<String>('recensione_pubblica'),
            onPressed: _busy ? null : () => unawaited(_save()),
            child: Text(_busy ? 'Invio…' : 'Pubblica'),
          ),
          if (widget.initial != null)
            TextButton(
              key: const ValueKey<String>('recensione_cancella'),
              onPressed: () => unawaited(_delete()),
              child: const Text('Cancella la recensione'),
            ),
        ],
      ),
    );
  }
}
