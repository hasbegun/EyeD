class ApiConfig {
  final String gatewayBaseUrl;
  final String engineBaseUrl;

  const ApiConfig({
    this.gatewayBaseUrl = 'http://127.0.0.1:9504',
    this.engineBaseUrl = 'http://127.0.0.1:9500',
  });

  String get wsResultsUrl {
    final uri = Uri.parse(gatewayBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.host}:${uri.port}/ws/results';
  }

  String wsSignalingUrl(String deviceId) {
    final uri = Uri.parse(gatewayBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.host}:${uri.port}/ws/signaling?device_id=${Uri.encodeComponent(deviceId)}&role=viewer';
  }
}
