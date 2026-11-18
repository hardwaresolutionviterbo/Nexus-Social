import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show Widget;

import '../chat/chat_models.dart';
import '../chat/chat_service.dart';

/// Chiamate vocali e videochiamate nelle chat a due (Fase 4, Blocco 8).
///
/// Offerta, risposta e chiusura viaggiano come messaggi cifrati MLS della chat: il server
/// non legge nulla e l'impronta DTLS della chiamata è protetta dalla cifratura della chat.
/// Audio e video vanno da telefono a telefono (DTLS-SRTP), al massimo attraverso il ponte TURN.

enum CallAction { offer, answer, end, reject, busy }

/// Un passaggio della chiamata.
class CallSignal {
  const CallSignal({required this.action, required this.callId, this.video = false, this.sdp = ''});

  final CallAction action;
  final String callId;
  final bool video;

  /// Descrizione della sessione WebRTC (offerta o risposta), con tutti i candidati.
  final String sdp;

  String encode() => jsonEncode(<String, Object>{
    'a': action.name,
    'c': callId,
    if (video) 'v': true,
    if (sdp.isNotEmpty) 's': sdp,
  });

  static CallSignal? decode(String raw) {
    try {
      final Object? j = jsonDecode(raw);
      if (j is! Map) return null;
      final CallAction? a = CallAction.values.where((x) => x.name == j['a']).firstOrNull;
      final Object? id = j['c'];
      final Object? sdp = j['s'];
      if (a == null || id is! String || id.isEmpty || id.length > 64) return null;
      if (sdp != null && (sdp is! String || sdp.length > 20000)) return null;
      if ((a == CallAction.offer || a == CallAction.answer) && (sdp as String?)?.isNotEmpty != true) return null;
      return CallSignal(action: a, callId: id, video: j['v'] == true, sdp: (sdp as String?) ?? '');
    } catch (_) {
      return null;
    }
  }
}

/// Passaggio arrivato da una chat.
class CallEnvelope {
  const CallEnvelope({required this.conversationId, required this.senderId, required this.at, required this.signal});

  final String conversationId;
  final String senderId;
  final DateTime at;
  final CallSignal signal;
}

