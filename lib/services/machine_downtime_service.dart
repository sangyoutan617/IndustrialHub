import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/machine.dart';
import '../models/machine_downtime_log.dart';
import 'data_event_service.dart';

class MachineDowntimeService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<MachineDowntimeLog>> getLog(int machineId) async {
    final rows = await _client
        .from('machine_downtime_log')
        .select()
        .eq('machine_id', machineId)
        .order('log_date', ascending: false)
        .order('log_id', ascending: false);
    return (rows as List)
        .map((row) => MachineDowntimeLog.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> logHistoricalResolvedEvents({
    required int factoryId,
    required List<
      ({
        int machineId,
        DateTime logDate,
        double hours,
        int machinesDown,
        String reason,
        DateTime repairStartedAt,
        DateTime repairedAt,
      })
    >
    events,
  }) async {
    if (events.isEmpty) return;
    await _client.from('machine_downtime_log').insert([
      for (final e in events)
        {
          'machine_id': e.machineId,
          'factory_id': factoryId,
          'log_date': e.logDate.toIso8601String().substring(0, 10),
          'downtime_hours': e.hours,
          'machines_down': e.machinesDown,
          'reason': e.reason,
          'repair_started_at': e.repairStartedAt.toUtc().toIso8601String(),
          'repaired_at': e.repairedAt.toUtc().toIso8601String(),
          'is_simulated': true,
        },
    ]);
    _notify(factoryId);
  }

  Future<void> logDowntime({
    required int machineId,
    required int factoryId,
    required double hours,
    int machinesDown = 1,
    int unitCount = 1,
    String? reason,
    required DateTime date,
    bool isSimulated = false,
  }) async {
    await _client.from('machine_downtime_log').insert({
      'machine_id': machineId,
      'factory_id': factoryId,
      'log_date': date.toIso8601String().substring(0, 10),
      'downtime_hours': hours,
      'machines_down': machinesDown,
      'reason': reason,
      if (isSimulated) 'is_simulated': true,
    });
    if (machinesDown >= unitCount) {
      await _setStatus(machineId, MachineStatus.downtime);
    }
    _notify(factoryId);
  }

  Future<void> updateDowntimeLog({
    required int logId,
    required int factoryId,
    required double hours,
    required int machinesDown,
    String? reason,
  }) async {
    await _client
        .from('machine_downtime_log')
        .update({
          'downtime_hours': hours,
          'machines_down': machinesDown,
          'reason': reason,
        })
        .eq('log_id', logId);
    _notify(factoryId);
  }

  Future<void> startRepair(int machineId, int factoryId) async {
    final openLogIds = await _openLogIds(machineId);
    if (openLogIds.isNotEmpty) {
      await _client
          .from('machine_downtime_log')
          .update({
            'repair_started_at': DateTime.now().toUtc().toIso8601String(),
          })
          .inFilter('log_id', openLogIds);
    }
    await _setStatus(machineId, MachineStatus.repair);
    _notify(factoryId);
  }

  Future<void> markRepaired(int machineId, int factoryId) async {
    final openLogIds = await _openLogIds(machineId);
    if (openLogIds.isNotEmpty) {
      await _client
          .from('machine_downtime_log')
          .update({'repaired_at': DateTime.now().toUtc().toIso8601String()})
          .inFilter('log_id', openLogIds);
    }
    await _setStatus(machineId, MachineStatus.active);
    _notify(factoryId);
  }

  Future<void> setStatus(int machineId, int factoryId, String status) async {
    await _setStatus(machineId, status);
    _notify(factoryId);
  }

  Future<List<int>> _openLogIds(int machineId) async {
    final rows = await _client
        .from('machine_downtime_log')
        .select('log_id')
        .eq('machine_id', machineId)
        .filter('repaired_at', 'is', null)
        .order('log_id', ascending: false);
    return (rows as List).map((row) => row['log_id'] as int).toList();
  }

  Future<void> _setStatus(int machineId, String status) {
    return _client
        .from('machines')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('machine_id', machineId);
  }

  void _notify(int factoryId) {
    DataEventService.instance.notifyChanged(
      factoryId: factoryId,
      source: DataChangeSource.capacity,
    );
  }
}
