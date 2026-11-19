import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/piazly_ui.dart';
import '../chat/chat_media_picker.dart';
import '../chat/chat_models.dart';
import '../profile/avatar_view.dart';
import '../profile/profile_repository.dart';
import 'status_service.dart';

/// Quando è stato pubblicato: «Adesso», «12 minuti fa», «Oggi, 18:40», «Ieri, 21:05».
String statusTimeLabel(DateTime at, DateTime now) {
  final DateTime l = at.toLocal();
  final Duration ago = now.difference(l);
  if (ago.inMinutes < 1) return 'Adesso';
  if (ago.inMinutes < 60) return ago.inMinutes == 1 ? '1 minuto fa' : '${ago.inMinutes} minuti fa';
  final String hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  final bool today = l.year == now.year && l.month == now.month && l.day == now.day;
  return today ? 'Oggi, $hm' : 'Ieri, $hm';
}

/// Foto e video per gli stati. Nei test: una versione finta.
abstract class StatusPicker {
  Future<Uint8List?> pickImage({required bool camera});

  Future<Uint8List?> pickVideo();
}

class RealStatusPicker implements StatusPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<Uint8List?> pickImage({required bool camera}) async {
    final PickedMedia? m = await RealChatDevice().pickImage(camera: camera);
    return m?.bytes;
  }

  @override
  Future<Uint8List?> pickVideo() async {
    final XFile? x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: StatusService.maxVideo);
    if (x == null) return null;
    final int size = await x.length();
    if (size > StatusService.maxBytes) {
      throw const ChatFailure('Video troppo pesante: per gli stati al massimo 16 MB (circa 30 secondi).');
    }
    final VideoPlayerController c = VideoPlayerController.file(File(x.path));
    try {
      await c.initialize();
      if (c.value.duration > StatusService.maxVideo + const Duration(seconds: 1)) {
        throw const ChatFailure('Video troppo lungo: per gli stati al massimo 30 secondi.');
      }
    } on ChatFailure {
      rethrow;
    } catch (_) {
      throw const ChatFailure('Questo video non si può usare.');
    } finally {
      await c.dispose();
    }
    return x.readAsBytes();
  }
}

/// Bordo attorno alla foto: colorato se ci sono stati nuovi, grigio se già visti.
class StatusRing extends StatelessWidget {
  const StatusRing({super.key, required this.child, required this.seen});

  final Widget child;
  final bool seen;

  @override
  Widget build(BuildContext context) {
    final Color color = seen ? Theme.of(context).colorScheme.outlineVariant : AppColors.brandOrange;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2.5)),
      child: child,
    );
  }
}

/// Sezione «Stati» della chat: il mio stato, quelli nuovi dei contatti e quelli già visti.
class StatusList extends StatefulWidget {
  const StatusList({
    super.key,
    required this.service,
    required this.contacts,
    this.profiles,
    this.picker,
  });

  final StatusService service;

  /// Le persone in rubrica, per «Tranne…» e «Solo con…».
  final Future<List<ChatContact>> Function() contacts;
  final ProfileRepository? profiles;
  final StatusPicker? picker;

  @override
  State<StatusList> createState() => _StatusListState();
}

class _StatusListState extends State<StatusList> {
  StatusService get service => widget.service;

  @override
  void initState() {
    super.initState();
    unawaited(service.load());
  }

