import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/signal_message.dart';

typedef OnTrackCallback = void Function(MediaStream stream);
typedef OnStateCallback = void Function(RTCPeerConnectionState state);

class DeviceStream {
  final String signalingUrl;
  final String deviceId;
  final OnTrackCallback onTrack;
  final OnStateCallback onState;

  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;
  // ignore: unused_field
  bool _closed = false;

  static const _iceServers = <Map<String, dynamic>>[
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  DeviceStream({
    required this.signalingUrl,
    required this.deviceId,
    required this.onTrack,
    required this.onState,
  });

  Future<void> connect() async {
    _closed = false;
    _ws = WebSocketChannel.connect(Uri.parse(signalingUrl));

    _send(SignalMessage(type: 'join', deviceId: deviceId, from: 'viewer'));

    _ws!.stream.listen(
      (data) {
        try {
          final msg =
              SignalMessage.fromJson(jsonDecode(data as String) as Map<String, dynamic>);
          _handleSignal(msg);
        } catch (_) {}
      },
      onDone: _cleanup,
    );
  }

  void disconnect() {
    _closed = true;
    _cleanup();
  }

  void _send(SignalMessage msg) {
    _ws?.sink.add(jsonEncode(msg.toJson()));
  }

  Future<void> _handleSignal(SignalMessage msg) async {
    switch (msg.type) {
      case 'offer':
        await _handleOffer(msg.payload);
      case 'ice-candidate':
        if (_pc != null && msg.payload != null) {
          final p = msg.payload as Map<String, dynamic>;
          await _pc!.addCandidate(RTCIceCandidate(
            p['candidate'] as String?,
            p['sdpMid'] as String?,
            p['sdpMLineIndex'] as int?,
          ));
        }
      case 'leave':
        onState(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
    }
  }

  Future<void> _handleOffer(dynamic offerPayload) async {
    _pc?.close();
    final offer = offerPayload as Map<String, dynamic>;

    _pc = await createPeerConnection({'iceServers': _iceServers});

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        onTrack(event.streams[0]);
      }
    };

    _pc!.onIceCandidate = (candidate) {
      _send(SignalMessage(
        type: 'ice-candidate',
        deviceId: deviceId,
        from: 'viewer',
        payload: candidate.toMap(),
      ));
    };

    _pc!.onConnectionState = (state) {
      onState(state);
    };

    await _pc!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    _send(SignalMessage(
      type: 'answer',
      deviceId: deviceId,
      from: 'viewer',
      payload: {'sdp': answer.sdp, 'type': answer.type},
    ));
  }

  void _cleanup() {
    _pc?.close();
    _pc = null;
    _ws?.sink.close();
    _ws = null;
  }
}
