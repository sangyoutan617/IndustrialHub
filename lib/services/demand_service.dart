import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/demand_forecast.dart';
import '../models/stock_movement.dart';
import 'data_event_service.dart';

class DemandService {
  final SupabaseClient _client = Supabase.instance.client;

  static const _selectWithProduct = '*, products(product_name)';

  Future<List<DemandForecast>> getForecasts(int factoryId) async {
    final rows = await _client
        .from('demand_forecast')
        .select(_selectWithProduct)
        .eq('factory_id', factoryId)
        .order('product_name', ascending: true);
    return (rows as List)
        .map((row) => DemandForecast.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<DemandForecast> createForecast(DemandForecast forecast) async {
    final row = await _client
        .from('demand_forecast')
        .insert(forecast.toInsertJson(forecast.factoryId))
        .select(_selectWithProduct)
        .single();
    final result = DemandForecast.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: forecast.factoryId,
      source: DataChangeSource.demand,
    );
    return result;
  }

  Future<DemandForecast> updateForecast(
    int demandId,
    DemandForecast forecast,
  ) async {
    final row = await _client
        .from('demand_forecast')
        .update(forecast.toInsertJson(forecast.factoryId))
        .eq('demand_id', demandId)
        .select(_selectWithProduct)
        .single();
    final result = DemandForecast.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: forecast.factoryId,
      source: DataChangeSource.demand,
    );
    return result;
  }

  Future<void> deleteForecast(int demandId, {int? factoryId}) async {
    await _client.from('demand_forecast').delete().eq('demand_id', demandId);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.demand,
      );
    }
  }

  /// Suggests a required_per_day baseline from actual shipment history,
  /// rather than leaving it as a number the user just types with no basis.
  /// Purely a suggestion — the caller still lets the user override it.
  /// Returns null if there's no matching finished_stock row (this product
  /// isn't tracked as finished stock yet) or no shipment_out movements to
  /// derive a rate from.
  Future<double?> suggestRequiredPerDay({
    required int factoryId,
    required int productId,
    int lookbackDays = 30,
  }) async {
    final stockRow = await _client
        .from('finished_stock')
        .select('stock_id')
        .eq('factory_id', factoryId)
        .eq('product_id', productId)
        .maybeSingle();
    if (stockRow == null) return null;
    final stockId = stockRow['stock_id'] as int;

    final since = DateTime.now().subtract(Duration(days: lookbackDays));
    final rows = await _client
        .from('stock_movements')
        .select('quantity')
        .eq('stock_id', stockId)
        .eq('movement_type', StockMovementType.shipmentOut)
        .gte('movement_date', since.toIso8601String().substring(0, 10));

    final movements = rows as List;
    if (movements.isEmpty) return null;

    final totalShipped = movements.fold<double>(
      0,
      (sum, row) => sum + (row['quantity'] as num).abs(),
    );
    return totalShipped / lookbackDays;
  }
}
