import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/demand_forecast.dart';

class DemandService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<DemandForecast>> getForecasts(int factoryId) async {
    final rows = await _client
        .from('demand_forecast')
        .select()
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
        .select()
        .single();
    return DemandForecast.fromJson(row);
  }

  Future<DemandForecast> updateForecast(
    int demandId,
    DemandForecast forecast,
  ) async {
    final row = await _client
        .from('demand_forecast')
        .update(forecast.toInsertJson(forecast.factoryId))
        .eq('demand_id', demandId)
        .select()
        .single();
    return DemandForecast.fromJson(row);
  }

  Future<void> deleteForecast(int demandId) async {
    await _client.from('demand_forecast').delete().eq('demand_id', demandId);
  }
}
