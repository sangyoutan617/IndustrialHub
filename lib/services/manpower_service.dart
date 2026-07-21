import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/manpower.dart';

class ManpowerService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Manpower>> getShifts(int factoryId) async {
    final rows = await _client
        .from('manpower')
        .select()
        .eq('factory_id', factoryId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((row) => Manpower.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Manpower> createShift(
    Manpower manpower, {
    bool isSimulated = false,
  }) async {
    final row = await _client
        .from('manpower')
        .insert({
          ...manpower.toInsertJson(manpower.factoryId),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    return Manpower.fromJson(row);
  }

  Future<Manpower> updateShift(int manpowerId, Manpower manpower) async {
    final row = await _client
        .from('manpower')
        .update({
          ...manpower.toInsertJson(manpower.factoryId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('manpower_id', manpowerId)
        .select()
        .single();
    return Manpower.fromJson(row);
  }

  Future<void> deleteShift(int manpowerId) async {
    await _client.from('manpower').delete().eq('manpower_id', manpowerId);
  }
}