  void _show(String message) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));

  Future<void> _text() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StatusTextComposer(service: service, contacts: widget.contacts),
    ),
  );

  Future<void> _media() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey<String>('stato_scatta'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scatta una foto'),
              onTap: () => Navigator.of(c).pop('camera'),
            ),
            ListTile(
              key: const ValueKey<String>('stato_galleria'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Foto dalla galleria'),
              onTap: () => Navigator.of(c).pop('galleria'),
            ),
            ListTile(
              key: const ValueKey<String>('stato_video'),
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video dalla galleria'),
              subtitle: const Text('Fino a 30 secondi'),
              onTap: () => Navigator.of(c).pop('video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final StatusPicker picker = widget.picker ?? RealStatusPicker();
    try {
      final Uint8List? bytes = choice == 'video'
          ? await picker.pickVideo()
          : await picker.pickImage(camera: choice == 'camera');
      if (bytes == null || !mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => StatusMediaComposer(
            service: service,
            contacts: widget.contacts,
            kind: choice == 'video' ? StatusKind.video : StatusKind.photo,
            bytes: bytes,
          ),
        ),
      );
    } on ChatFailure catch (e) {
      _show(e.message);
    } catch (_) {
      _show('Non è stato possibile aprire la foto o il video.');
    }
  }

  Future<void> _open(List<StatusGroup> groups, int index) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => StatusViewerScreen(service: service, groups: groups, start: index, profiles: widget.profiles),
    ),
  );

  Future<void> _privacy() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => StatusAudienceScreen(service: service, contacts: widget.contacts)),
  );

  Widget _groupTile(StatusGroup g, List<StatusGroup> list, int i) => ListTile(
    key: ValueKey<String>('stato_di_${g.userId}'),
    leading: StatusRing(
      seen: g.allSeen,
      child: AvatarView(name: g.name, repository: widget.profiles, path: g.avatarPath, size: 44),
    ),
    title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(statusTimeLabel(g.latest, service.now)),
    onTap: () => _open(list, i),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: service,
      builder: (BuildContext context, _) {
        final StatusGroup? mine = service.myGroup;
        final List<StatusGroup> recent = service.recent;
        final List<StatusGroup> viewed = service.viewed;
        return RefreshIndicator(
          onRefresh: service.load,
          child: ListView(
            padding: AppSpacing.pagePadding.copyWith(left: 0, right: 0),
            children: [
              SoftCard(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: Row(
                  children: [
                    InkWell(
                      key: const ValueKey<String>('il_mio_stato'),
                      customBorder: const CircleBorder(),
                      onTap: mine == null ? _media : () => _open(<StatusGroup>[mine], 0),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          StatusRing(
                            seen: mine == null,
                            child: AvatarView(name: 'Io', repository: widget.profiles, path: mine?.avatarPath, size: 48),
                          ),
                          if (mine == null)
                            const Positioned(
                              right: -2,
                              bottom: -2,
                              child: CircleAvatar(
                                radius: 11,
                                backgroundColor: AppColors.brandOrange,
                                child: Icon(Icons.add_rounded, size: 17, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: mine == null ? _media : () => _open(<StatusGroup>[mine], 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Il mio stato', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              mine == null
                                  ? 'Crea un aggiornamento con testo, foto o video'
                                  : '${mine.items.length == 1 ? '1 aggiornamento' : '${mine.items.length} aggiornamenti'}'
                                      ' · ${statusTimeLabel(mine.latest, service.now)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _SquareAction(
                      key: const ValueKey<String>('stato_testo'),
                      icon: Icons.edit_outlined,
                      tooltip: 'Scrivi uno stato',
                      onTap: _text,
                    ),
                    const SizedBox(width: 8),
                    _SquareAction(
                      key: const ValueKey<String>('stato_foto'),
                      icon: Icons.photo_camera_outlined,
                      tooltip: 'Foto o video',
                      onTap: _media,
                    ),
                  ],
                ),
              ),
              SoftCard(
                key: const ValueKey<String>('stati_privacy'),
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                onTap: _privacy,
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: PiazlyColors.violet, size: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chi vede i miei stati', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text(_audienceLabel(service), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.brandOrange),
                  ],
                ),
              ),
              if (service.error != null && !service.loaded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Text(service.error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              if (recent.isNotEmpty) const _Header('Aggiornamenti recenti'),
              for (int i = 0; i < recent.length; i++) _groupTile(recent[i], recent, i),
              if (viewed.isNotEmpty) const _Header('Già visti'),
              for (int i = 0; i < viewed.length; i++) _groupTile(viewed[i], viewed, i),
              if (service.loaded && recent.isEmpty && viewed.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    children: [
                      const PiazlyEmptyArt(),
                      const SizedBox(height: 14),
                      Text(
                        'Nessun aggiornamento dai tuoi contatti',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Quando qualcuno che hai in rubrica pubblica uno stato, lo vedi qui.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: PiazlyColors.violetDeep),
                      ),
                    ],
                  ),
                ),
              SoftCard(
                tint: PiazlyColors.violetSoft,
                margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: PiazlyColors.violet),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gli stati spariscono dopo 24 ore.',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            'Li vede solo chi scegli tu, ma non sono cifrati end-to-end come i messaggi delle chat.',
                            key: const ValueKey<String>('stati_avviso'),
                            style: theme.textTheme.bodySmall,
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
      },
    );
  }
}

String _audienceLabel(StatusService s) => switch (s.audience) {
  StatusAudience.contacts => 'I miei contatti',
  StatusAudience.except =>
    s.people.isEmpty ? 'I miei contatti' : 'I miei contatti tranne ${s.people.length}',
  StatusAudience.only => s.people.length == 1 ? 'Solo 1 persona' : 'Solo ${s.people.length} persone',
};

/// Quadratino arancio chiaro con l'icona (matita, fotocamera).
class _SquareAction extends StatelessWidget {
  const _SquareAction({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: PiazlyColors.orangeSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox.square(dimension: 46, child: Icon(icon, color: AppColors.brandOrange)),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// «Chi vede i miei stati»: tutti i contatti, tutti tranne alcuni, solo alcuni.
class StatusAudienceScreen extends StatefulWidget {
  const StatusAudienceScreen({super.key, required this.service, required this.contacts});

  final StatusService service;
  final Future<List<ChatContact>> Function() contacts;

  @override
  State<StatusAudienceScreen> createState() => _StatusAudienceScreenState();
}

class _StatusAudienceScreenState extends State<StatusAudienceScreen> {
  late StatusAudience _audience = widget.service.audience;
  late final Set<String> _except = <String>{
    if (widget.service.audience == StatusAudience.except) ...widget.service.people,
  };
  late final Set<String> _only = <String>{
    if (widget.service.audience == StatusAudience.only) ...widget.service.people,
  };
  List<ChatContact>? _list;

  @override
  void initState() {
    super.initState();
    widget.contacts().then((List<ChatContact> l) {
      if (mounted) setState(() => _list = l);
    }).catchError((Object _) {
      if (mounted) setState(() => _list = const <ChatContact>[]);
    });
  }

  Set<String> get _chosen => _audience == StatusAudience.except ? _except : _only;

  Future<void> _done() async {
    if (_audience == StatusAudience.only && _only.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scegli almeno una persona.')),
      );
      return;
    }
    await widget.service.setAudience(_audience, _chosen.toList()..sort());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ChatContact>? list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Chi vede i miei stati')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Text(
              'Vale per i prossimi stati che pubblichi. Li vede solo chi hai nella rubrica del '
              'telefono e usa Piazly, mai chi hai bloccato.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          RadioGroup<StatusAudience>(
            groupValue: _audience,
            onChanged: (StatusAudience? v) => setState(() => _audience = v ?? _audience),
            child: Column(
              children: [
                for (final StatusAudience a in StatusAudience.values)
                  RadioListTile<StatusAudience>(
                    key: ValueKey<String>('pubblico_${a.wire}'),
                    value: a,
                    title: Text(a.label),
                    subtitle: a == StatusAudience.contacts
                        ? null
                        : Text(a == StatusAudience.except
                            ? _except.length == 1 ? '1 escluso' : '${_except.length} esclusi'
                            : _only.length == 1 ? '1 persona scelta' : '${_only.length} persone scelte'),
                  ),
              ],
            ),
          ),
          if (_audience != StatusAudience.contacts) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: Text(
                _audience == StatusAudience.except ? 'Chi non deve vedere i tuoi stati' : 'Chi può vedere i tuoi stati',
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (list == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('Nessun contatto della rubrica usa ancora Piazly.'),
              )
            else
              for (final ChatContact c in list)
                CheckboxListTile(
                  key: ValueKey<String>('persona_${c.id}'),
                  value: _chosen.contains(c.id),
                  onChanged: (bool? v) => setState(() {
                    if (v == true) {
                      _chosen.add(c.id);
                    } else {
                      _chosen.remove(c.id);
                    }
                  }),
                  title: Text(c.name),
                  subtitle: Text('@${c.username}'),
                ),
          ],
          const SizedBox(height: 96),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey<String>('pubblico_fatto'),
        onPressed: _done,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Fatto'),
      ),
    );
  }
}

/// Pulsante con la scelta del pubblico, sotto gli editor.
class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.service, required this.contacts});

  final StatusService service;
  final Future<List<ChatContact>> Function() contacts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (BuildContext context, _) => ActionChip(
      key: const ValueKey<String>('stato_pubblico'),
      avatar: const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white),
      label: Text(_audienceLabel(service), style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.black26,
      side: BorderSide.none,
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => StatusAudienceScreen(service: service, contacts: contacts)),
      ),
    ),
  );
}

