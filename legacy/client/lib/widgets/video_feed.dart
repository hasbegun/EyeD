import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/api_config_provider.dart';
import '../services/device_stream.dart';
import '../theme/eyed_theme.dart';

class VideoFeed extends ConsumerStatefulWidget {
  final String deviceId;

  const VideoFeed({super.key, required this.deviceId});

  @override
  ConsumerState<VideoFeed> createState() => _VideoFeedState();
}

class _VideoFeedState extends ConsumerState<VideoFeed> {
  final _renderer = RTCVideoRenderer();
  DeviceStream? _stream;
  String _connState = 'waiting';

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) => _connect());
  }

  @override
  void didUpdateWidget(covariant VideoFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _disconnect();
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnect();
    _renderer.dispose();
    super.dispose();
  }

  void _connect() {
    final config = ref.read(apiConfigProvider);
    final url = config.wsSignalingUrl(widget.deviceId);

    _stream = DeviceStream(
      signalingUrl: url,
      deviceId: widget.deviceId,
      onTrack: (stream) {
        if (mounted) {
          setState(() => _renderer.srcObject = stream);
        }
      },
      onState: (state) {
        if (mounted) {
          setState(() {
            _connState = switch (state) {
              RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
                'connected',
              RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
                'connecting',
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
                'disconnected',
              RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
                'disconnected',
              _ => 'waiting',
            };
          });
        }
      },
    );
    _stream!.connect();
  }

  void _disconnect() {
    _stream?.disconnect();
    _stream = null;
    _renderer.srcObject = null;
  }

  String _badgeText(AppLocalizations l10n) => switch (_connState) {
        'connected' => l10n.videoLive,
        'connecting' => l10n.videoConnecting,
        'waiting' => l10n.videoWaiting,
        _ => l10n.videoOffline,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<EyedSemanticColors>()!;

    final badgeColor = switch (_connState) {
      'connected' => semantic.success,
      'connecting' => semantic.warning,
      _ => cs.onSurfaceVariant,
    };

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (_connState == 'connected')
              RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
            else
              Center(
                child: Text(
                  l10n.waitingForVideo,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeColor),
                ),
                child: Text(
                  _badgeText(l10n),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
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
