import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';
import '../models/analyze_result.dart';

class ResultsSocket {
  final String url;
  final _resultController = StreamController<AnalyzeResult>.broadcast();
  final _statusController = StreamController<bool>.broadcast();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _closed = false;
  int _reconnectMs = wsReconnectBaseMs;

  ResultsSocket({required this.url});

  Stream<AnalyzeResult> get results => _resultController.stream;
  Stream<bool> get connectionStatus => _statusController.stream;

  void connect() {
    _closed = false;
    _tryConnect();
  }

  void disconnect() {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
    _statusController.add(false);
  }

  Future<void> _tryConnect() async {
    if (_closed) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));

      // Wait for the WebSocket handshake to actually complete.
      await channel.ready;

      if (_closed) {
        channel.sink.close();
        return;
      }

      _channel = channel;
      _statusController.add(true);
      _reconnectMs = wsReconnectBaseMs;

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _resultController.add(AnalyzeResult.fromJson(json));
          } catch (_) {
            // Ignore malformed messages
          }
        },
        onDone: () {
          _statusController.add(false);
          _scheduleReconnect();
        },
        onError: (_) {
          _statusController.add(false);
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _statusController.add(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectMs), () {
      _reconnectTimer = null;
      _tryConnect();
    });
    _reconnectMs =
        (_reconnectMs * wsReconnectFactor).clamp(0, wsReconnectMaxMs);
  }

  void dispose() {
    disconnect();
    _resultController.close();
    _statusController.close();
  }
}
