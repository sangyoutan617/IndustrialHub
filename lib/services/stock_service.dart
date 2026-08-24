import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/finished_stock.dart';
import '../models/stock_movement.dart';

class StockService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<FinishedStock>> getStockList(int factoryId) async {
    final rows = await _client
        .from('finished_stock')
        .select()
        .eq('factory_id', factoryId)
        .order('product_name', ascending: true);
    return (rows as List)
        .map((row) => FinishedStock.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<FinishedStock> createStock(
    int factoryId,
    String productName,
    int initialQuantity,
  ) async {
    final row = await _client
        .from('finished_stock')
        .insert({
          'factory_id': factoryId,
          'product_name': productName,
          'current_quantity': initialQuantity,
        })
        .select()
        .single();
    return FinishedStock.fromJson(row);
  }

  Future<void> deleteStock(int stockId) async {
    await _client.from('finished_stock').delete().eq('stock_id', stockId);
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
  }) async {
    final current = await _client
        .from('finished_stock')
        .select('current_quantity')
        .eq('stock_id', stockId)
        .single();
    final currentQuantity = current['current_quantity'] as int;

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
  }
}
