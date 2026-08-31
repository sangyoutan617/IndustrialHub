import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/machine.dart';
import '../models/machine_downtime_log.dart';
import 'data_event_service.dart';

/// Drives the Active → Downtime → Repair → Active workflow: writes the
/// per-machine downtime ledger and keeps `machines.status` in step with it.
/// The machine equivalent of [MaterialMovementService] for raw materials —
/// each action here is a ledger write plus one parent-row status update.
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

  /// Bulk-writes several already-resolved downtime events in one round trip
  /// — used only for seeding historical demo data. Deliberately bypasses
  /// [logDowntime]/[startRepair]/[markRepaired]: those stamp `repair_started_at`/
  /// `repaired_at` with `DateTime.now()`, which is right for a live event but
  /// would make a 60-day-old backfilled event look repaired today. Every
  /// event here is already closed, so it has no effect on the machine's
  /// current live status — for a still-open historical event, call
  /// [logDowntime] itself with a past [DateTime] instead, which does need
  /// the live status flip.
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

  /// Opens a new downtime event. Flips the machine to `Downtime` — and so
  /// out of the capacity ceiling — **only when the whole group is down**
  /// (`machinesDown >= unitCount`). A partial stoppage is recorded for
  /// information but leaves `machines.status` (and C1) untouched; see
  /// `docs/FORMULAS.md`. Call this from `Active` or `Under Maintenance`.
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

  /// Edits an existing event's hours, reason and unit count in place. Does
  /// not touch `machines.status` or the repair timestamps — status is the
  /// repair workflow's job (or a manual correction on the machine form), so
  /// correcting a count across the full/partial line won't move a machine
  /// in or out of the ceiling on its own.
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

  /// Marks the still-open event as being actively worked on and flips the
  /// machine to `Repair`.
  Future<void> startRepair(int machineId, int factoryId) async {
    final openLogId = await _openLogId(machineId);
    if (openLogId != null) {
      await _client
          .from('machine_downtime_log')
          .update({'repair_started_at': DateTime.now().toUtc().toIso8601String()})
          .eq('log_id', openLogId);
    }
    await _setStatus(machineId, MachineStatus.repair);
    _notify(factoryId);
  }

  /// Closes the open event and returns the machine to `Active`.
  Future<void> markRepaired(int machineId, int factoryId) async {
    final openLogId = await _openLogId(machineId);
    if (openLogId != null) {
      await _client
          .from('machine_downtime_log')
          .update({'repaired_at': DateTime.now().toUtc().toIso8601String()})
          .eq('log_id', openLogId);
    }
    await _setStatus(machineId, MachineStatus.active);
    _notify(factoryId);
  }

  Future<int?> _openLogId(int machineId) async {
    final row = await _client
        .from('machine_downtime_log')
        .select('log_id')
        .eq('machine_id', machineId)
        .filter('repaired_at', 'is', null)
        .order('log_id', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : row['log_id'] as int;
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
