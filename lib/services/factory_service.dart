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
          // Required by the "own or admin" RLS policy's WITH CHECK — every
          // factory is stamped with its creator so per-user ownership
          // scoping works.
          'owner_id': _client.auth.currentUser?.id,
        })
        .select()
        .single();
    return Factory.fromJson(row);
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

  Future<Factory> renameFactory(int factoryId, String newName) async {
    final row = await _client
        .from('factories')
        .update({'factory_name': newName})
        .eq('factory_id', factoryId)
        .select()
        .single();
    return Factory.fromJson(row);
  }

  /// Deletes a factory. Throws if the database still has rows that reference
  /// it (machines, materials, stock, etc.) and the foreign keys don't
  /// cascade — the caller surfaces that as a "remove its data first" message
  /// rather than silently failing.
  Future<void> deleteFactory(int factoryId) async {
    await _client.from('factories').delete().eq('factory_id', factoryId);
  }
}
