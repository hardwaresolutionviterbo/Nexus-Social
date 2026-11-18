import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../chat/chat_models.dart' show ChatFailure;
import 'call_service.dart';

/// Schermata della chiamata, a tutto schermo: in arrivo, in uscita, in corso, finita.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.calls});

  final CallService calls;

  /// Si apre sopra a tutto quando c'è una chiamata (la apre la barra dell'app).
  static Future<void> open(BuildContext context, CallService calls) => Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) => CallScreen(calls: calls),
      transitionsBuilder: (_, Animation<double> a, _, Widget child) => FadeTransition(opacity: a, child: child),
    ),
  );

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;
  Timer? _close;
  Timer? _buzz;

  CallService get _c => widget.calls;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _c.state?.phase == CallPhase.active) setState(() {});
    });
    _changed();
  }

  void _changed() {
    final CallState? s = _c.state;
    if (s?.phase == CallPhase.incoming) {
      _buzz ??= Timer.periodic(const Duration(milliseconds: 1200), (_) => HapticFeedback.heavyImpact());
    } else {
      _buzz?.cancel();
      _buzz = null;
    }
    if (s == null || s.phase == CallPhase.idle) {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    if (s.phase == CallPhase.ended && _close == null) {
      _close = Timer(const Duration(milliseconds: 1500), _c.dismiss);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _tick?.cancel();
    _close?.cancel();
    _buzz?.cancel();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on ChatFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _status(CallState s) => switch (s.phase) {
    CallPhase.outgoing => s.video ? 'Videochiamata… squilla' : 'Chiamata… squilla',
    CallPhase.incoming => s.video ? 'Videochiamata in arrivo' : 'Chiamata in arrivo',
    CallPhase.connecting => 'Collegamento…',
    CallPhase.active => s.startedAt == null ? 'In corso' : callDuration(_c.chat.now().difference(s.startedAt!)),
    CallPhase.ended => s.endReason,
    CallPhase.idle => '',
  };

  @override
  Widget build(BuildContext context) {
    final CallState? s = _c.state;
    if (s == null) return const Scaffold(backgroundColor: Color(0xFF101522));
    final Widget? remote = s.video && s.phase == CallPhase.active ? _c.currentMedia?.remoteView() : null;
    final Widget? local = s.video && s.cameraOn ? _c.currentMedia?.localView() : null;
    const TextStyle light = TextStyle(color: Colors.white);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF101522),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (remote != null) Positioned.fill(child: remote),
            SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  // Telefono girato (o schermo basso): tutto più compatto, niente tagli.
                  final bool compact = box.maxHeight < 560;
                  final Widget header = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: compact ? 12 : 40),
                      if (remote == null)
                        CircleAvatar(
                          radius: compact ? 30 : 56,
                          backgroundColor: AppColors.brandOrange,
                          child: Text(
                            s.peerName.isEmpty ? '?' : s.peerName.characters.first.toUpperCase(),
                            style: TextStyle(color: Colors.white, fontSize: compact ? 24 : 44, fontWeight: FontWeight.w700),
                          ),
                        ),
                      SizedBox(height: compact ? 8 : 18),
                      Text(s.peerName, key: const ValueKey<String>('chiamata_nome'),
                          style: light.copyWith(fontSize: compact ? 20 : 26, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(_status(s), key: const ValueKey<String>('chiamata_stato'),
                          style: light.copyWith(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_rounded, size: 13, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text('Cifrata end-to-end', style: light.copyWith(fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ],
                  );
                  final List<Widget> options = <Widget>[
                    _RoundButton(
                      key: const ValueKey<String>('chiamata_microfono'),
                      icon: s.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      color: s.micOn ? Colors.white24 : Colors.white,
                      iconColor: s.micOn ? Colors.white : Colors.black87,
                      label: s.micOn ? 'Microfono' : 'Muto',
                      onTap: () => _guard(_c.toggleMic),
                    ),
                    if (s.video)
                      _RoundButton(
                        key: const ValueKey<String>('chiamata_fotocamera'),
                        icon: s.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        color: s.cameraOn ? Colors.white24 : Colors.white,
                        iconColor: s.cameraOn ? Colors.white : Colors.black87,
                        label: 'Fotocamera',
                        onTap: () => _guard(_c.toggleCamera),
                      ),
                    if (s.video)
                      _RoundButton(
                        key: const ValueKey<String>('chiamata_gira'),
                        icon: Icons.cameraswitch_rounded,
                        color: Colors.white24,
                        label: 'Gira',
                        onTap: () => _guard(_c.switchCamera),
                      )
                    else
                      _RoundButton(
                        key: const ValueKey<String>('chiamata_altoparlante'),
                        icon: Icons.volume_up_rounded,
                        color: s.speakerOn ? Colors.white : Colors.white24,
                        iconColor: s.speakerOn ? Colors.black87 : Colors.white,
                        label: 'Vivavoce',
                        onTap: () => _guard(_c.toggleSpeaker),
                      ),
                  ];
                  final Widget hangUp = _RoundButton(
                    key: const ValueKey<String>('chiamata_chiudi'),
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFE53935),
                    label: 'Chiudi',
                    onTap: () => _guard(_c.hangUp),
                  );
                  Widget controls;
                  if (s.phase == CallPhase.incoming) {
                    controls = Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundButton(
                          key: const ValueKey<String>('chiamata_rifiuta'),
                          icon: Icons.call_end_rounded,
                          color: const Color(0xFFE53935),
                          label: 'Rifiuta',
                          onTap: () => _guard(_c.reject),
                        ),
                        _RoundButton(
                          key: const ValueKey<String>('chiamata_rispondi'),
                          icon: s.video ? Icons.videocam_rounded : Icons.call_rounded,
                          color: const Color(0xFF2E7D32),
                          label: 'Rispondi',
                          onTap: () => _guard(_c.accept),
                        ),
                      ],
                    );
                  } else if (s.phase == CallPhase.ended) {
                    controls = const SizedBox(height: 40);
                  } else if (compact) {
                    controls = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [...options, hangUp]);
                  } else {
                    controls = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: options),
                        const SizedBox(height: 28),
                        hangUp,
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: SingleChildScrollView(child: Center(child: header))),
                      Padding(padding: EdgeInsets.only(bottom: compact ? 12 : 40, top: 8), child: controls),
                    ],
                  );
                },
              ),
            ),
            if (local != null)
              Positioned(
                right: 16,
                top: 56,
                width: 110,
                height: 160,
                child: ClipRRect(borderRadius: BorderRadius.circular(14), child: local),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 68, height: 68, child: Icon(icon, color: iconColor, size: 30)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ],
  );
}
