import 'dart:math' as math;

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

class SectorComparisonPoint {
  final DateTime month;
  final double factoryIndex;
  final double sectorIndex;

  const SectorComparisonPoint({
    required this.month,
    required this.factoryIndex,
    required this.sectorIndex,
  });
}

class SectorComparison {
  final List<SectorComparisonPoint> points;

  const SectorComparison(this.points);

  DateTime get baseMonth => points.first.month;
  DateTime get latestMonth => points.last.month;

  double get factoryChangePercent => points.last.factoryIndex - 100;
  double get sectorChangePercent => points.last.sectorIndex - 100;
}

class SimulatorBaseline {
  final double machineNameplate;

  final double outputPerWorkerHour;

  final int activeMachines;
  final int workers;
  final int shiftHours;

  const SimulatorBaseline({
    required this.machineNameplate,
    required this.outputPerWorkerHour,
    required this.activeMachines,
    required this.workers,
    required this.shiftHours,
  });

  static SimulatorBaseline from(CapacitySnapshot snapshot) {
    final active = snapshot.machines.where((m) => m.isActive).toList();
    final basis = active.isNotEmpty ? active : snapshot.machines;

    final nameplateTotal = basis.fold<double>(
      0,
      (sum, m) =>
          sum + m.ratedOutputPerHour * m.operatingHoursPerDay * m.unitCount,
    );
    final machineNameplate = basis.isEmpty
        ? 0.0
        : nameplateTotal / basis.length;

    final totalWorkers = snapshot.shifts.fold<int>(
      0,
      (sum, s) => sum + s.workerCount,
    );
    final workerHours = snapshot.shifts.fold<double>(
      0,
      (sum, s) => sum + s.workerCount * s.shiftHours,
    );
    final outputPerWorkerHour = workerHours > 0
        ? CapacityService.sumManpowerCapacity(snapshot.shifts) / workerHours
        : _mean(snapshot.shifts.map((s) => s.outputPerWorkerHour));
    final shiftHours = totalWorkers > 0
        ? workerHours / totalWorkers
        : _mean(snapshot.shifts.map((s) => s.shiftHours));

    return SimulatorBaseline(
      machineNameplate: machineNameplate,
      outputPerWorkerHour: outputPerWorkerHour,
      activeMachines: active.length,
      workers: totalWorkers,
      shiftHours: shiftHours.round(),
    );
  }

  static double _mean(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }
}

class CapacityService {
  final MachineService _machineService = MachineService();
  final ManpowerService _manpowerService = ManpowerService();
  final SupabaseClient _client = Supabase.instance.client;

  static double machineRowCapacity(Machine m) =>
      m.ratedOutputPerHour * m.operatingHoursPerDay * m.unitCount;

  static double stationCapacity(Manpower s) =>
      s.workerCount * s.shiftHours * s.outputPerWorkerHour;

  static Map<String, ({String? label, double capacity})> machineStages(
    Iterable<Machine> machines,
  ) {
    final stages = <String, ({String? label, double capacity})>{};
    for (final m in machines.where((m) => m.isActive)) {
      final existing = stages[m.stageKey];
      stages[m.stageKey] = (
        label: existing?.label ?? m.stageLabel,
        capacity: (existing?.capacity ?? 0) + machineRowCapacity(m),
      );
    }
    return stages;
  }

  static double computeMachineCapacity(Iterable<Machine> machines) {
    final caps = machineStages(machines).values.map((s) => s.capacity);
    return caps.isEmpty ? 0 : caps.reduce(math.min);
  }

  static double computeManpowerCapacity(Iterable<Manpower> shifts) {
    final list = shifts.toList();
    if (list.isEmpty) return 0;
    return list.map(stationCapacity).reduce(math.min);
  }

  static double sumManpowerCapacity(Iterable<Manpower> shifts) {
    return shifts.fold<double>(0, (sum, s) => sum + stationCapacity(s));
  }

  static double sumMachineCapacity(Iterable<Machine> machines) {
    return machines
        .where((m) => m.isActive)
        .fold<double>(0, (sum, m) => sum + machineRowCapacity(m));
  }

  static String bottleneckResourceFor(
    double machineCapacity,
    double manpowerCapacity,
  ) {
    return machineCapacity < manpowerCapacity ? 'MACHINE' : 'MANPOWER';
  }

  Future<CapacitySnapshot> getSnapshot(int factoryId, {int? productId}) async {
    final allMachines = await _machineService.getMachines(factoryId);
    final allShifts = await _manpowerService.getShifts(factoryId);
    final machines = productId == null
        ? allMachines
        : allMachines.where((m) => m.productId == productId).toList();
    final shifts = productId == null
        ? allShifts
        : allShifts.where((s) => s.productId == productId).toList();

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

  static SectorComparison? buildSectorComparison({
    required List<IpiBenchmark> ipiTrend,
    required Map<DateTime, double> factoryMonthlyOutput,
  }) {
    final months = <DateTime>[];
    final sector = <double>[];
    final factory = <double>[];
    for (final reading in ipiTrend) {
      final month = DateTime(reading.date.year, reading.date.month);
      final output = factoryMonthlyOutput[month];
      if (output == null) continue;
      months.add(month);
      sector.add(reading.productionIndex);
      factory.add(output);
    }
    if (months.length < 2) return null;
    if (factory.first <= 0 || sector.first <= 0) return null;

    return SectorComparison([
      for (var i = 0; i < months.length; i++)
        SectorComparisonPoint(
          month: months[i],
          factoryIndex: factory[i] / factory.first * 100,
          sectorIndex: sector[i] / sector.first * 100,
        ),
    ]);
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
