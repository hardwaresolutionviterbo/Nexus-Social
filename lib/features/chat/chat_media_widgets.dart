import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import 'chat_media.dart';
import 'chat_media_picker.dart';
import 'chat_models.dart';
import 'chat_service.dart';

/// Allegato dentro il fumetto: foto, video, vocale o documento.
class MediaContent extends StatefulWidget {
  const MediaContent({super.key, required this.chat, required this.message, required this.mine});

  final ChatService chat;
  final ChatMessage message;
  final bool mine;

  @override
  State<MediaContent> createState() => _MediaContentState();
}

class _MediaContentState extends State<MediaContent> {
  File? _file;
  String _for = '';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(MediaContent old) {
    super.didUpdateWidget(old);
    if (old.message.localFile != widget.message.localFile) _resolve();
  }

  Future<void> _resolve() async {
    final String name = widget.message.localFile;
    if (name == _for && _file != null) return;
    _for = name;
    final File? f = await widget.chat.localFileOf(widget.message);
    if (mounted) setState(() => _file = f);
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<File?> _get() async {
    if (_file != null) return _file;
    try {
      final File f = await widget.chat.download(widget.message);
      if (mounted) setState(() => _file = f);
      return f;
    } on ChatFailure catch (e) {
      if (mounted) _toast(e.message);
      return null;
    }
  }

  Future<void> _open() async {
    final ChatMedia md = widget.message.media!;
    final File? f = await _get();
    if (f == null || !mounted) return;
    switch (md.kind) {
      case MediaKind.image:
        await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => ImageViewerScreen(file: f, caption: widget.message.body),
        ));
      case MediaKind.video:
        await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => VideoViewerScreen(file: f),
        ));
      case MediaKind.file:
        await SharePlus.instance.share(ShareParams(
          files: <XFile>[XFile(f.path, mimeType: md.mime, name: md.name)],
        ));
      case MediaKind.audio:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatMedia md = widget.message.media!;
    final bool busy = widget.chat.isDownloading(widget.message.localId);
    final bool sending = widget.message.serverId == null && widget.message.mine;
    switch (md.kind) {
      case MediaKind.image:
        return _ImageTile(media: md, file: _file, busy: busy || sending && _file == null, onTap: _open);
      case MediaKind.video:
        return _VideoTile(media: md, ready: _file != null, busy: busy, onTap: _open);
      case MediaKind.audio:
        return VoicePlayer(
          key: ValueKey<String>('vocale_${widget.message.localId}'),
          file: _file,
          durationMs: md.durationMs,
          busy: busy,
          mine: widget.mine,
          onDownload: _get,
        );
      case MediaKind.file:
        return _FileTile(media: md, ready: _file != null, busy: busy, onTap: _open);
    }
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 26,
    child: CircularProgressIndicator(strokeWidth: 3, color: color),
  );
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.media, required this.file, required this.busy, required this.onTap});

  final ChatMedia media;
  final File? file;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double ratio = media.width > 0 && media.height > 0
        ? (media.width / media.height).clamp(0.6, 1.8)
        : 1.3;
    final Widget picture;
    if (file != null) {
      picture = Image.file(file!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (media.thumb.isNotEmpty) {
      picture = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Image.memory(base64Decode(media.thumb), fit: BoxFit.cover, gaplessPlayback: true),
      );
    } else {
      picture = const ColoredBox(color: Color(0xFFCFD6E4));
    }
    return GestureDetector(
      key: const ValueKey<String>('allegato_foto'),
      onTap: busy ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 240,
          child: AspectRatio(
            aspectRatio: ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                picture,
                if (file == null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: busy
                          ? const _Spinner()
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 6),
                                Text(formatBytes(media.size),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.media, required this.ready, required this.busy, required this.onTap});

  final ChatMedia media;
  final bool ready;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey<String>('allegato_video'),
    onTap: busy ? null : onTap,
    child: Container(
      width: 240,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1B2333), Color(0xFF34405A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: busy
                ? const _Spinner()
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: Icon(ready ? Icons.play_arrow_rounded : Icons.download_rounded,
                        color: Colors.white, size: 34),
                  ),
          ),
          Positioned(
            left: 10,
            bottom: 8,
            child: Row(
              children: [
                const Icon(Icons.videocam_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text(
                  media.durationMs > 0 ? formatDuration(media.durationMs) : formatBytes(media.size),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.media, required this.ready, required this.busy, required this.onTap});

  final ChatMedia media;
  final bool ready;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String ext = media.extension.toUpperCase();
    return InkWell(
      key: const ValueKey<String>('allegato_documento'),
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(ext.length > 4 ? ext.substring(0, 4) : ext,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.brandBlue)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(media.name.isEmpty ? 'Documento' : media.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  Text(formatBytes(media.size), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (busy)
              const _Spinner(color: AppColors.brandBlue)
            else
              Icon(ready ? Icons.open_in_new_rounded : Icons.download_rounded, color: AppColors.brandBlue),
          ],
        ),
      ),
    );
  }
}

/// Lettore dei messaggi vocali: play/pausa, barra e durata.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({
    super.key,
    required this.file,
    required this.durationMs,
    required this.busy,
    required this.mine,
    required this.onDownload,
  });

  final File? file;
  final int durationMs;
  final bool busy;
  final bool mine;
  final Future<File?> Function() onDownload;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _pos;
  StreamSubscription<PlayerState>? _state;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void dispose() {
    _pos?.cancel();
    _state?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final File? f = widget.file ?? await widget.onDownload();
    if (f == null) return;
    AudioPlayer? p = _player;
    if (p == null) {
      p = _player = AudioPlayer();
      await p.setFilePath(f.path);
      _pos = p.positionStream.listen((Duration d) {
        if (mounted) setState(() => _position = d);
      });
      _state = p.playerStateStream.listen((PlayerState s) {
        if (!mounted) return;
        if (s.processingState == ProcessingState.completed) {
          p!.pause();
          p.seek(Duration.zero);
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        } else {
          setState(() => _playing = s.playing);
        }
      });
    }
    if (_playing) {
      await p.pause();
    } else {
      unawaited(p.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = widget.durationMs;
    final double progress = total <= 0 ? 0 : (_position.inMilliseconds / total).clamp(0.0, 1.0);
    final Color accent = widget.mine ? AppColors.brandOrange : AppColors.brandBlue;
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: widget.busy
                ? Padding(padding: const EdgeInsets.all(9), child: _Spinner(color: accent))
                : IconButton.filled(
                    key: const ValueKey<String>('vocale_play'),
                    style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                    onPressed: _toggle,
                    icon: Icon(widget.file == null
                        ? Icons.download_rounded
                        : (_playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                    tooltip: _playing ? 'Pausa' : 'Ascolta',
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      formatDuration(_playing || _position > Duration.zero ? _position.inMilliseconds : total),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto a tutto schermo, con zoom.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.file, this.caption = ''});

  final File file;
  final String caption;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: Column(
      children: [
        Expanded(
          child: InteractiveViewer(maxScale: 5, child: Center(child: Image.file(file))),
        ),
        if (caption.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(caption, style: const TextStyle(color: Colors.white)),
            ),
          ),
      ],
    ),
  );
}

/// Video a tutto schermo.
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({super.key, required this.file});

  final File file;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _error = 'Questo video non si può riprodurre.');
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
    body: Center(
      child: _error != null
          ? Text(_error!, style: const TextStyle(color: Colors.white))
          : !_ready
          ? const CircularProgressIndicator(color: Colors.white)
          : GestureDetector(
              onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
              child: AspectRatio(
                aspectRatio: _c.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_c),
                    VideoProgressIndicator(_c, allowScrubbing: true),
                    if (!_c.value.isPlaying)
                      const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 64)),
                  ],
                ),
              ),
            ),
    ),
  );
}

