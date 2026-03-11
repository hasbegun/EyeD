class ApiConfig {
  final String engineBaseUrl;

  const ApiConfig({
    this.engineBaseUrl = 'http://127.0.0.1:9500',
  });

  static const String engine1Url = 'http://127.0.0.1:9500';
  static const String engine2Url = 'http://127.0.0.1:9510';
}
