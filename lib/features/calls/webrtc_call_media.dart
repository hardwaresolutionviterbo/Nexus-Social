import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:audio_session/audio_session.dart'
    show AndroidAudioAttributes, AndroidAudioContentType, AndroidAudioUsage;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer, AudioSource, LoopMode;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, FunctionResponse, SupabaseClient;

import '../../core/services/push_notifications.dart';
import '../chat/chat_models.dart' show ChatFailure;
import 'call_service.dart';

/// Suoneria scelta nel telefono per la chiamata in arrivo. Suona sul canale «suoneria»:
/// con il telefono in silenzioso o vibrazione resta muta, come le chiamate normali.
class SystemCallRinger implements CallRinger {
  AudioPlayer? _player;

  @override
  Future<void> start(String conversationId) async {
    // Se la chiamata era già a tutto schermo (app aperta dalla notifica), suona una volta sola.
    await PushNotifications.cancelIncomingCall(conversationId);
    final AudioPlayer p = _player ??= AudioPlayer(handleAudioSessionActivation: false);
    await p.setAndroidAudioAttributes(const AndroidAudioAttributes(
      usage: AndroidAudioUsage.notificationRingtone,
      contentType: AndroidAudioContentType.sonification,
    ));
    await p.setAudioSource(AudioSource.uri(Uri.parse('content://settings/system/ringtone')));
    await p.setLoopMode(LoopMode.one);
    unawaited(p.play());
  }

  @override
  Future<void> stop(String conversationId) async {
    await _player?.stop();
    await PushNotifications.cancelIncomingCall(conversationId);
  }
}

/// Credenziali del ponte dalla funzione `chiamate` (token di Firebase, come per `rubrica`).
class SupabaseIceProvider implements IceProvider {
  SupabaseIceProvider(this._client);

  final SupabaseClient _client;

  static const List<IceServer> stunOnly = <IceServer>[
    IceServer(urls: <String>['stun:stun.cloudflare.com:3478']),
  ];

  /// Credenziali già pronte (valgono un'ora): si riusano per 50 minuti, così la chiamata parte
  /// subito invece di aspettare la funzione.
  List<IceServer>? _cached;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<IceServer>> servers() async {
    final List<IceServer>? cached = _cached;
    if (cached != null && DateTime.now().difference(_cachedAt) < const Duration(minutes: 50)) return cached;
    final List<IceServer> fresh = await _fetch();
    if (fresh.length > 1) {
      _cached = fresh;
      _cachedAt = DateTime.now();
    }
    return fresh;
  }

  Future<List<IceServer>> _fetch() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ChatFailure('Accesso richiesto.');
    final String token = await user.getIdToken() ?? '';
    try {
      final FunctionResponse res = await _client.functions
          .invoke('chiamate', headers: <String, String>{'Authorization': 'Bearer $token'}, body: <String, Object>{})
          .timeout(const Duration(seconds: 15));
      final Object? data = res.data;
      final Object? list = data is Map ? data['iceServers'] : null;
      if (list is! List) return stunOnly;
      final List<IceServer> out = <IceServer>[
        for (final Object? s in list)
          if (s is Map && s['urls'] != null)
            IceServer(
              urls: <String>[for (final Object? u in (s['urls'] is List ? s['urls'] as List : <Object?>[s['urls']])) '$u'],
              username: s['username'] as String?,
              credential: s['credential'] as String?,
            ),
      ];
      return out.isEmpty ? stunOnly : out;
    } on FunctionException catch (e) {
      if (e.status == 429) throw const ChatFailure('Hai fatto troppe chiamate oggi. Riprova domani.');
      return stunOnly;
    } on TimeoutException {
      return stunOnly;
    }
  }
}

