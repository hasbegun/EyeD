class ApiConfig {
  final String engineBaseUrl;

  const ApiConfig({
    this.engineBaseUrl = ApiConfig.defaultBaseUrl,
  });

  static const _apiMode = String.fromEnvironment('API_MODE');

  /// In proxy mode (Docker/nginx), use the relative /engine path so nginx
  /// forwards requests to iris-engine2.  For local dev, hit the port directly.
  static const String defaultBaseUrl =
      _apiMode == 'proxy' ? '/engine' : 'http://127.0.0.1:9510';
}
