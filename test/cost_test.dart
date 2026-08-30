import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/purchase_order.dart';
import 'package:industrial_hub/models/raw_material.dart';
import 'package:industrial_hub/models/supplier.dart';
import 'package:industrial_hub/services/mrp_service.dart';

RawMaterial _material({
  int id = 1,
  double stock = 100,
  double? unitCost,
}) {
  return RawMaterial(
    materialId: id,
    factoryId: 1,
    materialName: 'Material $id',
    currentStock: stock,
    unit: 'kg',
    unitCost: unitCost,
  );
}

PurchaseOrder _order({
  int poId = 1,
  int supplierId = 1,
  double quantity = 100,
  DateTime? orderDate,
  double? unitPrice,
}) {
  return PurchaseOrder(
    poId: poId,
    supplierId: supplierId,
    materialId: 1,
    quantity: quantity,
    orderDate: orderDate ?? DateTime(2026, 1, 1),
    status: PurchaseOrderStatus.processing,
    isSimulated: false,
    unitPrice: unitPrice,
  );
}

Supplier _supplier({
  int id = 1,
  int leadTimeDays = 5,
  double rating = 5,
}) {
  return Supplier(
    supplierId: id,
    supplierName: 'Supplier $id',
    materialId: 1,
    leadTimeDays: leadTimeDays,
    reliabilityRating: rating,
    isSimulated: false,
  );
}

void main() {
  group('MrpService.orderTotal', () {
    test('multiplies quantity by unit price', () {
      expect(MrpService.orderTotal(_order(quantity: 100, unitPrice: 2.5)), 250);
    });

    test('is null when no price was recorded', () {
      expect(MrpService.orderTotal(_order(quantity: 100)), isNull);
    });
  });

  group('MrpService.inventoryValue', () {
    test('sums stock times unit cost across materials', () {
      final value = MrpService.inventoryValue([
        _material(id: 1, stock: 100, unitCost: 3), // 300
        _material(id: 2, stock: 50, unitCost: 2), // 100
      ]);
      expect(value, 400);
    });

    test('materials without a cost contribute nothing', () {
      final value = MrpService.inventoryValue([
        _material(id: 1, stock: 100, unitCost: 3), // 300
        _material(id: 2, stock: 9999), // unknown cost -> 0
      ]);
      expect(value, 300);
    });

    test('empty list is zero', () {
      expect(MrpService.inventoryValue(const []), 0);
    });
  });

  group('MrpService.latestUnitPrice', () {
    test('returns the price from the most recent priced order', () {
      final price = MrpService.latestUnitPrice([
        _order(poId: 1, orderDate: DateTime(2026, 1, 1), unitPrice: 2.0),
        _order(poId: 2, orderDate: DateTime(2026, 3, 1), unitPrice: 2.5),
        _order(poId: 3, orderDate: DateTime(2026, 2, 1), unitPrice: 2.2),
      ]);
      expect(price, 2.5);
    });

    test('ignores orders with no recorded price', () {
      final price = MrpService.latestUnitPrice([
        _order(poId: 1, orderDate: DateTime(2026, 1, 1), unitPrice: 2.0),
        _order(poId: 2, orderDate: DateTime(2026, 5, 1)), // no price, newer
      ]);
      expect(price, 2.0);
    });

    test('is null when nothing has a price', () {
      expect(MrpService.latestUnitPrice([_order(), _order(poId: 2)]), isNull);
    });
  });

  group('MrpService.compareSuppliers price-aware ranking', () {
    test('breaks an equal-lead-time tie in favour of the cheaper price', () {
      // Both suppliers: 5-day lead, 5-star -> identical effective lead time.
      final suppliers = [_supplier(id: 1), _supplier(id: 2)];
      final history = [
        // Supplier 1 charges more; supplier 2 is cheaper.
        _order(poId: 1, supplierId: 1, unitPrice: 3.0),
        _order(poId: 2, supplierId: 2, unitPrice: 2.0),
      ];
      final rows = MrpService.compareSuppliers(
        suppliersForMaterial: suppliers,
        historyForMaterial: history,
      );
      expect(rows.first.supplier.supplierId, 2); // cheaper first
      expect(rows.first.unitPrice, 2.0);
      expect(rows.last.unitPrice, 3.0);
    });

    test('a supplier with a known price sorts ahead of one with none', () {
      final suppliers = [_supplier(id: 1), _supplier(id: 2)];
      final history = [
        // Only supplier 2 has a priced order; supplier 1's price is unknown.
        _order(poId: 1, supplierId: 2, unitPrice: 2.0),
      ];
      final rows = MrpService.compareSuppliers(
        suppliersForMaterial: suppliers,
        historyForMaterial: history,
      );
      expect(rows.first.supplier.supplierId, 2); // known price ranks first
      expect(rows.last.unitPrice, isNull);
    });

    test('effective lead time still dominates price', () {
      // Supplier 1 is faster but pricier; supplier 2 is slower but cheaper.
      final suppliers = [
        _supplier(id: 1, leadTimeDays: 3),
        _supplier(id: 2, leadTimeDays: 10),
      ];
      final history = [
        _order(poId: 1, supplierId: 1, unitPrice: 9.0),
        _order(poId: 2, supplierId: 2, unitPrice: 1.0),
      ];
      final rows = MrpService.compareSuppliers(
        suppliersForMaterial: suppliers,
        historyForMaterial: history,
      );
      expect(rows.first.supplier.supplierId, 1); // faster wins despite price
    });
  });
}
