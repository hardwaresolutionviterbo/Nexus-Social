import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/widgets/piazly_ui.dart';
import 'ai_service.dart';

/// Avviso onesto, mostrato in cima alla chat e nelle Immagini IA.
const String aiNotice =
    'Piazly AI è un assistente automatico (Cloudflare Workers AI). Quello che scrivi qui va ai '
    'server per avere la risposta: non è cifrato come le chat. Non scrivere dati personali. '
    'Può sbagliare: controlla le cose importanti.';

/// Icona di Piazly AI (cerchio viola con la stellina).
class AiAvatar extends StatelessWidget {
  const AiAvatar({super.key, this.radius = 26});

  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2,
    height: radius * 2,
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: PiazlyColors.violetGradient),
    child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: radius),
  );
}

/// Riga fissata in cima all'elenco delle chat, come Meta AI su WhatsApp.
class AiChatTile extends StatelessWidget {
  const AiChatTile({super.key, required this.ai, required this.onTap});

  final AiService ai;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ai,
      builder: (BuildContext context, _) {
        final AiTurn? last = ai.last;
        return ListTile(
          key: const ValueKey<String>('chat_piazly_ai'),
          onTap: onTap,
          leading: const AiAvatar(),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Piazly AI', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(Icons.push_pin_rounded, size: 15, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          subtitle: Text(
            last == null ? 'Chiedimi qualcosa o crea un\'immagine' : last.text.replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

/// La chat con Piazly AI.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, required this.ai});

  final AiService ai;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();

  static const List<String> _ideas = <String>[
    'Scrivimi un annuncio per vendere una bici',
    'Come funziona la posizione in tempo reale?',
    'Idee per una serata con amici',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(widget.ai.load());
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask([String? preset]) async {
    final String q = preset ?? _text.text;
    if (q.trim().isEmpty) return;
    _text.clear();
    try {
      await widget.ai.ask(q);
    } on AiFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(f.message)));
      }
    }
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'immagine':
        await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute<Uint8List>(builder: (_) => AiImageScreen(ai: widget.ai, sendLabel: null)),
        );
      case 'svuota':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Svuotare la chat con Piazly AI?'),
            content: const Text('I messaggi si cancellano da questo telefono.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
              TextButton(
                key: const ValueKey<String>('ai_svuota_conferma'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Svuota'),
              ),
            ],
          ),
        );
        if (ok ?? false) await widget.ai.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(
          children: [
            AiAvatar(radius: 18),
            SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Piazly AI', maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    'Assistente automatico',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey<String>('ai_menu'),
            onSelected: (String v) => unawaited(_menu(v)),
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'immagine', child: Text('Crea un\'immagine')),
              PopupMenuItem<String>(value: 'svuota', child: Text('Svuota la chat')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.ai,
        builder: (BuildContext context, _) {
          final List<AiTurn> turns = widget.ai.turns;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  children: [
                    if (widget.ai.thinking)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          key: ValueKey<String>('ai_pensa'),
                          padding: EdgeInsets.all(10),
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                        ),
                      ),
                    for (final AiTurn t in turns.reversed) _AiBubble(turn: t),
                    if (turns.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (int i = 0; i < _ideas.length; i++)
                              ActionChip(
                                key: ValueKey<String>('ai_idea_$i'),
                                label: Text(_ideas[i]),
                                onPressed: () => unawaited(_ask(_ideas[i])),
                              ),
                          ],
                        ),
                      ),
                    SoftCard(
                      key: const ValueKey<String>('ai_avviso'),
                      margin: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                      tint: PiazlyColors.violetSoft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: PiazlyColors.violet),
                          const SizedBox(width: 10),
                          Expanded(child: Text(aiNotice, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey<String>('ai_campo'),
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: AiService.maxQuestion,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Chiedi a Piazly AI',
                            counterText: '',
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const ValueKey<String>('ai_invia'),
                        tooltip: 'Invia',
                        onPressed: _text.text.trim().isEmpty || widget.ai.thinking ? null : () => unawaited(_ask()),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  const _AiBubble({required this.turn});

  final AiTurn turn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool mine = turn.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: mine ? PiazlyColors.violet : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: SelectableText(
          turn.text,
          style: theme.textTheme.bodyLarge?.copyWith(color: mine ? Colors.white : null),
        ),
      ),
    );
  }
}

/// «Immagini IA»: descrivi, crea, guarda l'anteprima; [sendLabel] la manda nella chat.
class AiImageScreen extends StatefulWidget {
  const AiImageScreen({super.key, required this.ai, this.sendLabel = 'Invia nella chat'});

  final AiService ai;

  /// Testo del pulsante che restituisce l'immagine (null: solo anteprima).
  final String? sendLabel;

  @override
  State<AiImageScreen> createState() => _AiImageScreenState();
}

class _AiImageScreenState extends State<AiImageScreen> {
  final TextEditingController _prompt = TextEditingController();
  Uint8List? _image;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uint8List img = await widget.ai.image(_prompt.text);
      if (mounted) setState(() => _image = img);
    } on AiFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Uint8List? img = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('Immagini IA')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            key: const ValueKey<String>('ia_descrizione'),
            controller: _prompt,
            minLines: 2,
            maxLines: 4,
            maxLength: 400,
            decoration: const InputDecoration(
              labelText: 'Descrivi l\'immagine',
              hintText: 'Per esempio «un gatto arancione su una piazza italiana al tramonto»',
            ),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('ia_crea'),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(_busy ? 'Sto creando…' : (img == null ? 'Crea' : 'Crea di nuovo')),
          ),
          const SizedBox(height: 8),
          Text('Al massimo 5 immagini al giorno. $aiNotice', style: theme.textTheme.bodySmall),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, key: const ValueKey<String>('ia_errore'), style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (img != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(img, key: const ValueKey<String>('ia_anteprima'), fit: BoxFit.cover, gaplessPlayback: true),
            ),
            if (widget.sendLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey<String>('ia_invia'),
                onPressed: () => Navigator.of(context).pop(img),
                icon: const Icon(Icons.send_rounded),
                label: Text(widget.sendLabel!),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
