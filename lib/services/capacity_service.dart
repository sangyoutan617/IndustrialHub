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

/// One month of the factory-vs-sector comparison. DOSM publishes IPI as an
/// index rather than a unit count, so the factory's own output is rebased
/// onto the same 100-at-the-base-month footing. What the two series make
/// comparable is how each has *moved* since that month — never the levels
/// themselves, which are in different units entirely.
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

  /// Percent change since the base month, for each series. Both are read off
  /// the rebased index, so they answer "who grew faster", not "who is bigger".
  double get factoryChangePercent => points.last.factoryIndex - 100;
  double get sectorChangePercent => points.last.sectorIndex - 100;
}

/// The per-machine and per-worker rates the what-if simulator extrapolates
/// from, together with the field values that mean "nothing changed yet".
///
/// The simulator can't just call [CapacityService.computeMachineCapacity]:
/// that sums the machines that exist, while the simulator has to price a
/// machine count that doesn't exist yet. So it needs a per-machine rate —
/// but derived so the untouched baseline reproduces the real ceiling
/// instead of a number the Capacity dashboard disagrees with.
class SimulatorBaseline {
  /// Mean full-uptime output of one active machine, i.e. mean(rated × hours).
  ///
  /// The mean of the *product*, not the product of the means. Multiplying
  /// mean(rated) by mean(hours) silently drops the covariance between the
  /// two, which understates any fleet where the faster machines also run the
  /// longer days.
  final double machineNameplate;

  /// Worker-hour-weighted output rate, so a shift that supplies more
  /// worker-hours moves the rate proportionally instead of counting once.
  final double outputPerWorkerHour;

  final int activeMachines;
  final int uptimePercent;
  final int workers;
  final int shiftHours;

  const SimulatorBaseline({
    required this.machineNameplate,
    required this.outputPerWorkerHour,
    required this.activeMachines,
    required this.uptimePercent,
    required this.workers,
    required this.shiftHours,
  });

  /// Both rates are weighted so that, at the returned field values, the
  /// simulator's own arithmetic reproduces [CapacityService.computeMachineCapacity]
  /// and [CapacityService.computeManpowerCapacity] — up to the rounding
  /// forced by the simulator's whole-number-only inputs.
  static SimulatorBaseline from(CapacitySnapshot snapshot) {
    final active = snapshot.machines.where((m) => m.isActive).toList();
    // Inactive machines must not drag the rate — but with nothing active at
    // all, an average over every machine is still the best available guess
    // at what one machine is worth.
    final basis = active.isNotEmpty ? active : snapshot.machines;

    final nameplateTotal = basis.fold<double>(
      0,
      (sum, m) => sum + m.ratedOutputPerHour * m.operatingHoursPerDay,
    );
    final machineNameplate = basis.isEmpty
        ? 0.0
        : nameplateTotal / basis.length;

    // Capacity-weighted, so nameplateTotal × uptime/100 lands back on
    // Σ(rated × hours × uptime/100) rather than on a plain per-machine mean
    // that ignores how much capacity each machine's uptime applies to.
    final uptimePercent = nameplateTotal > 0
        ? basis.fold<double>(
                0,
                (sum, m) =>
                    sum +
                    m.ratedOutputPerHour *
                        m.operatingHoursPerDay *
                        m.uptimePercent,
              ) /
              nameplateTotal
        : 100.0;

    final totalWorkers = snapshot.shifts.fold<int>(
      0,
      (sum, s) => sum + s.workerCount,
    );
    final workerHours = snapshot.shifts.fold<double>(
      0,
      (sum, s) => sum + s.workerCount * s.shiftHours,
    );
    final outputPerWorkerHour = workerHours > 0
        ? CapacityService.computeManpowerCapacity(snapshot.shifts) / workerHours
        : _mean(snapshot.shifts.map((s) => s.outputPerWorkerHour));
    final shiftHours = totalWorkers > 0
        ? workerHours / totalWorkers
        : _mean(snapshot.shifts.map((s) => s.shiftHours));

    return SimulatorBaseline(
      machineNameplate: machineNameplate,
      outputPerWorkerHour: outputPerWorkerHour,
      activeMachines: active.length,
      uptimePercent: uptimePercent.round().clamp(0, 100),
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

  /// Puts factory output and its sector's IPI onto one chart by rebasing both
  /// to 100 at the first month they share. Only months present in *both*
  /// series are kept, so a gap in the factory's log shortens the comparison
  /// rather than reading as a collapse in output.
  ///
  /// Returns null when the overlap is under two months (a single point is a
  /// dot, not a trend) or when a base value is non-positive and there is
  /// nothing to divide by.
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
