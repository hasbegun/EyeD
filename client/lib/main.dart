import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress known Flutter platform assertion bugs:
  // - macOS keyboard: https://github.com/flutter/flutter/issues/124879
  // - web trackpad: PointerDeviceKind.trackpad assertion in gesture converter
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exception.toString();
    if (msg.contains('_assertEventIsRegular') ||
        msg.contains('PointerDeviceKind.trackpad')) {
      return;
    }
    originalOnError?.call(details);
  };

  runApp(const ProviderScope(child: EyedApp()));
}
