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
}