/// Server da usare per collegarsi (STUN e ponte TURN), dalla funzione `chiamate`.
class IceServer {
  const IceServer({required this.urls, this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, Object> toMap() => <String, Object>{
    'urls': urls,
    'username': ?username,
    'credential': ?credential,
  };
}

abstract class IceProvider {
  Future<List<IceServer>> servers();
}

/// La parte audio/video (WebRTC sul telefono, finta nei test).
abstract class CallMedia {
  /// Prepara microfono (e fotocamera) e il collegamento con i server indicati.
  Future<void> open({required List<IceServer> ice, required bool video});

  /// Offerta completa (con i candidati raccolti).
  Future<String> createOffer();

  /// Risposta completa a un'offerta.
  Future<String> answer(String offer);

  Future<void> acceptAnswer(String answer);

  /// Il collegamento è attivo (true) o caduto (false).
  Stream<bool> get connected;

  Future<void> setMicrophone(bool on);

  Future<void> setCamera(bool on);

  Future<void> switchCamera();

  Future<void> setSpeaker(bool on);

  /// Video dell'altra persona e mio (anteprima); null nelle chiamate vocali.
  Widget? remoteView();

  Widget? localView();

  Future<void> close();
}

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// Suoneria della chiamata in arrivo (quella del telefono; finta nei test).
abstract class CallRinger {
  Future<void> start();

  Future<void> stop();
}

/// Chiamata in corso (una alla volta).
class CallState {
  const CallState({
    required this.phase,
    required this.conversationId,
    required this.callId,
    required this.peerName,
    required this.video,
    this.startedAt,
    this.micOn = true,
    this.cameraOn = true,
    this.speakerOn = false,
    this.endReason = '',
  });

  final CallPhase phase;
  final String conversationId;
  final String callId;
  final String peerName;
  final bool video;
  final DateTime? startedAt;
  final bool micOn;
  final bool cameraOn;
  final bool speakerOn;
  final String endReason;

  CallState copyWith({
    CallPhase? phase,
    DateTime? startedAt,
    bool? micOn,
    bool? cameraOn,
    bool? speakerOn,
    String? endReason,
  }) => CallState(
    phase: phase ?? this.phase,
    conversationId: conversationId,
    callId: callId,
    peerName: peerName,
    video: video,
    startedAt: startedAt ?? this.startedAt,
    micOn: micOn ?? this.micOn,
    cameraOn: cameraOn ?? this.cameraOn,
    speakerOn: speakerOn ?? this.speakerOn,
    endReason: endReason ?? this.endReason,
  );
}

/// «2:31» o «1:02:05».
String callDuration(Duration d) {
  final int h = d.inHours;
  final String m = (d.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class CallService extends ChangeNotifier {
  CallService({
    required this.chat,
    required this.ice,
    required this.media,
    this.ringTimeout = const Duration(seconds: 45),
    this.offerMaxAge = const Duration(seconds: 45),
    this.ringer,
  }) {
    _sub = chat.callSignals.listen(_onSignal);
  }

  final ChatService chat;
  final IceProvider ice;

  /// Crea la parte audio/video per ogni chiamata.
  final CallMedia Function() media;
  final Duration ringTimeout;

  /// Un'offerta più vecchia di così (telefono spento, app chiusa a lungo) è una chiamata persa.
  final Duration offerMaxAge;

  final CallRinger? ringer;
  bool _ringing = false;

  late final StreamSubscription<CallEnvelope> _sub;
  StreamSubscription<bool>? _link;
  CallState? _state;
  CallMedia? _media;
  String _offer = '';
  Timer? _ringTimer;
  bool _disposed = false;

  CallState? get state => _state;
  CallMedia? get currentMedia => _media;

  /// C'è una chiamata da mostrare (anche appena finita, per un istante).
  bool get showing => _state != null && _state!.phase != CallPhase.idle;

  void _set(CallState? s) {
    _state = s;
    final bool ring = s?.phase == CallPhase.incoming;
    if (ring != _ringing) {
      _ringing = ring;
      final CallRinger? r = ringer;
      if (r != null) unawaited((ring ? r.start() : r.stop()).catchError((Object _) {}));
    }
    chat.inCall = s != null && s.phase != CallPhase.ended && s.phase != CallPhase.idle;
    if (!_disposed) notifyListeners();
  }

  static String _newId() {
    final Random r = Random.secure();
    return List<String>.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String _peerName(String conversationId) => chat.conversation(conversationId)?.displayName ?? 'Chiamata';

  /// Chiama nella chat a due [conversationId].
  Future<void> start(String conversationId, {required bool video}) async {
    if (_state != null && _state!.phase != CallPhase.ended) throw const ChatFailure('C\'è già una chiamata in corso.');
    final ChatConversation? c = chat.conversation(conversationId);
    if (c == null || c.isGroup || c.isRequest) throw const ChatFailure('Puoi chiamare solo nelle chat a due già accettate.');
    final String id = _newId();
    _set(CallState(phase: CallPhase.outgoing, conversationId: conversationId, callId: id, peerName: c.displayName, video: video));
    try {
      final CallMedia m = _media = media();
      await m.open(ice: await ice.servers(), video: video);
      _watch(m);
      final String offer = await m.createOffer();
      if (_state?.callId != id) return;
      await chat.sendCallSignal(conversationId, CallSignal(action: CallAction.offer, callId: id, video: video, sdp: offer));
      _ringTimer = Timer(ringTimeout, () => _timeout(id));
    } on ChatFailure catch (e) {
      await _finish(e.message, log: null);
      rethrow;
    } catch (_) {
      await _finish('Chiamata non riuscita', log: null);
      throw const ChatFailure('Chiamata non riuscita. Controlla la connessione e i permessi di microfono e fotocamera.');
    }
  }

  void _timeout(String id) {
    final CallState? s = _state;
    if (s == null || s.callId != id || s.phase != CallPhase.outgoing) return;
    unawaited(chat.sendCallSignal(s.conversationId, CallSignal(action: CallAction.end, callId: id)).catchError((_) {}));
    unawaited(_finish('Nessuna risposta', log: s.video ? 'Videochiamata senza risposta' : 'Chiamata senza risposta'));
  }

  void _watch(CallMedia m) {
    _link?.cancel();
    _link = m.connected.listen((bool up) {
      final CallState? s = _state;
      if (s == null) return;
      if (up && (s.phase == CallPhase.connecting || s.phase == CallPhase.outgoing)) {
        _ringTimer?.cancel();
        _set(s.copyWith(phase: CallPhase.active, startedAt: chat.now()));
      } else if (!up && s.phase == CallPhase.active) {
        unawaited(hangUp(reason: 'Collegamento perso'));
      }
    });
  }

  Future<void> _onSignal(CallEnvelope e) async {
    final CallSignal sig = e.signal;
    final CallState? s = _state;
    switch (sig.action) {
      case CallAction.offer:
        final ChatConversation? c = chat.conversation(e.conversationId);
        final bool old = chat.now().difference(e.at) > offerMaxAge;
        if (c == null || c.isGroup || c.isRequest) return;
        if (old) {
          await chat.logCall(e.conversationId, sig.video ? 'Videochiamata persa' : 'Chiamata persa');
          return;
        }
        if (s != null && s.phase != CallPhase.ended) {
          if (s.callId == sig.callId) return;
          // Occupato: l'altra persona lo sa subito.
          await chat.sendCallSignal(e.conversationId, CallSignal(action: CallAction.busy, callId: sig.callId));
          await chat.logCall(e.conversationId, sig.video ? 'Videochiamata persa' : 'Chiamata persa');
          return;
        }
        _offer = sig.sdp;
        // Le credenziali del ponte si preparano mentre squilla: la risposta parte subito.
        unawaited(ice.servers().then((_) {}, onError: (Object _) {}));
        _set(CallState(
          phase: CallPhase.incoming,
          conversationId: e.conversationId,
          callId: sig.callId,
          peerName: _peerName(e.conversationId),
          video: sig.video,
        ));
        _ringTimer?.cancel();
        _ringTimer = Timer(ringTimeout, () {
          final CallState? now = _state;
          if (now != null && now.callId == sig.callId && now.phase == CallPhase.incoming) {
            unawaited(_finish('Chiamata persa', log: sig.video ? 'Videochiamata persa' : 'Chiamata persa'));
          }
        });
      case CallAction.answer:
        if (s == null || s.callId != sig.callId || s.phase != CallPhase.outgoing) return;
        _ringTimer?.cancel();
        _set(s.copyWith(phase: CallPhase.connecting));
        try {
          await _media?.acceptAnswer(sig.sdp);
        } catch (_) {
          await hangUp(reason: 'Chiamata non riuscita');
        }
      case CallAction.end:
      case CallAction.reject:
      case CallAction.busy:
        if (s == null || s.callId != sig.callId || s.phase == CallPhase.ended) return;
        final String reason = switch (sig.action) {
          CallAction.busy => 'Occupato',
          CallAction.reject => 'Chiamata rifiutata',
          _ => 'Chiamata terminata',
        };
        await _finish(reason, log: _logText(s, missed: s.phase == CallPhase.incoming));
    }
  }

  String _logText(CallState s, {bool missed = false}) {
    final String kind = s.video ? 'Videochiamata' : 'Chiamata vocale';
    final DateTime? from = s.startedAt;
    if (missed) return s.video ? 'Videochiamata persa' : 'Chiamata persa';
    if (from == null) return s.phase == CallPhase.outgoing ? '$kind senza risposta' : '$kind non riuscita';
    return '$kind · ${callDuration(chat.now().difference(from))}';
  }

  /// Rispondi alla chiamata in arrivo.
  Future<void> accept() async {
    final CallState? s = _state;
    if (s == null || s.phase != CallPhase.incoming) return;
    _ringTimer?.cancel();
    _set(s.copyWith(phase: CallPhase.connecting));
    try {
      final CallMedia m = _media = media();
      await m.open(ice: await ice.servers(), video: s.video);
      _watch(m);
      final String answer = await m.answer(_offer);
      await chat.sendCallSignal(s.conversationId, CallSignal(action: CallAction.answer, callId: s.callId, video: s.video, sdp: answer));
    } catch (_) {
      await hangUp(reason: 'Chiamata non riuscita');
    }
  }

  /// Rifiuta la chiamata in arrivo.
  Future<void> reject() async {
    final CallState? s = _state;
    if (s == null || s.phase != CallPhase.incoming) return;
    try {
      await chat.sendCallSignal(s.conversationId, CallSignal(action: CallAction.reject, callId: s.callId));
    } catch (_) {
      // Senza rete: l'altra persona vedrà «nessuna risposta».
    }
    await _finish('Chiamata rifiutata', log: s.video ? 'Videochiamata rifiutata' : 'Chiamata rifiutata');
  }

  /// Chiudi la chiamata (in uscita, in corso o mentre si collega).
  Future<void> hangUp({String reason = 'Chiamata terminata'}) async {
    final CallState? s = _state;
    if (s == null || s.phase == CallPhase.ended || s.phase == CallPhase.idle) return;
    try {
      await chat.sendCallSignal(s.conversationId, CallSignal(action: CallAction.end, callId: s.callId));
    } catch (_) {
      // Senza rete: l'altra persona vedrà il collegamento cadere.
    }
    await _finish(reason, log: _logText(s));
  }

  Future<void> _finish(String reason, {required String? log}) async {
    final CallState? s = _state;
    _ringTimer?.cancel();
    _ringTimer = null;
    await _link?.cancel();
    _link = null;
    final CallMedia? m = _media;
    _media = null;
    _offer = '';
    if (m != null) {
      try {
        await m.close();
      } catch (_) {
        // Già chiusa.
      }
    }
    if (s == null) return;
    if (log != null) await chat.logCall(s.conversationId, log);
    _set(s.copyWith(phase: CallPhase.ended, endReason: reason));
  }

  /// La schermata della chiamata finita si chiude.
  void dismiss() {
    if (_state?.phase == CallPhase.ended) _set(null);
  }

  Future<void> toggleMic() async {
    final CallState? s = _state;
    if (s == null) return;
    await _media?.setMicrophone(!s.micOn);
    _set(s.copyWith(micOn: !s.micOn));
  }

  Future<void> toggleCamera() async {
    final CallState? s = _state;
    if (s == null || !s.video) return;
    await _media?.setCamera(!s.cameraOn);
    _set(s.copyWith(cameraOn: !s.cameraOn));
  }

  Future<void> toggleSpeaker() async {
    final CallState? s = _state;
    if (s == null) return;
    await _media?.setSpeaker(!s.speakerOn);
    _set(s.copyWith(speakerOn: !s.speakerOn));
  }

  Future<void> switchCamera() async => _media?.switchCamera();

  @override
  void dispose() {
    _disposed = true;
    _ringTimer?.cancel();
    unawaited(_sub.cancel());
    unawaited(_link?.cancel());
    unawaited(_media?.close());
    super.dispose();
  }
}
