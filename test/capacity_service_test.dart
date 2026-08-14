import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/machine.dart';
import 'package:industrial_hub/models/manpower.dart';
import 'package:industrial_hub/services/capacity_service.dart';

Machine _machine({
  double rated = 10,
  double hours = 8,
  double uptime = 100,
  String status = 'Active',
}) {
  return Machine(
    machineId: 1,
    factoryId: 1,
    machineName: 'Test machine',
    ratedOutputPerHour: rated,
    operatingHoursPerDay: hours,
    uptimePercent: uptime,
    status: status,
    isSimulated: false,
  );
}

Manpower _shift({int workers = 5, double hours = 8, double perHour = 2}) {
  return Manpower(
    manpowerId: 1,
    factoryId: 1,
    shiftName: 'Test shift',
    workerCount: workers,
    shiftHours: hours,
    outputPerWorkerHour: perHour,
    isSimulated: false,
  );
}

/// Builds a snapshot the same way CapacityService.getSnapshot does — the
/// effective ceiling is the lower of the two capacities and the bottleneck
/// resource is derived from them — so tests exercise internally consistent
/// states rather than hand-picked contradictions.
CapacitySnapshot _snapshot({
  required double machineCapacity,
  required double manpowerCapacity,
  List<Manpower> shifts = const [],
}) {
  final effective = machineCapacity < manpowerCapacity
      ? machineCapacity
      : manpowerCapacity;
  return CapacitySnapshot(
    machines: const [],
    shifts: shifts,
    machineCapacity: machineCapacity,
    manpowerCapacity: manpowerCapacity,
    effectiveCapacity: effective,
    bottleneckResource: CapacityService.bottleneckResourceFor(
      machineCapacity,
      manpowerCapacity,
    ),
  );
}

void main() {
  group('CapacityService.computeMachineCapacity', () {
    test('sums rated output * hours * uptime for active machines', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(rated: 10, hours: 8, uptime: 100),
        _machine(rated: 5, hours: 10, uptime: 50),
      ]);
      expect(capacity, 105);
    });

    test('excludes machines under maintenance', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(rated: 10, hours: 8, uptime: 100),
        _machine(
          rated: 100,
          hours: 24,
          uptime: 100,
          status: 'Under Maintenance',
        ),
      ]);
      expect(capacity, 80);
    });

    test('empty list yields zero capacity', () {
      expect(CapacityService.computeMachineCapacity([]), 0);
    });
  });

  group('CapacityService.computeManpowerCapacity', () {
    test('sums worker_count * shift_hours * output_per_worker_hour', () {
      final capacity = CapacityService.computeManpowerCapacity([
        _shift(workers: 5, hours: 8, perHour: 2),
        _shift(workers: 3, hours: 6, perHour: 1),
      ]);
      expect(capacity, 98);
    });
  });

  group('CapacityService.bottleneckResourceFor', () {
    test('names MACHINE when machine capacity is the lower ceiling', () {
      expect(CapacityService.bottleneckResourceFor(80, 120), 'MACHINE');
    });

    test('names MANPOWER when manpower capacity is the lower ceiling', () {
      expect(CapacityService.bottleneckResourceFor(120, 80), 'MANPOWER');
    });
  });

  // computeHiringGap is the deterministic number the AI insight card narrates
  // ("hire N more workers"), so every branch of it is pinned here — the AI
  // must never be handed a wrong figure to explain.
  group('CapacityService.computeHiringGap', () {
    test('machine bottleneck: no hiring recommendation, since hiring '
        'more workers would not lift output', () {
      final gap = CapacityService.computeHiringGap(
        _snapshot(
          machineCapacity: 80,
          manpowerCapacity: 120,
          shifts: [_shift(workers: 10, hours: 8, perHour: 1)],
        ),
      );
      expect(gap.bottleneck, 'MACHINE');
      expect(gap.currentWorkers, 10);
      expect(gap.additionalWorkersNeeded, isNull);
    });

    test('manpower bottleneck: sizes the extra workers that close the gap '
        'to the machine ceiling', () {
      // 10 workers produce 80/day (8 each); machine ceiling is 120, so the
      // 40/day gap needs 40 / 8 = 5 more workers.
      final gap = CapacityService.computeHiringGap(
        _snapshot(
          machineCapacity: 120,
          manpowerCapacity: 80,
          shifts: [_shift(workers: 10, hours: 8, perHour: 1)],
        ),
      );
      expect(gap.bottleneck, 'MANPOWER');
      expect(gap.currentWorkers, 10);
      expect(gap.additionalWorkersNeeded, 5);
    });

    test('rounds a fractional worker requirement up — you cannot hire a '
        'fraction of a worker', () {
      // Gap is 45/day at 8/worker/day = 5.625 workers, which rounds to 6.
      final gap = CapacityService.computeHiringGap(
        _snapshot(
          machineCapacity: 125,
          manpowerCapacity: 80,
          shifts: [_shift(workers: 10, hours: 8, perHour: 1)],
        ),
      );
      expect(gap.additionalWorkersNeeded, 6);
    });

    test('equal capacities: labelled manpower but no workers needed', () {
      final gap = CapacityService.computeHiringGap(
        _snapshot(
          machineCapacity: 80,
          manpowerCapacity: 80,
          shifts: [_shift(workers: 10, hours: 8, perHour: 1)],
        ),
      );
      expect(gap.bottleneck, 'MANPOWER');
      expect(gap.additionalWorkersNeeded, isNull);
    });

    test('manpower bottleneck with no shift data: cannot size a '
        'recommendation', () {
      final gap = CapacityService.computeHiringGap(
        _snapshot(machineCapacity: 120, manpowerCapacity: 0),
      );
      expect(gap.bottleneck, 'MANPOWER');
      expect(gap.currentWorkers, 0);
      expect(gap.additionalWorkersNeeded, isNull);
    });

    test('workers present but a zero output rate: cannot size a '
        'recommendation (no divide-by-zero)', () {
      final gap = CapacityService.computeHiringGap(
        _snapshot(
          machineCapacity: 100,
          manpowerCapacity: 0,
          shifts: [_shift(workers: 5, hours: 8, perHour: 0)],
        ),
      );
      expect(gap.bottleneck, 'MANPOWER');
      expect(gap.currentWorkers, 5);
      expect(gap.additionalWorkersNeeded, isNull);
    });
  });
}
