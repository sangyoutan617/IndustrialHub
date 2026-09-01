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
