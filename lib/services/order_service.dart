import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase_order.dart';

class OrderService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<PurchaseOrder>> getOrdersForMaterials(
    List<int> materialIds,
  ) async {
    if (materialIds.isEmpty) return [];
    final rows = await _client
        .from('purchase_orders')
        .select()
        .inFilter('material_id', materialIds)
        .order('order_date', ascending: false);
    return (rows as List)
        .map((row) => PurchaseOrder.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Paginated variant for the purchase-orders list screen, which otherwise
  /// fetches every order for the factory up front. Other callers (material
  /// forecast, supplier lead-time stats) still need the full set and keep
  /// using [getOrdersForMaterials].
  Future<List<PurchaseOrder>> getOrdersPageForMaterials(
    List<int> materialIds, {
    required int limit,
    required int offset,
  }) async {
    if (materialIds.isEmpty) return [];
    final rows = await _client
        .from('purchase_orders')
        .select()
        .inFilter('material_id', materialIds)
        .order('order_date', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .map((row) => PurchaseOrder.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<PurchaseOrder> createOrder(
    PurchaseOrder order, {
    bool isSimulated = false,
  }) async {
    final row = await _client
        .from('purchase_orders')
        .insert({
          ...order.toInsertJson(),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    return PurchaseOrder.fromJson(row);
  }

  Future<PurchaseOrder> updateStatus(int poId, String status) async {
    final row = await _client
        .from('purchase_orders')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', poId)
        .select()
        .single();
    return PurchaseOrder.fromJson(row);
  }

  Future<void> deleteOrder(int poId) async {
    await _client.from('purchase_orders').delete().eq('po_id', poId);
  }

  Future<void> receiveDelivery(PurchaseOrder order) async {
    final material = await _client
        .from('raw_materials')
        .select('current_stock')
        .eq('material_id', order.materialId)
        .single();
    final currentStock = (material['current_stock'] as num).toDouble();

    await _client
        .from('raw_materials')
        .update({
          'current_stock': currentStock + order.quantity,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('material_id', order.materialId);

    await _client
        .from('purchase_orders')
        .update({
          'status': PurchaseOrderStatus.delivered,
          'delivered_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', order.poId);
  }
}
