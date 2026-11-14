import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'profile_repository.dart';

/// Foto profilo rotonda con anello arancio. Senza foto mostra l'iniziale del nome.
class AvatarView extends StatefulWidget {
  const AvatarView({
    super.key,
    required this.name,
    this.repository,
    this.path,
    this.bytes,
    this.size = 72,
  });

  final String name;
  final ProfileRepository? repository;

  /// Percorso nel bucket privato (scaricato con il proprio accesso).
  final String? path;

  /// Immagine già in memoria (appena scelta, non ancora salvata).
  final Uint8List? bytes;
  final double size;

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  Future<Uint8List?>? _download;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AvatarView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.repository != widget.repository) _load();
  }

  void _load() {
    final String? path = widget.path;
    _download = (path == null || widget.repository == null)
        ? null
        : widget.repository!.downloadAvatar(path);
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;
    final String initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim().substring(0, 1).toUpperCase();
    Widget fallback() => Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.brandGradient,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: s * 0.42,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    Widget image(Uint8List data) => ClipOval(
      child: Image.memory(data, width: s, height: s, fit: BoxFit.cover, gaplessPlayback: true),
    );

    final Widget inner;
    if (widget.bytes != null) {
      inner = image(widget.bytes!);
    } else if (_download != null) {
      inner = FutureBuilder<Uint8List?>(
        future: _download,
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) =>
            snap.data == null ? fallback() : image(snap.data!),
      );
    } else {
      inner = fallback();
    }
    return Semantics(
      label: 'Foto profilo',
      image: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.orangeGradient,
          boxShadow: [
            BoxShadow(color: AppColors.brandOrange.withValues(alpha: 0.4), blurRadius: 16),
          ],
        ),
        child: inner,
      ),
    );
  }
}
