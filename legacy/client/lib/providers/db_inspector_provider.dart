import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/db_inspector_models.dart';
import 'gateway_client_provider.dart';

final dbSchemaProvider = FutureProvider<DbSchemaResponse>((ref) async {
  return await ref.read(gatewayClientProvider).getDbSchema();
});

final dbStatsProvider = FutureProvider<DbStatsResponse>((ref) async {
  return await ref.read(gatewayClientProvider).getDbStats();
});

/// State for the table browser tab.
class TableBrowserState {
  final String? selectedTable;
  final TableRowsResponse? response;
  final bool loading;
  final String? error;
  final int offset;

  const TableBrowserState({
    this.selectedTable,
    this.response,
    this.loading = false,
    this.error,
    this.offset = 0,
  });

  TableBrowserState copyWith({
    String? selectedTable,
    TableRowsResponse? response,
    bool? loading,
    String? error,
    int? offset,
  }) {
    return TableBrowserState(
      selectedTable: selectedTable ?? this.selectedTable,
      response: response ?? this.response,
      loading: loading ?? this.loading,
      error: error,
      offset: offset ?? this.offset,
    );
  }
}

class TableBrowserNotifier extends StateNotifier<TableBrowserState> {
  final Ref _ref;

  TableBrowserNotifier(this._ref) : super(const TableBrowserState());

  Future<void> selectTable(String tableName) async {
    state = TableBrowserState(selectedTable: tableName, loading: true);
    await _fetchRows(tableName, 0);
  }

  Future<void> goToPage(int offset) async {
    if (state.selectedTable == null) return;
    state = state.copyWith(loading: true, offset: offset);
    await _fetchRows(state.selectedTable!, offset);
  }

  Future<void> refresh() async {
    if (state.selectedTable == null) return;
    state = state.copyWith(loading: true);
    await _fetchRows(state.selectedTable!, state.offset);
  }

  Future<void> _fetchRows(String tableName, int offset) async {
    try {
      final resp = await _ref.read(gatewayClientProvider).getTableRows(
            tableName,
            limit: 50,
            offset: offset,
          );
      state = state.copyWith(
        response: resp,
        loading: false,
        offset: offset,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final tableBrowserProvider =
    StateNotifierProvider<TableBrowserNotifier, TableBrowserState>((ref) {
  return TableBrowserNotifier(ref);
});
