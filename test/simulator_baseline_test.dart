import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/machine.dart';
import 'package:industrial_hub/models/manpower.dart';
import 'package:industrial_hub/services/capacity_service.dart';

Machine _machine({
  required int id,
  required double rated,
  required double hours,
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

double _machineCapacityOf(SimulatorBaseline b) =>
    b.machines * b.machineHours * b.machineRate;

double _manpowerCapacityOf(SimulatorBaseline b) =>
    b.workers * b.shiftHours * b.outputPerWorkerHour;

void main() {
  group('SimulatorBaseline.from', () {
    test('prefills the slowest machine stage', () {
      final baseline = SimulatorBaseline.from(
        _snapshot([
          _machine(id: 1, rated: 100, hours: 10, stage: 'Extrusion'),
          _machine(id: 2, rated: 50, hours: 10, stage: 'Packaging'),
        ], const []),
      );

      expect(baseline.machines, 1);
      expect(baseline.machineHours, 10);
      expect(baseline.machineRate, 50);
      expect(_machineCapacityOf(baseline), 500);
    });

    test('parallel machines in a stage collapse to one count and rate', () {
      final baseline = SimulatorBaseline.from(
        _snapshot([
          _machine(id: 1, rated: 30, hours: 16, stage: 'Fill'),
          _machine(id: 2, rated: 30, hours: 16, unitCount: 2, stage: 'Fill'),
          _machine(id: 3, rated: 200, hours: 16, stage: 'Mix'),
        ], const []),
      );

      expect(baseline.machines, 3);
      expect(baseline.machineHours, 16);
      expect(baseline.machineRate, 30);
      expect(_machineCapacityOf(baseline), 1440);
    });

    test('prefills the slowest labour station', () {
      final baseline = SimulatorBaseline.from(
        _snapshot(const [], [
          _shift(id: 1, workers: 12, hours: 8, perHour: 9),
          _shift(id: 2, workers: 5, hours: 8, perHour: 8),
        ]),
      );

      expect(baseline.workers, 5);
      expect(baseline.shiftHours, 8);
      expect(baseline.outputPerWorkerHour, 8);
      expect(_manpowerCapacityOf(baseline), 320);
    });

    test('inactive machines are ignored', () {
      final baseline = SimulatorBaseline.from(
        _snapshot([
          _machine(id: 1, rated: 100, hours: 10, stage: 'A'),
          _machine(
            id: 2,
            rated: 1,
            hours: 1,
            stage: 'B',
            status: 'Under Maintenance',
          ),
        ], const []),
      );

      expect(baseline.machines, 1);
      expect(_machineCapacityOf(baseline), 1000);
    });

    test('no machines and no shifts yields zeros', () {
      final baseline = SimulatorBaseline.from(_snapshot(const [], const []));

      expect(baseline.machines, 0);
      expect(baseline.machineHours, 0);
      expect(baseline.machineRate, 0);
      expect(baseline.workers, 0);
      expect(baseline.shiftHours, 0);
      expect(baseline.outputPerWorkerHour, 0);
    });
  });
}