/// Stato di solo testo, su sfondo colorato.
class StatusTextComposer extends StatefulWidget {
  const StatusTextComposer({super.key, required this.service, required this.contacts});

  final StatusService service;
  final Future<List<ChatContact>> Function() contacts;

  @override
  State<StatusTextComposer> createState() => _StatusTextComposerState();
}

class _StatusTextComposerState extends State<StatusTextComposer> {
  final TextEditingController _text = TextEditingController();
  int _color = 0;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.service.postText(_text.text, _color);
      if (mounted) Navigator.of(context).pop();
    } on ChatFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = Color(statusColors[_color]);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            key: const ValueKey<String>('stato_colore'),
            tooltip: 'Cambia colore',
            onPressed: () => setState(() => _color = (_color + 1) % statusColors.length),
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    key: const ValueKey<String>('stato_scrivi'),
                    controller: _text,
                    autofocus: true,
                    maxLength: StatusService.maxText,
                    minLines: 1,
                    maxLines: 10,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Scrivi uno stato',
                      hintStyle: TextStyle(color: Colors.white60, fontSize: 30),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _AudienceChip(service: widget.service, contacts: widget.contacts),
                    ),
                  ),
                  IconButton.filled(
                    key: const ValueKey<String>('stato_pubblica'),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.brandOrange,
                      foregroundColor: Colors.white,
                      fixedSize: const Size(56, 56),
                    ),
                    tooltip: 'Pubblica',
                    onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Foto o video con didascalia, prima di pubblicare.
