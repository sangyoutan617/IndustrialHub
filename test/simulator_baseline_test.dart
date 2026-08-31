import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/machine.dart';
import 'package:industrial_hub/models/manpower.dart';
import 'package:industrial_hub/services/capacity_service.dart';

Machine _machine({
  required int id,
  required double rated,
  required double hours,
  int unitCount = 1,
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
    status: status,
    isSimulated: false,
  );
}

Manpower _shift({
  required int id,
  required int workers,
  required double hours,
  required double perHour,
}) {
  return Manpower(
    manpowerId: id,
    factoryId: 1,
    productId: 1,
    shiftName: 'Shift $id',
    workerCount: workers,
    shiftHours: hours,
    outputPerWorkerHour: perHour,
    isSimulated: false,
  );
}

CapacitySnapshot _snapshot(List<Machine> machines, List<Manpower> shifts) {
  final machineCapacity = CapacityService.computeMachineCapacity(machines);
  final manpowerCapacity = CapacityService.computeManpowerCapacity(shifts);
  return CapacitySnapshot(
    machines: machines,
    shifts: shifts,
    machineCapacity: machineCapacity,
    manpowerCapacity: manpowerCapacity,
    effectiveCapacity: machineCapacity < manpowerCapacity
        ? machineCapacity
        : manpowerCapacity,
    bottleneckResource: CapacityService.bottleneckResourceFor(
      machineCapacity,
      manpowerCapacity,
    ),
  );
}

/// What the simulator screen itself computes from the baseline, mirrored here
/// so a change to that arithmetic has to be made in both places deliberately.
double _simMachineCapacity(SimulatorBaseline b, {int? machines}) {
  return (machines ?? b.activeMachines) * b.machineNameplate;
}

double _simManpowerCapacity(SimulatorBaseline b, {int? workers, int? hours}) {
  return (workers ?? b.workers) *
      (hours ?? b.shiftHours) *
      b.outputPerWorkerHour;
}

