import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/finished_stock.dart';
import '../models/product.dart';
import '../models/stock_movement.dart';
import 'data_event_service.dart';
import 'stock_offline_queue_service.dart';

class StockService {
  final SupabaseClient _client = Supabase.instance.client;
  final _queue = StockOfflineQueueService();

  static const _selectWithProduct = '*, products(product_name, status)';

  Future<List<FinishedStock>> getStockList(
    int factoryId, {
    bool includeArchived = false,
  }) async {
    final rows = await _client
        .from('finished_stock')
        .select(_selectWithProduct)
        .eq('factory_id', factoryId);
    var list = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(FinishedStock.fromJson)
        .toList();
    if (!includeArchived) {
      list = list.where((s) => !s.isArchived).toList();
    }
    list.sort((a, b) => a.productName.compareTo(b.productName));
    return list;
  }

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

  Future<FinishedStock> getOrCreateStockForProduct(
    int factoryId,
    Product product,
  ) async {
    final existing = await _client
        .from('finished_stock')
        .select(_selectWithProduct)
        .eq('factory_id', factoryId)
        .eq('product_id', product.productId)
        .maybeSingle();
    if (existing != null) {
      return FinishedStock.fromJson(existing);
    }
    return createStock(factoryId, product, 0);
  }

  Future<List<StockMovement>> getMovements(int stockId) async {
    final rows = await _client
        .from('stock_movements')
        .select()
        .eq('stock_id', stockId)
        .order('movement_date', ascending: false)
        .order('movement_id', ascending: false);
    return (rows as List)
        .map((row) => StockMovement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<StockMovement>> getMovementsForFactory(int factoryId) async {
    final rows = await _client
        .from('stock_movements')
        .select('*, finished_stock!inner(factory_id, products(product_name))')
        .eq('finished_stock.factory_id', factoryId)
        .order('movement_date', ascending: false);
    return (rows as List)
        .map((row) => StockMovement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordBulkMovements({
    required int stockId,
    required int factoryId,
    required List<
      ({
        String movementType,
        int quantity,
        DateTime movementDate,
        String? note,
      })
    >
    movements,
    required int finalQuantity,
  }) async {
    if (movements.isNotEmpty) {
      await _client.from('stock_movements').insert([
        for (final m in movements)
          {
            'stock_id': stockId,
            'movement_type': m.movementType,
            'quantity': m.quantity,
            'movement_date': m.movementDate.toIso8601String().substring(0, 10),
            'note': m.note,
            'is_simulated': true,
          },
      ]);
    }
    await _client
        .from('finished_stock')
        .update({
          'current_quantity': finalQuantity,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('stock_id', stockId);
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.stock,
    );
  }

  Future<int?> recordMovement({
    required int stockId,
    required String movementType,
    required int quantity,
    required DateTime movementDate,
    String? note,
    bool isSimulated = false,
    int? factoryId,
    bool notify = true,
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
      _ => quantity,
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

    if (notify && fId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: fId,
        source: DataChangeSource.stock,
      );
    }
    return fId;
  }

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
      final fId = await recordMovement(
        stockId: stockId,
        movementType: movementType,
        quantity: quantity,
        movementDate: movementDate,
        note: note,
        notify: false,
      );
      await _queue.markSynced(id);
      if (fId != null) {
        DataEventService.instance.notifyChanged(
          factoryId: fId,
          source: DataChangeSource.stock,
        );
      }
      return true;
    } catch (e) {
      if (e.toString().contains('below zero')) {
        await _queue.remove(id);
        rethrow;
      }
      return false;
    }
  }

  Future<int> pendingMovementCount() => _queue.pendingCount();

  Future<List<String>> syncPendingMovements({bool dropConflicts = false}) async {
    final rows = await _queue.getPending();
    final failures = <String>[];
    final touchedFactoryIds = <int>{};
    for (final row in rows) {
      try {
        final fId = await recordMovement(
          stockId: row['stock_id'] as int,
          movementType: row['movement_type'] as String,
          quantity: row['quantity'] as int,
          movementDate: DateTime.parse(row['movement_date'] as String),
          note: row['note'] as String?,
          notify: false,
        );
        await _queue.markSynced(row['id'] as int);
        if (fId != null) touchedFactoryIds.add(fId);
      } catch (e) {
        if (e.toString().contains('below zero')) {
          if (dropConflicts) await _queue.remove(row['id'] as int);
          failures.add(
            'A queued ${_movementLabel(row['movement_type'] as String)} of '
            '${row['quantity']} could not sync — it would take stock below '
            'zero.',
          );
        }
      }
    }
    for (final fId in touchedFactoryIds) {
      DataEventService.instance.notifyChanged(
        factoryId: fId,
        source: DataChangeSource.stock,
      );
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
