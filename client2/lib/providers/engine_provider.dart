import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SelectedEngine {
  engine1, // iris-engine (Python) — port 9500
  engine2, // iris-engine2 (C++) — port 9510
}

final selectedEngineProvider = StateProvider<SelectedEngine>(
  (ref) => SelectedEngine.engine2,
);
