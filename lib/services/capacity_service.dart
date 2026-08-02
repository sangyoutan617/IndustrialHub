import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ipi_benchmark.dart';
import '../models/machine.dart';
import '../models/manpower.dart';
import '../models/msic_code.dart';
import '../models/productivity_benchmark.dart';
import 'machine_service.dart';
import 'manpower_service.dart';

class CapacitySnapshot {
  final List<Machine> machines;
  final List<Manpower> shifts;
  final double machineCapacity;
  final double manpowerCapacity;
  final double effectiveCapacity;
  final String bottleneckResource;

  const CapacitySnapshot({
    required this.machines,
    required this.shifts,
    required this.machineCapacity,
    required this.manpowerCapacity,
    required this.effectiveCapacity,
    required this.bottleneckResource,
  });
}

/// Deterministic hiring gap for the AI insight card — Gemini narrates this,
/// it never computes it. When labour is the bottleneck, this is how many
/// more workers (at the current average output rate) would be needed to
/// raise labour capacity up to the machine ceiling. Null when machines are
/// the bottleneck (hiring wouldn't raise output) or there isn't enough
/// shift data to size a recommendation.
class HiringGap {
  final String bottleneck;
  final int currentWorkers;
  final int? additionalWorkersNeeded;

  const HiringGap({
    required this.bottleneck,
    required this.currentWorkers,
    this.additionalWorkersNeeded,
  });
}

class CapacityService {
  final MachineService _machineService = MachineService();
  final ManpowerService _manpowerService = ManpowerService();
  final SupabaseClient _client = Supabase.instance.client;

  static double computeMachineCapacity(Iterable<Machine> machines) {
    return machines.where((m) => m.isActive).fold<double>(0, (sum, m) {
      return sum +
          m.ratedOutputPerHour *
              m.operatingHoursPerDay *
              (m.uptimePercent / 100);
    });
  }

  static double computeManpowerCapacity(Iterable<Manpower> shifts) {
    return shifts.fold<double>(0, (sum, s) {
      return sum + s.workerCount * s.shiftHours * s.outputPerWorkerHour;
    });
  }

  static String bottleneckResourceFor(
    double machineCapacity,
    double manpowerCapacity,
  ) {
    return machineCapacity < manpowerCapacity ? 'MACHINE' : 'MANPOWER';
  }

  Future<CapacitySnapshot> getSnapshot(int factoryId) async {
    final machines = await _machineService.getMachines(factoryId);
    final shifts = await _manpowerService.getShifts(factoryId);

    final machineCapacity = computeMachineCapacity(machines);
    final manpowerCapacity = computeManpowerCapacity(shifts);
    final effectiveCapacity = machineCapacity < manpowerCapacity
        ? machineCapacity
        : manpowerCapacity;
    final bottleneckResource = bottleneckResourceFor(
      machineCapacity,
      manpowerCapacity,
    );

    return CapacitySnapshot(
      machines: machines,
      shifts: shifts,
      machineCapacity: machineCapacity,
      manpowerCapacity: manpowerCapacity,
      effectiveCapacity: effectiveCapacity,
      bottleneckResource: bottleneckResource,
    );
  }

  static HiringGap computeHiringGap(CapacitySnapshot snapshot) {
    final currentWorkers = snapshot.shifts.fold<int>(
      0,
      (sum, s) => sum + s.workerCount,
    );

    if (snapshot.bottleneckResource != 'MANPOWER' || currentWorkers == 0) {
      return HiringGap(
        bottleneck: snapshot.bottleneckResource,
        currentWorkers: currentWorkers,
      );
    }

    final totalWorkerDayOutput = snapshot.shifts.fold<double>(
      0,
      (sum, s) => sum + s.workerCount * s.shiftHours * s.outputPerWorkerHour,
    );
    final avgOutputPerWorkerDay = totalWorkerDayOutput / currentWorkers;
    if (avgOutputPerWorkerDay <= 0) {
      return HiringGap(
        bottleneck: snapshot.bottleneckResource,
        currentWorkers: currentWorkers,
      );
    }

    final gap = snapshot.machineCapacity - snapshot.manpowerCapacity;
    final additional = (gap / avgOutputPerWorkerDay).ceil();
    return HiringGap(
      bottleneck: snapshot.bottleneckResource,
      currentWorkers: currentWorkers,
      additionalWorkersNeeded: additional > 0 ? additional : null,
    );
  }

  double? outputPerWorker(CapacitySnapshot snapshot) {
    final totalWorkers = snapshot.shifts.fold<int>(
      0,
      (sum, s) => sum + s.workerCount,
    );
    if (totalWorkers == 0) return null;
    return snapshot.effectiveCapacity / totalWorkers;
  }

  Future<List<MsicCode>> getMsicCodes() async {
    final rows = await _client
        .from('msic_codes')
        .select()
        .order('msic_code', ascending: true);
    return (rows as List)
        .map((row) => MsicCode.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<MsicCode?> getMsicByCode(String msicCode) async {
    final row = await _client
        .from('msic_codes')
        .select()
        .eq('msic_code', msicCode)
        .maybeSingle();
    return row == null ? null : MsicCode.fromJson(row);
  }

  Future<ProductivityBenchmark?> getProductivityBenchmark(String sector) async {
    final rows = await _client
        .from('productivity_benchmarks')
        .select()
        .ilike('sector', sector)
        .order('year', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return ProductivityBenchmark.fromJson(list.first as Map<String, dynamic>);
  }

  Future<List<IpiBenchmark>> getIpiTrend(
    String division, {
    int months = 12,
  }) async {
    final rows = await _client
        .from('ipi_benchmarks')
        .select()
        .eq('division', division)
        .order('date', ascending: false)
        .limit(months);
    final list = (rows as List)
        .map((row) => IpiBenchmark.fromJson(row as Map<String, dynamic>))
        .toList();
    return list.reversed.toList();
  }
}