void main() {
  group('SimulatorBaseline reproduces the real ceiling at rest', () {
    test(
      'the app\'s own demo fleet — the case the old averaging got 31% wrong',
      () {
        // Mirrors SeedService._seedMachines / _seedManpower exactly —
        // including the Packaging Unit being a group of 3 identical machines.
        final machines = [
          _machine(id: 1, rated: 50, hours: 16),
          _machine(id: 2, rated: 40, hours: 16),
          _machine(id: 3, rated: 100, hours: 16, unitCount: 3),
          _machine(id: 4, rated: 20, hours: 8, status: 'Under Maintenance'),
        ];
        final shifts = [
          _shift(id: 1, workers: 15, hours: 8, perHour: 5),
          _shift(id: 2, workers: 8, hours: 8, perHour: 4),
        ];
        final snapshot = _snapshot(machines, shifts);
        final baseline = SimulatorBaseline.from(snapshot);

        expect(baseline.activeMachines, 3);
        expect(baseline.workers, 23);
        expect(baseline.shiftHours, 8);

        expect(
          _simMachineCapacity(baseline),
          closeTo(snapshot.machineCapacity, snapshot.machineCapacity * 0.01),
        );
        expect(
          _simManpowerCapacity(baseline),
          closeTo(snapshot.manpowerCapacity, 0.001),
        );
      },
    );

    test(
      'a fleet whose running hours vary — where product-of-means diverges',
      () {
        final machines = [
          _machine(id: 1, rated: 50, hours: 16),
          _machine(id: 2, rated: 40, hours: 8),
          _machine(id: 3, rated: 100, hours: 20),
        ];
        final snapshot = _snapshot(machines, const []);
        final baseline = SimulatorBaseline.from(snapshot);

        // mean(rated) × mean(hours) would be 63.33 × 14.67 = 928.9, while
        // mean(rated × hours) is 1040 — the covariance the old code dropped.
        expect(baseline.machineNameplate, closeTo(1040, 0.01));
        expect(
          _simMachineCapacity(baseline),
          closeTo(snapshot.machineCapacity, snapshot.machineCapacity * 0.01),
        );
      },
    );

    test('a grouped row still reproduces the real ceiling at rest', () {
      // One row of 4 identical machines + one single. machineCapacity is
      // 50×16×4 + 30×16 = 3200 + 480 = 3680, over 2 rows.
      final snapshot = _snapshot([
        _machine(id: 1, rated: 50, hours: 16, unitCount: 4),
        _machine(id: 2, rated: 30, hours: 16),
      ], const []);
      final baseline = SimulatorBaseline.from(snapshot);

      expect(snapshot.machineCapacity, 3680);
      expect(baseline.activeMachines, 2);
      expect(baseline.machineNameplate, closeTo(1840, 0.01));
      expect(
        _simMachineCapacity(baseline),
        closeTo(snapshot.machineCapacity, snapshot.machineCapacity * 0.01),
      );
    });

    test('inactive machines never drag the per-machine rate', () {
      final withIdleJunk = _snapshot([
        _machine(id: 1, rated: 100, hours: 16),
        _machine(id: 2, rated: 1, hours: 1, status: 'Retired'),
      ], const []);
      final activeOnly = _snapshot([
        _machine(id: 1, rated: 100, hours: 16),
      ], const []);

      expect(
        SimulatorBaseline.from(withIdleJunk).machineNameplate,
        SimulatorBaseline.from(activeOnly).machineNameplate,
      );
    });

    test('shift hours are worker-weighted, not counted once per shift', () {
      // A 100-worker 12h shift and a 1-worker 4h shift: the plain mean would
      // say 8h, which is nowhere near where the worker-hours actually are.
      final snapshot = _snapshot(const [], [
        _shift(id: 1, workers: 100, hours: 12, perHour: 5),
        _shift(id: 2, workers: 1, hours: 4, perHour: 5),
      ]);
      final baseline = SimulatorBaseline.from(snapshot);

      expect(baseline.workers, 101);
      expect(baseline.shiftHours, 12); // 1204 worker-hours / 101 workers
      expect(
        _simManpowerCapacity(baseline),
        closeTo(snapshot.manpowerCapacity, snapshot.manpowerCapacity * 0.01),
      );
    });
  });

  group('SimulatorBaseline extrapolation', () {
    test('an added machine is worth what an average active one is worth', () {
      final snapshot = _snapshot([
        _machine(id: 1, rated: 50, hours: 16),
        _machine(id: 2, rated: 30, hours: 16),
      ], const []);
      final baseline = SimulatorBaseline.from(snapshot);

      final atTwo = _simMachineCapacity(baseline, machines: 2);
      final atThree = _simMachineCapacity(baseline, machines: 3);

      expect(atThree - atTwo, closeTo(baseline.machineNameplate, 0.001));
      expect(_simMachineCapacity(baseline, machines: 0), 0);
    });
  });

  group('SimulatorBaseline degenerate inputs', () {
    test('no machines at all: a zero rate', () {
      final baseline = SimulatorBaseline.from(_snapshot(const [], const []));

      expect(baseline.machineNameplate, 0);
      expect(baseline.activeMachines, 0);
      expect(baseline.workers, 0);
      expect(baseline.shiftHours, 0);
    });

    test('machines exist but none active: falls back to the whole fleet, so '
        'reactivating one still moves the number', () {
      final baseline = SimulatorBaseline.from(
        _snapshot([
          _machine(id: 1, rated: 50, hours: 16, status: 'Retired'),
        ], const []),
      );

      expect(baseline.activeMachines, 0);
      expect(baseline.machineNameplate, closeTo(800, 0.001));
      expect(_simMachineCapacity(baseline, machines: 1), closeTo(800, 0.001));
    });

    test('shifts staffed by nobody do not divide by zero', () {
      final baseline = SimulatorBaseline.from(
        _snapshot(const [], [_shift(id: 1, workers: 0, hours: 8, perHour: 5)]),
      );

      expect(baseline.workers, 0);
      expect(baseline.shiftHours, 8);
      expect(baseline.outputPerWorkerHour, closeTo(5, 0.001));
    });
  });
}
