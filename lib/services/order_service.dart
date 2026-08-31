import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase_order.dart';
import 'data_event_service.dart';

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

  /// Best-effort preview of the PO number a new order would likely get —
  /// current max `po_id` + 1. This is NOT reserved and NOT guaranteed: a
  /// concurrent insert from another device can still take it first, so the
  /// real number only ever comes from the row [createOrder] actually
  /// returns. Purely a "here's roughly what to expect" preview shown before
  /// saving. Returns 1 when there are no orders yet.
  Future<int> getNextPoIdPreview() async {
    final rows = await _client
        .from('purchase_orders')
        .select('po_id')
        .order('po_id', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return 1;
    return (list.first['po_id'] as int) + 1;
  }

  Future<PurchaseOrder> createOrder(
    PurchaseOrder order, {
    bool isSimulated = false,
    int? factoryId,
  }) async {
    final row = await _client
        .from('purchase_orders')
        .insert({
          ...order.toInsertJson(),
          if (isSimulated) 'is_simulated': true,
        })
        .select()
        .single();
    final result = PurchaseOrder.fromJson(row);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.order,
      );
    }
    return result;
  }

  Future<PurchaseOrder> updateOrder(
    int poId,
    PurchaseOrder order, {
    int? factoryId,
  }) async {
    final row = await _client
        .from('purchase_orders')
        .update({
          ...order.toInsertJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', poId)
        .select()
        .single();
    final result = PurchaseOrder.fromJson(row);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.order,
      );
    }
    return result;
  }

  Future<PurchaseOrder> updateStatus(
    int poId,
    String status, {
    int? factoryId,
  }) async {
    final row = await _client
        .from('purchase_orders')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', poId)
        .select()
        .single();
    final result = PurchaseOrder.fromJson(row);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.order,
      );
    }
    return result;
  }

  Future<void> deleteOrder(int poId, {int? factoryId}) async {
    await _client.from('purchase_orders').delete().eq('po_id', poId);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.order,
      );
    }
  }

  /// Marks the order delivered as of a specific past [deliveredAt] date and
  /// adds its quantity to the material's stock — used only for seeding
  /// historical demo data. [receiveDelivery] always stamps `delivered_at` as
  /// *today* (correct for a real live delivery), which would make a 60-day-
  /// old backfilled order look like it just arrived; this sets the date
  /// directly instead. Not idempotent/transactional like [receiveDelivery] —
  /// fine for one-time seeding, not for a live user-facing action.
  Future<void> markDeliveredAt(
    PurchaseOrder order,
    DateTime deliveredAt, {
    int? factoryId,
  }) async {
    await _client
        .from('purchase_orders')
        .update({
          'status': PurchaseOrderStatus.delivered,
          'delivered_at': deliveredAt.toIso8601String().substring(0, 10),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('po_id', order.poId);
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.order,
      );
    }
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
  Future<void> receiveDelivery(PurchaseOrder order, {int? factoryId}) async {
    try {
      await _client.rpc('receive_delivery', params: {'p_po_id': order.poId});
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      await _receiveDeliveryFallback(order);
    }
    if (factoryId != null) {
      DataEventService.instance.notifyChanged(
        factoryId: factoryId,
        source: DataChangeSource.order,
      );
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
