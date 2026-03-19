/// Compile-time mode configuration derived from --dart-define=EYED_MODE.
///
/// All values are `const` — baked in at build time, immune to runtime
/// mutation via browser devtools (satisfies security gate S4).
///
/// Safe-by-default: absent EYED_MODE → prod.
class ModeConfig {
  ModeConfig._();

  /// The operational mode string: "dev" | "test" | "prod".
  static const String mode =
      String.fromEnvironment('EYED_MODE', defaultValue: 'prod');

  static const bool isDev  = mode == 'dev';
  static const bool isTest = mode == 'test';
  static const bool isProd = mode == 'prod';

  /// True in dev and test — enables FHE toggle UI and DEV banner.
  /// False in prod — no dev-only UI is compiled into the widget tree.
  static const bool showDevTools = isDev || isTest;
}
