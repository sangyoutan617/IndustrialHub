import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/raw_material.dart';
import 'package:industrial_hub/services/mrp_service.dart';

RawMaterial _material({int id = 1, double stock = 100, double perUnit = 2}) {
  return RawMaterial(
    materialId: id,
    factoryId: 1,
    materialName: 'Material $id',
    currentStock: stock,
    unit: 'kg',
    consumptionPerUnit: perUnit,
  );
}

void main() {
  group('MrpService.computeProductionConsumption', () {
    test('multiplies each material rate by units produced', () {
      final consumption = MrpService.computeProductionConsumption([
        _material(id: 1, perUnit: 2),
        _material(id: 2, perUnit: 0.5),
      ], 10);
      expect(consumption, {1: 20.0, 2: 5.0});
    });

    test('omits materials with a zero consumption rate', () {
      final consumption = MrpService.computeProductionConsumption([
        _material(id: 1, perUnit: 2),
        _material(id: 2, perUnit: 0),
      ], 10);
      expect(consumption, {1: 20.0});
      expect(consumption.containsKey(2), isFalse);
    });

    test('zero units produced consumes nothing', () {
      final consumption = MrpService.computeProductionConsumption([
        _material(perUnit: 2),
      ], 0);
      expect(consumption, isEmpty);
    });

    test('empty material list yields an empty map', () {
      expect(MrpService.computeProductionConsumption(const [], 10), isEmpty);
    });
  });

  group('MrpService.insufficientMaterials', () {
    test('flags a material whose stock cannot cover the run', () {
      // Needs 2×60 = 120 but only 100 on hand.
      final short = MrpService.insufficientMaterials([
        _material(id: 1, stock: 100, perUnit: 2),
      ], 60);
      expect(short.map((m) => m.materialId), [1]);
    });

    test('does not flag a material with exactly enough stock', () {
      // Needs 2×50 = 100, has exactly 100.
      final short = MrpService.insufficientMaterials([
        _material(stock: 100, perUnit: 2),
      ], 50);
      expect(short, isEmpty);
    });

    test('returns only the short materials from a mixed list', () {
      final short = MrpService.insufficientMaterials([
        _material(id: 1, stock: 100, perUnit: 2), // needs 200 → short
        _material(id: 2, stock: 500, perUnit: 2), // needs 200 → ok
      ], 100);
      expect(short.map((m) => m.materialId), [1]);
    });
  });
}
