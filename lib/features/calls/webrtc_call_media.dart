import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, FunctionResponse, SupabaseClient;

import '../chat/chat_models.dart' show ChatFailure;
import 'call_service.dart';

/// Credenziali del ponte dalla funzione `chiamate` (token di Firebase, come per `rubrica`).
class SupabaseIceProvider implements IceProvider {
  SupabaseIceProvider(this._client);

  final SupabaseClient _client;

  static const List<IceServer> stunOnly = <IceServer>[
    IceServer(urls: <String>['stun:stun.cloudflare.com:3478']),
  ];

  @override
  Future<List<IceServer>> servers() async {
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
    final MediaStream local = _local = await navigator.mediaDevices.getUserMedia(<String, Object>{
      'audio': true,
      'video': video ? <String, Object>{'facingMode': 'user', 'width': 640, 'height': 480} : false,
    });
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

  /// Aspetta che i candidati siano raccolti (al massimo 5 secondi) e dà la descrizione completa.
  Future<String> _complete() async {
    final RTCPeerConnection pc = _pc!;
    final Completer<void> done = Completer<void>();
    pc.onIceGatheringState = (RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) done.complete();
    };
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return (await pc.getLocalDescription())!.sdp!;
    await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
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
