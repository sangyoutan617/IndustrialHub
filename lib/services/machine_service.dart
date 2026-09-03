import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/machine.dart';
import 'data_event_service.dart';

class MachineService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Machine>> getMachines(int factoryId) async {
    final rows = await _client
        .from('machines')
        .select()
        .eq('factory_id', factoryId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((row) => Machine.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Machine> createMachine(
    Machine machine, {
    bool isSimulated = false,
  }) async {
    final row = await _client
        .from('machines')
        .insert({
          ...machine.toInsertJson(machine.factoryId),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    final result = Machine.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: machine.factoryId,
      source: DataChangeSource.capacity,
    );
    return result;
  }

  Future<Machine> updateMachine(int machineId, Machine machine) async {
    final row = await _client
        .from('machines')
        .update({
          ...machine.toInsertJson(machine.factoryId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('machine_id', machineId)
        .select()
        .single();
    final result = Machine.fromJson(row);
    DataEventService.instance.notifyChanged(
      factoryId: machine.factoryId,
      source: DataChangeSource.capacity,
    );
    return result;
  }

  Future<void> deleteMachine(int machineId, {int? factoryId}) async {
    await _client.from('machines').delete().eq('machine_id', machineId);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.capacity,
      );
    }
  }
}