/// Audio e video con WebRTC (flutter_webrtc). Le offerte e le risposte si mandano complete,
/// con tutti i candidati, così bastano due messaggi cifrati per collegarsi.
class WebRtcCallMedia implements CallMedia {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  final RTCVideoRenderer _localView = RTCVideoRenderer();
  final RTCVideoRenderer _remoteView = RTCVideoRenderer();
  final StreamController<bool> _connected = StreamController<bool>.broadcast();
  bool _video = false;
  bool _renderers = false;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> open({required List<IceServer> ice, required bool video}) async {
    _video = video;
    if (video) {
      await _localView.initialize();
      await _remoteView.initialize();
      _renderers = true;
    }
    final MediaStream local;
    try {
      local = _local = await navigator.mediaDevices.getUserMedia(<String, Object>{
        'audio': true,
        'video': video
            ? <String, Object>{
                'mandatory': <String, String>{'minWidth': '640', 'minHeight': '480', 'minFrameRate': '24'},
                'facingMode': 'user',
                'optional': <Object>[],
              }
            : false,
      });
    } catch (e) {
      throw ChatFailure(video
          ? 'Piazly non può usare fotocamera e microfono. Consentili in Impostazioni → App → Piazly → Autorizzazioni.'
          : 'Piazly non può usare il microfono. Consentilo in Impostazioni → App → Piazly → Autorizzazioni.');
    }
    if (video) _localView.srcObject = local;
    final RTCPeerConnection pc = _pc = await createPeerConnection(<String, Object>{
      'iceServers': <Map<String, Object>>[for (final IceServer s in ice) s.toMap()],
      'sdpSemantics': 'unified-plan',
    });
    for (final MediaStreamTrack t in local.getTracks()) {
      await pc.addTrack(t, local);
    }
    pc.onTrack = (RTCTrackEvent e) {
      if (_video && e.streams.isNotEmpty) _remoteView.srcObject = e.streams.first;
    };
    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (_connected.isClosed) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) _connected.add(true);
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _connected.add(false);
      }
    };
    pc.onIceConnectionState = (RTCIceConnectionState s) {
      if (_connected.isClosed) return;
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connected.add(true);
      }
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) _connected.add(false);
    };
    await Helper.setSpeakerphoneOn(video);
  }

  /// Aspetta i candidati e dà la descrizione completa. Non serve aspettarli tutti: appena c'è
  /// un candidato del ponte (relay) basta un attimo in più; al massimo 2,5 secondi.
  Future<String> _complete() async {
    final RTCPeerConnection pc = _pc!;
    final Completer<void> done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    pc.onIceGatheringState = (RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) finish();
    };
    pc.onIceCandidate = (RTCIceCandidate c) {
      if ((c.candidate ?? '').contains(' typ relay')) Timer(const Duration(milliseconds: 300), finish);
    };
    if (pc.iceGatheringState != RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await done.future.timeout(const Duration(milliseconds: 2500), onTimeout: () {});
    }
    return (await pc.getLocalDescription())!.sdp!;
  }

  @override
  Future<String> createOffer() async {
    final RTCPeerConnection pc = _pc!;
    final RTCSessionDescription offer = await pc.createOffer(<String, Object>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _video,
    });
    await pc.setLocalDescription(offer);
    return _complete();
  }

  @override
  Future<String> answer(String offer) async {
    final RTCPeerConnection pc = _pc!;
    await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
    final RTCSessionDescription answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return _complete();
  }

  @override
  Future<void> acceptAnswer(String answer) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
  }

  @override
  Future<void> setMicrophone(bool on) async {
    for (final MediaStreamTrack t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  Future<void> setCamera(bool on) async {
    for (final MediaStreamTrack t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  Future<void> switchCamera() async {
    final List<MediaStreamTrack> v = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (v.isNotEmpty) await Helper.switchCamera(v.first);
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Widget? remoteView() => _video ? RTCVideoView(_remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover) : null;

  @override
  Widget? localView() => _video
      ? RTCVideoView(_localView, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
      : null;

  @override
  Future<void> close() async {
    for (final MediaStreamTrack t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    await _pc?.close();
    _pc = null;
    if (_renderers) {
      _localView.srcObject = null;
      _remoteView.srcObject = null;
      await _localView.dispose();
      await _remoteView.dispose();
      _renderers = false;
    }
    if (!_connected.isClosed) await _connected.close();
  }
}

/// Chiamata di gruppo con WebRTC: un collegamento per ogni altra persona (fino a 3), con lo
/// stesso microfono e la stessa fotocamera.
class WebRtcGroupCallMedia implements GroupCallMedia {
  List<IceServer> _ice = const <IceServer>[];
  bool _video = false;
  MediaStream? _local;
  final RTCVideoRenderer _localView = RTCVideoRenderer();
  final Map<String, RTCPeerConnection> _pcs = <String, RTCPeerConnection>{};
  final Map<String, RTCVideoRenderer> _views = <String, RTCVideoRenderer>{};
  final StreamController<(String, bool)> _connected = StreamController<(String, bool)>.broadcast();

  @override
  Stream<(String, bool)> get connected => _connected.stream;

  @override
  Future<void> open({required List<IceServer> ice, required bool video}) async {
    _ice = ice;
    _video = video;
    try {
      _local = await navigator.mediaDevices.getUserMedia(<String, Object>{
        'audio': true,
        'video': video
            ? <String, Object>{
                'mandatory': <String, String>{'minWidth': '480', 'minHeight': '360', 'minFrameRate': '20'},
                'facingMode': 'user',
                'optional': <Object>[],
              }
            : false,
      });
    } catch (_) {
      throw ChatFailure(video
          ? 'Piazly non può usare fotocamera e microfono. Consentili in Impostazioni → App → Piazly → Autorizzazioni.'
          : 'Piazly non può usare il microfono. Consentilo in Impostazioni → App → Piazly → Autorizzazioni.');
    }
    if (video) {
      await _localView.initialize();
      _localView.srcObject = _local;
    }
    await Helper.setSpeakerphoneOn(true);
  }

  Future<RTCPeerConnection> _pc(String peer) async {
    final RTCPeerConnection? have = _pcs[peer];
    if (have != null) return have;
    final RTCPeerConnection pc = await createPeerConnection(<String, Object>{
      'iceServers': <Map<String, Object>>[for (final IceServer s in _ice) s.toMap()],
      'sdpSemantics': 'unified-plan',
    });
    _pcs[peer] = pc;
    final MediaStream local = _local!;
    for (final MediaStreamTrack t in local.getTracks()) {
      await pc.addTrack(t, local);
    }
    if (_video) {
      final RTCVideoRenderer view = RTCVideoRenderer();
      await view.initialize();
      _views[peer] = view;
      pc.onTrack = (RTCTrackEvent e) {
        if (e.streams.isNotEmpty) view.srcObject = e.streams.first;
      };
    }
    pc.onIceConnectionState = (RTCIceConnectionState s) {
      if (_connected.isClosed) return;
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _connected.add((peer, true));
      }
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) _connected.add((peer, false));
    };
    return pc;
  }

  Future<String> _complete(RTCPeerConnection pc) async {
    final Completer<void> done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    pc.onIceGatheringState = (RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) finish();
    };
    pc.onIceCandidate = (RTCIceCandidate c) {
      if ((c.candidate ?? '').contains(' typ relay')) Timer(const Duration(milliseconds: 300), finish);
    };
    if (pc.iceGatheringState != RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await done.future.timeout(const Duration(milliseconds: 2500), onTimeout: () {});
    }
    return (await pc.getLocalDescription())!.sdp!;
  }

  @override
  Future<String> offerTo(String peer) async {
    final RTCPeerConnection pc = await _pc(peer);
    final RTCSessionDescription offer = await pc.createOffer(<String, Object>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _video,
    });
    await pc.setLocalDescription(offer);
    return _complete(pc);
  }

  @override
  Future<String> answerFrom(String peer, String offer) async {
    final RTCPeerConnection pc = await _pc(peer);
    await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
    final RTCSessionDescription answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return _complete(pc);
  }

  @override
  Future<void> acceptAnswer(String peer, String answer) async {
    await _pcs[peer]?.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
  }

  @override
  Future<void> drop(String peer) async {
    final RTCPeerConnection? pc = _pcs.remove(peer);
    await pc?.close();
    final RTCVideoRenderer? view = _views.remove(peer);
    if (view != null) {
      view.srcObject = null;
      await view.dispose();
    }
  }

  @override
  Future<void> setMicrophone(bool on) async {
    for (final MediaStreamTrack t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  Future<void> setCamera(bool on) async {
    for (final MediaStreamTrack t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  Future<void> switchCamera() async {
    final List<MediaStreamTrack> v = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (v.isNotEmpty) await Helper.switchCamera(v.first);
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Widget? remoteView(String peer) {
    final RTCVideoRenderer? view = _views[peer];
    return view == null ? null : RTCVideoView(view, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }

  @override
  Widget? localView() => _video
      ? RTCVideoView(_localView, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
      : null;

  @override
  Future<void> close() async {
    for (final String peer in _pcs.keys.toList()) {
      await drop(peer);
    }
    for (final MediaStreamTrack t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    if (_video) {
      _localView.srcObject = null;
      await _localView.dispose();
    }
    if (!_connected.isClosed) await _connected.close();
  }
}
