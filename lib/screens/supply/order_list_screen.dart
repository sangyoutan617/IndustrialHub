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

const _openStatuses = [
  PurchaseOrderStatus.pending,
  PurchaseOrderStatus.processing,
  PurchaseOrderStatus.shipped,
];

class _OrderListScreenState extends State<OrderListScreen> {
  final _materialService = MaterialService();
  final _supplierService = SupplierService();
  final _orderService = OrderService();

  _LoadState _state = _LoadState.loading;
  List<PurchaseOrder> _orders = [];
  Map<int, String> _materialNames = {};
  Map<int, String> _supplierNames = {};
  String? _statusFilter;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
      final materialIds = materials.map((m) => m.materialId).toList();
      final suppliers = await _supplierService.getSuppliersForMaterials(
        materialIds,
      );
      final orders = await _orderService.getOrdersForMaterials(materialIds);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _orders = orders;
        _materialNames = {
          for (final m in materials) m.materialId: m.materialName,
        };
        _supplierNames = {
          for (final s in suppliers) s.supplierId: s.supplierName,
        };
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load orders: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  List<PurchaseOrder> get _filteredOrders {
    if (_statusFilter == null) return _orders;
    return _orders.where((o) => o.status == _statusFilter).toList();
  }

  Future<void> _openForm({PurchaseOrder? order}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            OrderFormScreen(factoryId: widget.factoryId, order: order),
      ),
    );
    if (!mounted) return;
    if (saved == true) _load();
  }

  Future<void> _advanceStatus(PurchaseOrder order, String newStatus) async {
    try {
      await _orderService.updateStatus(order.poId, newStatus);
      if (!mounted) return;
      _load();
    } catch (e) {
      debugPrint('supply: failed to update order status: $e');
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
      if (!mounted) return;
      _load();
    } catch (e) {
      debugPrint('supply: failed to receive delivery: $e');
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

  Future<void> _deletePermanently(PurchaseOrder order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete order permanently?',
      message: 'This removes the cancelled order from history for good.',
    );
    if (!confirmed) return;
    try {
      await _orderService.deleteOrder(order.poId);
      if (!mounted) return;
      _load();
    } catch (e) {
      debugPrint('supply: failed to delete order: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete order. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase orders')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
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
            onAction: () => _openForm(),
          );
        }
        final filtered = _filteredOrders;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _statusFilter == null,
                      onSelected: (_) => setState(() => _statusFilter = null),
                    ),
                    for (final status in PurchaseOrderStatus.all)
                      ChoiceChip(
                        label: Text(status),
                        selected: _statusFilter == status,
                        onSelected: (_) =>
                            setState(() => _statusFilter = status),
                      ),
                  ],
                ),
              ),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    message: 'No orders match this filter.',
                  ),
                )
              else
                for (final order in filtered) _buildOrderCard(order),
            ],
          ),
        );
    }
  }

  String _relativeDeliveryText(PurchaseOrder order) {
    final expected = order.expectedDelivery;
    if (expected == null) return '';
    final today = DateTime.now();
    final days = DateTime(
      expected.year,
      expected.month,
      expected.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days > 0) return ' · arriving in $days day${days == 1 ? '' : 's'}';
    if (days == 0) return ' · arriving today';
    return ' · overdue by ${-days} day${-days == 1 ? '' : 's'}';
  }

  Widget _buildOrderCard(PurchaseOrder order) {
    final materialName = _materialNames[order.materialId] ?? 'Unknown material';
    final supplierName = _supplierNames[order.supplierId] ?? 'Unknown supplier';
    final isOpen = _openStatuses.contains(order.status);
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
              '${order.expectedDelivery != null ? ' · expected ${_formatDate(order.expectedDelivery!)}' : ''}'
              '${isOpen ? _relativeDeliveryText(order) : ''}',
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
            onPressed: () => _openForm(order: order),
            child: const Text('Edit'),
          ),
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
      case PurchaseOrderStatus.cancelled:
        return [
          TextButton(
            onPressed: () => _deletePermanently(order),
            child: const Text('Delete permanently'),
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
