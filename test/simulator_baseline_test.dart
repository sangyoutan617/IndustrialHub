import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/machine.dart';
import 'package:industrial_hub/models/manpower.dart';
import 'package:industrial_hub/services/capacity_service.dart';

Machine _machine({
  required int id,
  required double rated,
  required double hours,
  required double uptime,
  String status = 'Active',
}) {
  return Machine(
    machineId: id,
    factoryId: 1,
    productId: 1,
    machineName: 'Machine $id',
    ratedOutputPerHour: rated,
    operatingHoursPerDay: hours,
    uptimePercent: uptime,
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
double _simMachineCapacity(SimulatorBaseline b, {int? machines, int? uptime}) {
  return (machines ?? b.activeMachines) *
      b.machineNameplate *
      ((uptime ?? b.uptimePercent) / 100);
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
        // Mirrors SeedService._seedMachines / _seedManpower exactly.
        final machines = [
          _machine(id: 1, rated: 50, hours: 16, uptime: 95),
          _machine(id: 2, rated: 40, hours: 16, uptime: 90),
          _machine(id: 3, rated: 100, hours: 16, uptime: 98),
          _machine(
            id: 4,
            rated: 20,
            hours: 8,
            uptime: 80,
            status: 'Under Maintenance',
          ),
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

        // Within the rounding the whole-number-only uptime field forces.
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
          _machine(id: 1, rated: 50, hours: 16, uptime: 95),
          _machine(id: 2, rated: 40, hours: 8, uptime: 90),
          _machine(id: 3, rated: 100, hours: 20, uptime: 98),
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

    test('inactive machines never drag the per-machine rate', () {
      final withIdleJunk = _snapshot([
        _machine(id: 1, rated: 100, hours: 16, uptime: 100),
        _machine(id: 2, rated: 1, hours: 1, uptime: 10, status: 'Retired'),
      ], const []);
      final activeOnly = _snapshot([
        _machine(id: 1, rated: 100, hours: 16, uptime: 100),
      ], const []);

      expect(
        SimulatorBaseline.from(withIdleJunk).machineNameplate,
        SimulatorBaseline.from(activeOnly).machineNameplate,
      );
      expect(SimulatorBaseline.from(withIdleJunk).uptimePercent, 100);
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
        _machine(id: 1, rated: 50, hours: 16, uptime: 100),
        _machine(id: 2, rated: 30, hours: 16, uptime: 100),
      ], const []);
      final baseline = SimulatorBaseline.from(snapshot);

      final atTwo = _simMachineCapacity(baseline, machines: 2);
      final atThree = _simMachineCapacity(baseline, machines: 3);

      expect(atThree - atTwo, closeTo(baseline.machineNameplate, 0.001));
      expect(_simMachineCapacity(baseline, machines: 0), 0);
    });

    test('uptime scales machine capacity linearly', () {
      final snapshot = _snapshot([
        _machine(id: 1, rated: 50, hours: 10, uptime: 100),
      ], const []);
      final baseline = SimulatorBaseline.from(snapshot);

      expect(_simMachineCapacity(baseline, uptime: 100), closeTo(500, 0.001));
      expect(_simMachineCapacity(baseline, uptime: 50), closeTo(250, 0.001));
      expect(_simMachineCapacity(baseline, uptime: 0), 0);
    });
  });

  group('SimulatorBaseline degenerate inputs', () {
    test('no machines at all: a zero rate, and uptime defaults to 100', () {
      final baseline = SimulatorBaseline.from(_snapshot(const [], const []));

      expect(baseline.machineNameplate, 0);
      expect(baseline.activeMachines, 0);
      expect(baseline.uptimePercent, 100);
      expect(baseline.workers, 0);
      expect(baseline.shiftHours, 0);
    });

    test('machines exist but none active: falls back to the whole fleet, so '
        'reactivating one still moves the number', () {
      final baseline = SimulatorBaseline.from(
        _snapshot([
          _machine(id: 1, rated: 50, hours: 16, uptime: 90, status: 'Retired'),
        ], const []),
      );

      expect(baseline.activeMachines, 0);
      expect(baseline.machineNameplate, closeTo(800, 0.001));
      expect(_simMachineCapacity(baseline, machines: 1), closeTo(720, 0.001));
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