class StatusMediaComposer extends StatefulWidget {
  const StatusMediaComposer({
    super.key,
    required this.service,
    required this.contacts,
    required this.kind,
    required this.bytes,
  });

  final StatusService service;
  final Future<List<ChatContact>> Function() contacts;
  final StatusKind kind;
  final Uint8List bytes;

  @override
  State<StatusMediaComposer> createState() => _StatusMediaComposerState();
}

class _StatusMediaComposerState extends State<StatusMediaComposer> {
  final TextEditingController _caption = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.service.postMedia(kind: widget.kind, bytes: widget.bytes, caption: _caption.text);
      if (mounted) Navigator.of(context).pop();
    } on ChatFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Nuovo stato')),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.kind == StatusKind.photo
                  ? Image.memory(widget.bytes, fit: BoxFit.contain)
                  : _MemoryVideo(bytes: widget.bytes, autoplay: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              key: const ValueKey<String>('stato_didascalia'),
              controller: _caption,
              maxLength: StatusService.maxText,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Aggiungi una didascalia',
                hintStyle: const TextStyle(color: Colors.white60),
                counterText: '',
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _AudienceChip(service: widget.service, contacts: widget.contacts),
                  ),
                ),
                IconButton.filled(
                  key: const ValueKey<String>('stato_pubblica'),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.brandOrange,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(56, 56),
                  ),
                  tooltip: 'Pubblica',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Video da memoria: si scrive in un file temporaneo e si riproduce.
class _MemoryVideo extends StatefulWidget {
  const _MemoryVideo({super.key, required this.bytes, this.autoplay = false, this.onReady, this.paused = false});

  final Uint8List bytes;
  final bool autoplay;
  final bool paused;
  final void Function(Duration length)? onReady;

  @override
  State<_MemoryVideo> createState() => _MemoryVideoState();
}

