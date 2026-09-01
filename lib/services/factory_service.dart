import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/factory.dart';

class FactoryService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Factory>> getFactories() async {
    final rows = await _client
        .from('factories')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((row) => Factory.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Factory> createFactory(
    String factoryName, {
    String? location,
    String? state,
    String? msicCode,
  }) async {
    final row = await _client
        .from('factories')
        .insert({
          ...Factory(
            factoryId: 0,
            factoryName: factoryName,
            location: location,
            state: state,
            msicCode: msicCode,
          ).toInsertJson(),
          'owner_id': _client.auth.currentUser?.id,
        })
        .select()
        .single();
    final factory = Factory.fromJson(row);
    await _client.from('products').insert({
      'factory_id': factory.factoryId,
      'product_name': 'General',
      'unit': 'units',
      'is_general': true,
    });
    return factory;
  }

  Future<Factory> updateMsicCode(int factoryId, String msicCode) async {
    final row = await _client
        .from('factories')
        .update({'msic_code': msicCode})
        .eq('factory_id', factoryId)
        .select()
        .single();
    return Factory.fromJson(row);
  }

  Future<Factory> updateFactoryDetails(
    int factoryId, {
    String? location,
    String? state,
    String? msicCode,
  }) async {
    final updates = <String, dynamic>{
      'location': ?location,
      'state': ?state,
      'msic_code': ?msicCode,
    };
    if (updates.isEmpty) {
      final row = await _client
          .from('factories')
          .select()
          .eq('factory_id', factoryId)
          .single();
      return Factory.fromJson(row);
    }
    final row = await _client
        .from('factories')
        .update(updates)
        .eq('factory_id', factoryId)
        .select()
        .single();
    return Factory.fromJson(row);
  }

  Future<Factory> renameFactory(int factoryId, String newName) async {
    final row = await _client
        .from('factories')
        .update({'factory_name': newName})
        .eq('factory_id', factoryId)
        .select()
        .single();
    return Factory.fromJson(row);
  }

  Future<void> deleteFactory(int factoryId) async {
    await _client.from('factories').delete().eq('factory_id', factoryId);
  }
}
