import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/bom_entry.dart';
import 'package:industrial_hub/models/raw_material.dart';
import 'package:industrial_hub/services/mrp_service.dart';

RawMaterial _material({int id = 1, double stock = 100}) {
  return RawMaterial(
    materialId: id,
    factoryId: 1,
    materialName: 'Material $id',
    currentStock: stock,
    unit: 'kg',
  );
}

BomEntry _bomEntry({int productId = 1, int materialId = 1, double perUnit = 2}) {
  return BomEntry(
    productId: productId,
    materialId: materialId,
    quantityPerUnit: perUnit,
  );
}

void main() {
  group('MrpService.computeProductionConsumption', () {
    test('multiplies each BOM line rate by units produced', () {
      final consumption = MrpService.computeProductionConsumption([
        _bomEntry(materialId: 1, perUnit: 2),
        _bomEntry(materialId: 2, perUnit: 0.5),
      ], 10);
      expect(consumption, {1: 20.0, 2: 5.0});
    });

    test('omits BOM lines with a zero rate', () {
      final consumption = MrpService.computeProductionConsumption([
        _bomEntry(materialId: 1, perUnit: 2),
        _bomEntry(materialId: 2, perUnit: 0),
      ], 10);
      expect(consumption, {1: 20.0});
      expect(consumption.containsKey(2), isFalse);
    });

    test('zero units produced consumes nothing', () {
      final consumption = MrpService.computeProductionConsumption([
        _bomEntry(perUnit: 2),
      ], 0);
      expect(consumption, isEmpty);
    });

    test('empty bill of materials yields an empty map', () {
      expect(MrpService.computeProductionConsumption(const [], 10), isEmpty);
    });
  });

  group('MrpService.insufficientMaterials', () {
    test('flags a material whose stock cannot cover the run', () {
      // Needs 2×60 = 120 but only 100 on hand.
      final short = MrpService.insufficientMaterials(
        materials: [_material(id: 1, stock: 100)],
        bom: [_bomEntry(materialId: 1, perUnit: 2)],
        unitsProduced: 60,
      );
      expect(short.map((m) => m.materialId), [1]);
    });

    test('does not flag a material with exactly enough stock', () {
      // Needs 2×50 = 100, has exactly 100.
      final short = MrpService.insufficientMaterials(
        materials: [_material(stock: 100)],
        bom: [_bomEntry(perUnit: 2)],
        unitsProduced: 50,
      );
      expect(short, isEmpty);
    });

    test('returns only the short materials from a mixed list', () {
      final short = MrpService.insufficientMaterials(
        materials: [
          _material(id: 1, stock: 100), // needs 200 → short
          _material(id: 2, stock: 500), // needs 200 → ok
        ],
        bom: [
          _bomEntry(materialId: 1, perUnit: 2),
          _bomEntry(materialId: 2, perUnit: 2),
        ],
        unitsProduced: 100,
      );
      expect(short.map((m) => m.materialId), [1]);
    });

    test('a material with no BOM line is never flagged, regardless of stock', () {
      final short = MrpService.insufficientMaterials(
        materials: [_material(id: 1, stock: 0)],
        bom: const [],
        unitsProduced: 100,
      );
      expect(short, isEmpty);
    });
  });
}
