import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/purchase_order.dart';
import '../../services/material_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'order_form_screen.dart';

class OrderListScreen extends StatefulWidget {
  final int factoryId;

  const OrderListScreen({super.key, required this.factoryId});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

enum _LoadState { loading, error, ready }

const _pageSize = 20;

class _OrderListScreenState extends State<OrderListScreen> {
  final _materialService = MaterialService();
  final _supplierService = SupplierService();
  final _orderService = OrderService();

  _LoadState _state = _LoadState.loading;
  List<PurchaseOrder> _orders = [];
  Map<int, String> _materialNames = {};
  Map<int, String> _supplierNames = {};
  List<int> _materialIds = [];
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
      final materialIds = materials.map((m) => m.materialId).toList();
      final suppliers = await _supplierService.getSuppliersForMaterials(
        materialIds,
      );
      final orders = await _orderService.getOrdersPageForMaterials(
        materialIds,
        limit: _pageSize,
        offset: 0,
      );
      setState(() {
        _orders = orders;
        _materialIds = materialIds;
        _materialNames = {
          for (final m in materials) m.materialId: m.materialName,
        };
        _supplierNames = {
          for (final s in suppliers) s.supplierId: s.supplierName,
        };
        _hasMore = orders.length == _pageSize;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = await _orderService.getOrdersPageForMaterials(
        _materialIds,
        limit: _pageSize,
        offset: _orders.length,
      );
      setState(() {
        _orders = [..._orders, ...nextPage];
        _hasMore = nextPage.length == _pageSize;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load more orders.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(factoryId: widget.factoryId),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _advanceStatus(PurchaseOrder order, String newStatus) async {
    try {
      await _orderService.updateStatus(order.poId, newStatus);
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update order. Please try again.'),
        ),
      );
    }
  }

  Future<void> _receiveDelivery(PurchaseOrder order) async {
    final materialName = _materialNames[order.materialId] ?? 'this material';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Receive delivery?',
      message:
          'This adds ${order.quantity} to $materialName\'s stock and marks the order Delivered.',
      confirmLabel: 'Receive',
    );
    if (!confirmed) return;
    try {
      await _orderService.receiveDelivery(order);
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not receive delivery. Please try again.'),
        ),
      );
    }
  }

  Future<void> _cancel(PurchaseOrder order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel order?',
      message: 'This marks the order Cancelled. Stock is not affected.',
      confirmLabel: 'Cancel order',
    );
    if (!confirmed) return;
    await _advanceStatus(order, PurchaseOrderStatus.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase orders')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        if (_orders.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'No purchase orders yet.',
            actionLabel: 'New order',
            onAction: _openForm,
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _orders.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _orders.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _isLoadingMore
                        ? const CircularProgressIndicator()
                        : OutlinedButton(
                            onPressed: _loadMore,
                            child: const Text('Load more'),
                          ),
                  ),
                );
              }
              return _buildOrderCard(_orders[index]);
            },
          ),
        );
    }
  }

  Widget _buildOrderCard(PurchaseOrder order) {
    final materialName = _materialNames[order.materialId] ?? 'Unknown material';
    final supplierName = _supplierNames[order.supplierId] ?? 'Unknown supplier';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    materialName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _statusChip(order.status),
              ],
            ),
            Text('$supplierName · ${order.quantity} units'),
            Text(
              'Ordered ${_formatDate(order.orderDate)}'
              '${order.expectedDelivery != null ? ' · expected ${_formatDate(order.expectedDelivery!)}' : ''}',
            ),
            const SizedBox(height: 8),
            Row(children: _actionsFor(order)),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionsFor(PurchaseOrder order) {
    switch (order.status) {
      case PurchaseOrderStatus.pending:
        return [
          TextButton(
            onPressed: () =>
                _advanceStatus(order, PurchaseOrderStatus.processing),
            child: const Text('Start processing'),
          ),
          TextButton(
            onPressed: () => _cancel(order),
            child: const Text('Cancel'),
          ),
        ];
      case PurchaseOrderStatus.processing:
        return [
          TextButton(
            onPressed: () => _advanceStatus(order, PurchaseOrderStatus.shipped),
            child: const Text('Mark shipped'),
          ),
          TextButton(
            onPressed: () => _cancel(order),
            child: const Text('Cancel'),
          ),
        ];
      case PurchaseOrderStatus.shipped:
        return [
          FilledButton(
            onPressed: () => _receiveDelivery(order),
            child: const Text('Receive delivery'),
          ),
          TextButton(
            onPressed: () => _cancel(order),
            child: const Text('Cancel'),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _statusChip(String status) {
    final isCancelled = status == PurchaseOrderStatus.cancelled;
    final color = isCancelled
        ? Theme.of(context).colorScheme.error
        : AppColors.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCancelled
            ? color.withValues(alpha: 0.12)
            : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
