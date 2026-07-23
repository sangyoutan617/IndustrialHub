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

  Future<PurchaseOrder> updateOrder(int poId, PurchaseOrder order) async {
    final row = await _client
        .from('purchase_orders')
        .update({
          ...order.toInsertJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', poId)
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

  /// Marks the order delivered and adds its quantity to the material's
  /// stock. Goes through the `receive_delivery` RPC so both writes happen
  /// in one transaction and a repeat call on an already-delivered order
  /// is a no-op (idempotent — a double tap can't double-count stock).
  ///
  /// Falls back to the old two-step read-then-write only when the RPC
  /// genuinely doesn't exist yet (pre-migration database) — any other
  /// Postgrest failure (RLS denial, constraint violation) is a real error
  /// and should surface as one rather than silently degrading.
  Future<void> receiveDelivery(PurchaseOrder order) async {
    try {
      await _client.rpc('receive_delivery', params: {'p_po_id': order.poId});
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      await _receiveDeliveryFallback(order);
    }
  }

  /// Non-transactional fallback used only when the `receive_delivery` RPC
  /// hasn't been created yet. Updates the order's status first, filtered
  /// to orders that aren't already closed, so a repeat call (or a double
  /// tap racing the first request) finds no matching row the second time
  /// and skips the stock update — mirroring the RPC's idempotency instead
  /// of double-counting stock on a retry.
  Future<void> _receiveDeliveryFallback(PurchaseOrder order) async {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final updated = await _client
        .from('purchase_orders')
        .update({
          'status': PurchaseOrderStatus.delivered,
          'delivered_at': today,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', order.poId)
        .not(
          'status',
          'in',
          '(${PurchaseOrderStatus.delivered},${PurchaseOrderStatus.cancelled})',
        )
        .select('po_id');
    if ((updated as List).isEmpty) return;

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
  }
}
