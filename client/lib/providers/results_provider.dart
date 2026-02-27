import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/results_socket.dart';
import '../models/analyze_result.dart';
import 'api_config_provider.dart';

final wsConnectedProvider = StateProvider<bool>((ref) => false);

final resultsSocketProvider = Provider<ResultsSocket>((ref) {
  final config = ref.watch(apiConfigProvider);
  final socket = ResultsSocket(url: config.wsResultsUrl);

  socket.connectionStatus.listen((connected) {
    ref.read(wsConnectedProvider.notifier).state = connected;
  });

  socket.connect();
  ref.onDispose(socket.dispose);
  return socket;
});

final resultsStreamProvider = StreamProvider<AnalyzeResult>((ref) {
  final socket = ref.watch(resultsSocketProvider);
  return socket.results;
});
