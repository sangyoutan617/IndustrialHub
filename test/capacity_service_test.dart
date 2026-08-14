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
}
