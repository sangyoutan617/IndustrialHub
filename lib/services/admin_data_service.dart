import 'package:supabase_flutter/supabase_flutter.dart';
import 'seed_service.dart';

class TableSimulatedCount {
  final String table;
  final String label;
  final int simulated;
  final int total;

  const TableSimulatedCount({
    required this.table,
    required this.label,
    required this.simulated,
    required this.total,
  });

  int get real => total - simulated;
}

class AdminDataService {
  final SupabaseClient _client = Supabase.instance.client;
  final SeedService _seedService = SeedService();

  static const _tables = [
    ('machines', 'machine_id', 'Machines'),
    ('manpower', 'manpower_id', 'Manpower shifts'),
    ('stock_movements', 'movement_id', 'Stock movements'),
    ('purchase_orders', 'po_id', 'Purchase orders'),
  ];

  Future<List<TableSimulatedCount>> countSimulated() async {
    final results = <TableSimulatedCount>[];
    for (final (table, idColumn, label) in _tables) {
      final totalRows = await _client.from(table).select(idColumn);
      final simulatedRows = await _client
          .from(table)
          .select(idColumn)
          .eq('is_simulated', true);
      results.add(
        TableSimulatedCount(
          table: table,
          label: label,
          simulated: (simulatedRows as List).length,
          total: (totalRows as List).length,
        ),
      );
    }
    return results;
  }

  Future<SeedResult> runSeed() => _seedService.seedDemoData();
}