class _MemoryVideoState extends State<_MemoryVideo> {
  VideoPlayerController? _c;
  File? _file;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final Directory tmp = await getTemporaryDirectory();
      final File f = File('${tmp.path}/stato_${identityHashCode(widget.bytes)}.mp4');
      await f.writeAsBytes(widget.bytes, flush: true);
      _file = f;
      final VideoPlayerController c = VideoPlayerController.file(f);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      widget.onReady?.call(c.value.duration);
      if (widget.autoplay) await c.play();
    } catch (_) {
      if (mounted) setState(() => _error = 'Questo video non si può riprodurre.');
    }
  }

  @override
  void didUpdateWidget(_MemoryVideo old) {
    super.didUpdateWidget(old);
    final VideoPlayerController? c = _c;
    if (c == null || old.paused == widget.paused) return;
    if (widget.paused) {
      unawaited(c.pause());
    } else {
      unawaited(c.play());
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    final File? f = _file;
    if (f != null) unawaited(f.delete().then((_) {}, onError: (Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _c;
    if (_error != null) return Text(_error!, style: const TextStyle(color: Colors.white));
    if (c == null) return const CircularProgressIndicator(color: Colors.white);
    return AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
  }
}

/// Stati a tutto schermo, con le barre in alto: tocca a destra per andare avanti, a sinistra per
/// tornare indietro, tieni premuto per fermare.
class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.service,
    required this.groups,
    required this.start,
    this.profiles,
    this.itemDuration = const Duration(seconds: 5),
    this.frozenAt,
  });

  final StatusService service;
  final List<StatusGroup> groups;
  final int start;
  final ProfileRepository? profiles;
  final Duration itemDuration;

  /// Solo per le anteprime delle schermate: barra ferma a questo punto (0–1).
  final double? frozenAt;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.itemDuration)
    ..addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) _next();
    });
  late int _group = widget.start;
  late int _item = widget.groups[widget.start].firstUnseen;
  bool _paused = false;
  bool _closing = false;
  Uint8List? _bytes;
  String? _error;
  int _loadToken = 0;

  StatusGroup get group => widget.groups[_group];
  StatusItem get item => group.items[_item];

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _show() {
    final StatusItem s = item;
    // Dopo il disegno: la lista sotto si aggiorna («Già visti»).
    unawaited(Future<void>.microtask(() => widget.service.markSeen(s)));
    _progress
      ..stop()
      ..duration = widget.itemDuration
      ..value = widget.frozenAt ?? 0;
    _bytes = null;
    _error = null;
    final int token = ++_loadToken;
    if (s.kind == StatusKind.text) {
      _run();
      return;
    }
    widget.service.media(s).then((Uint8List b) {
      if (!mounted || token != _loadToken) return;
      setState(() => _bytes = b);
      if (s.kind == StatusKind.photo) _run();
    }).catchError((Object e) {
      if (!mounted || token != _loadToken) return;
      setState(() => _error = e is ChatFailure ? e.message : 'Questo stato non si può aprire.');
      _run();
    });
  }

  /// Fa scorrere la barra (non nelle anteprime con la barra ferma).
  void _run() {
    if (widget.frozenAt == null && !_paused) unawaited(_progress.forward());
  }

  void _videoReady(Duration length) {
    if (!mounted) return;
    final Duration d = length > Duration.zero && length <= StatusService.maxVideo + const Duration(seconds: 1)
        ? length
        : StatusService.maxVideo;
    _progress.duration = d;
    _run();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _progress.stop();
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_item < group.items.length - 1) {
      setState(() => _item++);
      _show();
    } else if (_group < widget.groups.length - 1) {
      setState(() {
        _group++;
        _item = group.firstUnseen;
      });
      _show();
    } else {
      _close();
    }
  }

  void _previous() {
    if (_item > 0) {
      setState(() => _item--);
    } else if (_group > 0) {
      setState(() {
        _group--;
        _item = 0;
      });
    } else {
      _progress.value = 0;
      _run();
      return;
    }
    _show();
  }

  void _pause(bool paused) {
    setState(() => _paused = paused);
    if (paused) {
      _progress.stop();
    } else if (item.kind == StatusKind.text || _bytes != null || _error != null) {
      _run();
    }
  }

  Future<void> _viewers() async {
    _pause(true);
    final StatusItem s = item;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext c) => FutureBuilder<List<StatusViewer>>(
        future: widget.service.viewers(s),
        builder: (BuildContext c, AsyncSnapshot<List<StatusViewer>> snap) {
          final List<StatusViewer>? list = snap.data;
          return SafeArea(
            child: SizedBox(
              height: 360,
              child: snap.hasError
                  ? const Center(child: Text('Non è stato possibile caricare chi l\'ha visto.'))
                  : list == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      key: const ValueKey<String>('stato_visualizzazioni'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                          child: Text(
                            list.isEmpty
                                ? 'Non l\'ha ancora visto nessuno'
                                : list.length == 1 ? 'Visto da 1 persona' : 'Visto da ${list.length} persone',
                            style: Theme.of(c).textTheme.titleMedium,
                          ),
                        ),
                        for (final StatusViewer v in list)
                          ListTile(
                            leading: AvatarView(name: v.name, repository: widget.profiles, path: v.avatarPath, size: 40),
                            title: Text(v.name),
                            subtitle: Text(statusTimeLabel(v.seenAt, widget.service.now)),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
    if (mounted) _pause(false);
  }

  Future<void> _delete() async {
    _pause(true);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Eliminare questo stato?'),
        content: const Text('Sparirà per tutti quelli che potevano vederlo.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annulla')),
          FilledButton(
            key: const ValueKey<String>('stato_elimina_conferma'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      if (mounted) _pause(false);
      return;
    }
    try {
      await widget.service.delete(item);
      if (mounted) _close();
    } on ChatFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      _pause(false);
    }
  }

  Widget _content(StatusItem s) {
    if (s.kind == StatusKind.text) {
      return Container(
        color: Color(statusColors[s.color.clamp(0, statusColors.length - 1)]),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Text(
          s.body,
          key: const ValueKey<String>('stato_testo_mostrato'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
        ),
      );
    }
    final Uint8List? b = _bytes;
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.white)));
    }
    if (b == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
    return Center(
      child: s.kind == StatusKind.photo
          ? Image.memory(b, fit: BoxFit.contain)
          : _MemoryVideo(key: ValueKey<String>(s.id), bytes: b, autoplay: true, paused: _paused, onReady: _videoReady),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StatusItem s = item;
    final bool mine = s.mine;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (TapUpDetails d) {
          final double w = MediaQuery.sizeOf(context).width;
          d.localPosition.dx < w / 3 ? _previous() : _next();
        },
        onLongPressStart: (_) => _pause(true),
        onLongPressEnd: (_) => _pause(false),
        onVerticalDragEnd: (DragEndDetails d) {
          if ((d.primaryVelocity ?? 0) > 300) _close();
        },
        child: Stack(
          children: [
            Positioned.fill(child: _content(s)),
            if (s.kind != StatusKind.text && s.body.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: mine ? 88 : 32,
                child: Container(
                  color: Colors.black45,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Text(
                    s.body,
                    key: const ValueKey<String>('stato_didascalia_mostrata'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (BuildContext c, _) => Row(
                        children: [
                          for (int i = 0; i < group.items.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    minHeight: 3,
                                    value: i < _item ? 1 : i == _item ? _progress.value : 0,
                                    backgroundColor: Colors.white38,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey<String>('stato_chiudi'),
                        color: Colors.white,
                        tooltip: 'Chiudi',
                        onPressed: _close,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      AvatarView(
                        name: mine ? 'Io' : group.name,
                        repository: widget.profiles,
                        path: group.avatarPath,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mine ? 'Il mio stato' : group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              statusTimeLabel(s.createdAt, widget.service.now),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (mine)
                        IconButton(
                          key: const ValueKey<String>('stato_elimina'),
                          color: Colors.white,
                          tooltip: 'Elimina',
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (mine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: TextButton.icon(
                      key: const ValueKey<String>('stato_visto_da'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: _viewers,
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(s.views == 1 ? 'Visto da 1' : 'Visto da ${s.views}'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
