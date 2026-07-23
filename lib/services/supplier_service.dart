import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase_order.dart';
import '../models/supplier.dart';

class SupplierLeadTimeStats {
  final double actualAverageDays;
  final int deliveredCount;
  final double? onTimePercent;

  const SupplierLeadTimeStats({
    required this.actualAverageDays,
    required this.deliveredCount,
    required this.onTimePercent,
  });
}

class SupplierService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Supplier>> getSuppliersForMaterials(List<int> materialIds) async {
    if (materialIds.isEmpty) return [];
    final rows = await _client
        .from('suppliers')
        .select()
        .inFilter('material_id', materialIds)
        .order('supplier_name', ascending: true);
    return (rows as List)
        .map((row) => Supplier.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Supplier> createSupplier(
    Supplier supplier, {
    bool isSimulated = false,
  }) async {
    final row = await _client
        .from('suppliers')
        .insert({
          ...supplier.toInsertJson(),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    return Supplier.fromJson(row);
  }

  Future<Supplier> updateSupplier(int supplierId, Supplier supplier) async {
    final row = await _client
        .from('suppliers')
        .update({
          ...supplier.toInsertJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('supplier_id', supplierId)
        .select()
        .single();
    return Supplier.fromJson(row);
  }

  Future<void> deleteSupplier(int supplierId) async {
    await _client.from('suppliers').delete().eq('supplier_id', supplierId);
  }

  /// Actual (delivered_at - order_date) lead time per supplier, from their
  /// delivered orders — the "were they actually on time" counterpart to
  /// the supplier's self-declared lead_time_days.
  Future<Map<int, SupplierLeadTimeStats>> getActualLeadTimeStats(
    List<int> supplierIds,
  ) async {
    if (supplierIds.isEmpty) return {};

    final rows = await _client
        .from('purchase_orders')
        .select('supplier_id, order_date, expected_delivery, delivered_at')
        .inFilter('supplier_id', supplierIds)
        .eq('status', PurchaseOrderStatus.delivered)
        .not('delivered_at', 'is', null);

    final leadDaysBySupplier = <int, List<double>>{};
    final onTimeBySupplier = <int, List<bool>>{};

    for (final row in rows as List) {
      final map = row as Map<String, dynamic>;
      final supplierId = map['supplier_id'] as int;
      final orderDate = DateTime.parse(map['order_date'] as String);
      final deliveredAt = DateTime.parse(map['delivered_at'] as String);
      final leadDays = deliveredAt.difference(orderDate).inHours / 24;
      leadDaysBySupplier.putIfAbsent(supplierId, () => []).add(leadDays);

      final expectedDelivery = map['expected_delivery'] != null
          ? DateTime.parse(map['expected_delivery'] as String)
          : null;
      if (expectedDelivery != null) {
        onTimeBySupplier
            .putIfAbsent(supplierId, () => [])
            .add(!deliveredAt.isAfter(expectedDelivery));
      }
    }

    return {
      for (final entry in leadDaysBySupplier.entries)
        entry.key: SupplierLeadTimeStats(
          actualAverageDays:
              entry.value.fold<double>(0, (sum, v) => sum + v) /
              entry.value.length,
          deliveredCount: entry.value.length,
          onTimePercent: onTimeBySupplier[entry.key] == null
              ? null
              : onTimeBySupplier[entry.key]!.where((v) => v).length /
                    onTimeBySupplier[entry.key]!.length *
                    100,
        ),
    };
  }
}
