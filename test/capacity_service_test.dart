import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/machine.dart';
import 'package:industrial_hub/models/manpower.dart';
import 'package:industrial_hub/services/capacity_service.dart';

Machine _machine({
  int id = 1,
  double rated = 10,
  double hours = 8,
  int unitCount = 1,
  String? stage,
  String status = 'Active',
}) {
  return Machine(
    machineId: id,
    factoryId: 1,
    productId: 1,
    machineName: 'Machine $id',
    ratedOutputPerHour: rated,
    operatingHoursPerDay: hours,
    unitCount: unitCount,
    stage: stage,
    status: status,
    isSimulated: false,
  );
}

Manpower _shift({int workers = 5, double hours = 8, double perHour = 2}) {
  return Manpower(
    manpowerId: 1,
    factoryId: 1,
    productId: 1,
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
  group('CapacityService.computeMachineCapacity — flow (min across stages)', () {
    test('two machines at the same stage run in parallel and add up', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(id: 1, rated: 10, hours: 8, stage: 'Filling'), // 80
        _machine(id: 2, rated: 5, hours: 8, stage: 'Filling'), // 40
      ]);
      expect(capacity, 120);
    });

    test('distinct stages run in series — the slowest stage governs', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(id: 1, rated: 100, hours: 10, stage: 'Extrusion'), // 1000
        _machine(id: 2, rated: 50, hours: 10, stage: 'Packaging'), // 500
      ]);
      expect(capacity, 500);
    });

    test('a blank stage means the machine is its own stage', () {
      // Two unstaged machines → two one-machine stages → the slower one wins.
      final capacity = CapacityService.computeMachineCapacity([
        _machine(id: 1, rated: 10, hours: 8), // 80
        _machine(id: 2, rated: 5, hours: 8), // 40
      ]);
      expect(capacity, 40);
    });

    test('unitCount multiplies a stage total; inactive rows are excluded', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(id: 1, rated: 10, hours: 8, unitCount: 3, stage: 'A'), // 240
        _machine(
          id: 2,
          rated: 100,
          hours: 24,
          unitCount: 5,
          stage: 'A',
          status: 'Under Maintenance',
        ), // excluded
        _machine(id: 3, rated: 20, hours: 8, stage: 'B'), // 160
      ]);
      expect(capacity, 160); // min(stage A 240, stage B 160)
    });

    test('a stage with no active machines stops the flow at zero', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(id: 1, rated: 10, hours: 8, stage: 'A'),
        _machine(
          id: 2,
          rated: 5,
          hours: 8,
          stage: 'B',
          status: 'Downtime',
        ),
      ]);
      expect(capacity, 0);
    });

    test('a stage still counts while it keeps one active machine', () {
      final capacity = CapacityService.computeMachineCapacity([
        _machine(id: 1, rated: 10, hours: 8, stage: 'A'),
        _machine(id: 2, rated: 5, hours: 8, stage: 'A', status: 'Downtime'),
        _machine(id: 3, rated: 20, hours: 8, stage: 'B'),
      ]);
      expect(capacity, 80);
    });

    test('empty list yields zero capacity', () {
      expect(CapacityService.computeMachineCapacity([]), 0);
    });
  });

  group('CapacityService.computeManpowerCapacity — slowest station', () {
    test('the slowest task station caps labour', () {
      final capacity = CapacityService.computeManpowerCapacity([
        _shift(workers: 5, hours: 8, perHour: 2), // 80
        _shift(workers: 3, hours: 6, perHour: 1), // 18
      ]);
      expect(capacity, 18);
    });

    test('a single station is its own capacity', () {
      expect(
        CapacityService.computeManpowerCapacity([
          _shift(workers: 5, hours: 8, perHour: 2),
        ]),
        80,
      );
    });

    test('no stations yields zero', () {
      expect(CapacityService.computeManpowerCapacity(const []), 0);
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
