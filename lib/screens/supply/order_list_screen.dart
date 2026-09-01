import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/purchase_order.dart';
import '../../services/mrp_service.dart';
import '../../services/material_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import 'order_form_screen.dart';
import 'purchase_order_detail_screen.dart';

class OrderListScreen extends StatefulWidget {
  final int factoryId;

  const OrderListScreen({super.key, required this.factoryId});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

enum _LoadState { loading, error, ready }

const _openStatuses = [
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
    final saved = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) =>
            OrderFormScreen(factoryId: widget.factoryId, order: order),
      ),
    );
    if (!mounted || saved == null) return;
    _load();
    if (order == null && saved is PurchaseOrder) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PurchaseOrderDetailScreen(
            factoryId: widget.factoryId,
            order: saved,
            materialName:
                _materialNames[saved.materialId] ?? 'Unknown material',
            supplierName:
                _supplierNames[saved.supplierId] ?? 'Unknown supplier',
          ),
        ),
      );
      if (!mounted) return;
      _load();
      return;
    }
    final poNumber = saved is PurchaseOrder ? ' ${formatPoNumber(saved.poId)}' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          order == null ? 'Purchase order$poNumber created' : 'Purchase order$poNumber updated',
        ),
      ),
    );
  }

  Future<void> _openDetail(PurchaseOrder order) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderDetailScreen(
          factoryId: widget.factoryId,
          order: order,
          materialName: _materialNames[order.materialId] ?? 'Unknown material',
          supplierName: _supplierNames[order.supplierId] ?? 'Unknown supplier',
        ),
      ),
    );
    if (!mounted || changed != true) return;
    _load();
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
        return ErrorState(
          message: 'Could not load purchase orders. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_orders.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No purchase orders yet',
                  subtitle: 'Create an order to start tracking deliveries.',
                  actionLabel: 'New order',
                  onAction: () => _openForm(),
                ),
              ],
            ),
          );
        }
        final filtered = _filteredOrders;
        return RefreshIndicator(
          onRefresh: _load,
          child: OrientationBuilder(
            builder: (context, orientation) {
              final isLandscape = orientation == Orientation.landscape;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  ),
                  if (filtered.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          message: 'No orders match this filter.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(8),
                      sliver: isLandscape
                          ? SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                childAspectRatio: 2.8,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) =>
                                    _buildOrderCard(filtered[index]),
                                childCount: filtered.length,
                              ),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) =>
                                    _buildOrderCard(filtered[index]),
                                childCount: filtered.length,
                              ),
                            ),
                    ),
                ],
              );
            },
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
    final total = MrpService.orderTotal(order);
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPoNumber(order.poId),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      materialName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$supplierName · ${formatUnits(order.quantity)}'
                      '${total != null ? ' · ${formatCurrency(total)}' : ''}',
                    ),
                    Text(
                      'Ordered ${formatDate(order.orderDate)}'
                      '${order.expectedDelivery != null ? ' · expected ${formatDate(order.expectedDelivery!)}' : ''}'
                      '${isOpen ? _relativeDeliveryText(order) : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(order.status),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  AppStatus _statusFor(String status) {
    switch (status) {
      case PurchaseOrderStatus.processing:
        return AppStatus.info;
      case PurchaseOrderStatus.shipped:
        return AppStatus.warning;
      case PurchaseOrderStatus.delivered:
        return AppStatus.success;
      case PurchaseOrderStatus.cancelled:
        return AppStatus.neutral;
      default:
        return AppStatus.neutral;
    }
  }

  Widget _statusChip(String status) {
    return StatusChip(label: status, status: _statusFor(status));
  }
}
