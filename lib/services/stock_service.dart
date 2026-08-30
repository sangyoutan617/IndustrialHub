import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/finished_stock.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';
import 'data_event_service.dart';
import 'stock_offline_queue_service.dart';

class StockService {
  final SupabaseClient _client = Supabase.instance.client;
  final _queue = StockOfflineQueueService();

  static const _selectWithProduct = '*, products(product_name)';

  Future<List<FinishedStock>> getStockList(int factoryId) async {
    final rows = await _client
        .from('finished_stock')
        .select(_selectWithProduct)
        .eq('factory_id', factoryId);
    // Sorted client-side by the joined product name — finished_stock has
    // no product-name column of its own to order the query by any more.
    final list = (rows as List)
        .map((row) => FinishedStock.fromJson(row as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.productName.compareTo(b.productName));
    return list;
  }

  /// Creates a finished-stock row for [product] — one row per product per
  /// factory (see the DB's own unique constraint); the caller is
  /// responsible for only offering products that don't already have one
  /// (see stock_list_screen.dart's picker).
  Future<FinishedStock> createStock(
    int factoryId,
    Product product,
    int initialQuantity,
  ) async {
    final row = await _client
        .from('finished_stock')
        .insert({
          'factory_id': factoryId,
          'product_id': product.productId,
          'current_quantity': initialQuantity,
        })
        .select(_selectWithProduct)
        .single();
    final result = FinishedStock.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.stock,
    );
    return result;
  }

  Future<void> deleteStock(int stockId, {int? factoryId}) async {
    await _client.from('finished_stock').delete().eq('stock_id', stockId);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.stock,
      );
    }
  }

  Future<List<StockMovement>> getMovements(int stockId) async {
    final rows = await _client
        .from('stock_movements')
        .select()
        .eq('stock_id', stockId)
        .order('movement_date', ascending: false);
    return (rows as List)
        .map((row) => StockMovement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  // One query for every movement across every product — powers the
  // StockTrendScreen heatmap.
  Future<List<StockMovement>> getMovementsForFactory(int factoryId) async {
    final rows = await _client
        .from('stock_movements')
        .select('*, finished_stock!inner(factory_id)')
        .eq('finished_stock.factory_id', factoryId)
        .order('movement_date', ascending: false);
    return (rows as List)
        .map((row) => StockMovement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordMovement({
    required int stockId,
    required String movementType,
    required int quantity,
    required DateTime movementDate,
    String? note,
    bool isSimulated = false,
    int? factoryId,
  }) async {
    final current = await _client
        .from('finished_stock')
        .select('current_quantity, factory_id')
        .eq('stock_id', stockId)
        .single();
    final currentQuantity = current['current_quantity'] as int;
    final fId = factoryId ?? current['factory_id'] as int?;

    final delta = switch (movementType) {
      StockMovementType.productionIn => quantity.abs(),
      StockMovementType.returned => quantity.abs(),
      StockMovementType.shipmentOut => -quantity.abs(),
      StockMovementType.damaged => -quantity.abs(),
      _ => quantity, // adjustment: signed as entered
    };
    final newQuantity = currentQuantity + delta;
    if (newQuantity < 0) {
      throw Exception('This movement would take stock below zero.');
    }

    await _client.from('stock_movements').insert({
      'stock_id': stockId,
      'movement_type': movementType,
      'quantity': quantity,
      'movement_date': movementDate.toIso8601String().substring(0, 10),
      'note': note,
      if (isSimulated) 'is_simulated': true,
    });

    await _client
        .from('finished_stock')
        .update({
          'current_quantity': newQuantity,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('stock_id', stockId);

    if (fId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: fId,
        source: DataChangeSource.stock,
      );
    }
  }

  // Queues locally first (always succeeds), then tries Supabase right away.
  // Returns true if it synced immediately, false if it's still pending —
  // the factory floor rarely has reliable Wi-Fi, so recording a movement
  // should never block on that.
  Future<bool> recordMovementQueued({
    required int stockId,
    required String movementType,
    required int quantity,
    required DateTime movementDate,
    String? note,
  }) async {
    final id = await _queue.enqueue(
      stockId: stockId,
      movementType: movementType,
      quantity: quantity,
      movementDate: movementDate,
      note: note,
    );
    try {
      await recordMovement(
        stockId: stockId,
        movementType: movementType,
        quantity: quantity,
        movementDate: movementDate,
        note: note,
      );
      await _queue.markSynced(id);
      return true;
    } catch (e) {
      if (e.toString().contains('below zero')) {
        // A real conflict, not a connectivity problem — retrying it later
        // would never succeed, so surface it now instead of queuing forever.
        await _queue.remove(id);
        rethrow;
      }
      return false;
    }
  }

  Future<int> pendingMovementCount() => _queue.pendingCount();

  // Retries every unsynced queue entry — call on screen load/refresh so a
  // movement recorded offline gets pushed up as soon as Supabase is
  // reachable again, without the user having to do anything. Returns one
  // message per entry that turned out to be a real conflict (not just
  // unreachable). A conflict is only removed from the queue when
  // [dropConflicts] is true — a silent background sync leaves it pending
  // rather than discarding it with nobody having seen why; the user's own
  // "Retry" tap is what actually resolves and reports it.
  Future<List<String>> syncPendingMovements({bool dropConflicts = false}) async {
    final rows = await _queue.getPending();
    final failures = <String>[];
    for (final row in rows) {
      try {
        await recordMovement(
          stockId: row['stock_id'] as int,
          movementType: row['movement_type'] as String,
          quantity: row['quantity'] as int,
          movementDate: DateTime.parse(row['movement_date'] as String),
          note: row['note'] as String?,
        );
        await _queue.markSynced(row['id'] as int);
      } catch (e) {
        if (e.toString().contains('below zero')) {
          if (dropConflicts) await _queue.remove(row['id'] as int);
          failures.add(
            'A queued ${_movementLabel(row['movement_type'] as String)} of '
            '${row['quantity']} could not sync — it would take stock below '
            'zero.',
          );
        }
        // Otherwise still unreachable — leave queued, retried next time.
      }
    }
    return failures;
  }

  String _movementLabel(String type) => switch (type) {
    StockMovementType.productionIn => 'Production in',
    StockMovementType.returned => 'Returned',
    StockMovementType.shipmentOut => 'Shipment out',
    StockMovementType.damaged => 'Damaged',
    _ => 'Adjustment',
  };
}