/// Anteprima prima di inviare: foto o video con didascalia, documento con nome e peso.
class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({super.key, required this.media, required this.peerName});

  final PickedMedia media;
  final String peerName;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final TextEditingController _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PickedMedia m = widget.media;
    final Widget preview = switch (m.kind) {
      MediaKind.image => InteractiveViewer(child: Image.memory(m.bytes)),
      MediaKind.video => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_rounded, color: Colors.white, size: 72),
          const SizedBox(height: 8),
          Text('${m.name}\n${formatBytes(m.bytes.length)}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ],
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_rounded, color: Colors.white, size: 72),
          const SizedBox(height: 8),
          Text('${m.name}\n${formatBytes(m.bytes.length)}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ],
      ),
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Invia a ${widget.peerName}', style: const TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: preview)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('didascalia'),
                      controller: _caption,
                      maxLength: MediaLimits.maxCaption,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: m.kind == MediaKind.file ? 'Aggiungi un messaggio' : 'Aggiungi una didascalia',
                        hintStyle: const TextStyle(color: Colors.white60),
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey<String>('anteprima_invia'),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.brandOrange,
                      foregroundColor: Colors.white,
                      fixedSize: const Size(52, 52),
                    ),
                    onPressed: () => Navigator.of(context).pop(_caption.text),
                    icon: const Icon(Icons.send_rounded),
                    tooltip: 'Invia',
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
