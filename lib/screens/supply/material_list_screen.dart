import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/purchase_order.dart';
import '../../models/raw_material.dart';
import '../../services/capacity_service.dart';
import '../../services/material_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'material_form_screen.dart';
import 'order_list_screen.dart';
import 'supplier_list_screen.dart';

const _incomingStatuses = {
  PurchaseOrderStatus.pending,
  PurchaseOrderStatus.processing,
  PurchaseOrderStatus.shipped,
};

/// Projected day (from now) that stock hits zero, given a constant burn
/// rate and a set of incoming deliveries. Walks each delivery in arrival
/// order, checking whether the burn would zero out stock before that
/// delivery lands; the first such gap is the real stock-out day. Returns
/// null if stock never hits zero within [horizonDays].
double? _projectedStockOutDay({
  required double currentStock,
  required double burnRatePerDay,
  required List<(double quantity, double arrivalDay)> incoming,
  double horizonDays = 90,
}) {
  if (burnRatePerDay <= 0) return null;

  final events = List<(double, double)>.from(incoming)
    ..sort((a, b) => a.$2.compareTo(b.$2));

  var balance = currentStock;
  var day = 0.0;
  for (final (quantity, arrivalDay) in events) {
    final clampedArrival = arrivalDay < day ? day : arrivalDay;
    if (clampedArrival > horizonDays) break;
    final elapsed = clampedArrival - day;
    final daysToZero = balance / burnRatePerDay;
    if (daysToZero <= elapsed) {
      return day + daysToZero;
    }
    balance -= burnRatePerDay * elapsed;
    balance += quantity;
    day = clampedArrival;
  }

  final daysToZero = balance / burnRatePerDay;
  final finalDay = day + daysToZero;
  return finalDay <= horizonDays ? finalDay : null;
}

class _MaterialRisk {
  final RawMaterial material;
  final double? burnRatePerDay;
  final double? daysOfCover;
  final double? projectedStockOutDay;
  final DateTime? stockOutDate;
  final double? minSupplierLeadDays;
  final PurchaseOrder? coveringOrder;
  final int? coveringOrderArrivalDays;

  _MaterialRisk({
    required this.material,
    this.burnRatePerDay,
    this.daysOfCover,
    this.projectedStockOutDay,
    this.stockOutDate,
    this.minSupplierLeadDays,
    this.coveringOrder,
    this.coveringOrderArrivalDays,
  });

  /// Incoming-aware: a delivery already on the way can push this back past
  /// the reorder threshold even though the raw burn-down alone would not.
  bool get needsReorder =>
      projectedStockOutDay != null &&
      minSupplierLeadDays != null &&
      projectedStockOutDay! <= minSupplierLeadDays!;

  bool get hasSupplier => minSupplierLeadDays != null;

  /// True when the raw burn-down (ignoring incoming deliveries) would have
  /// triggered a reorder, but an incoming delivery covers it instead.
  bool get isCoveredByIncoming =>
      coveringOrder != null &&
      !needsReorder &&
      daysOfCover != null &&
      minSupplierLeadDays != null &&
      daysOfCover! <= minSupplierLeadDays!;
}

class MaterialListScreen extends StatefulWidget {
  final int factoryId;

  const MaterialListScreen({super.key, required this.factoryId});

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

enum _LoadState { loading, error, ready }

class _MaterialListScreenState extends State<MaterialListScreen> {
  final _materialService = MaterialService();
  final _supplierService = SupplierService();
  final _capacityService = CapacityService();
  final _orderService = OrderService();

  _LoadState _state = _LoadState.loading;
  List<_MaterialRisk> _risks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MaterialListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryId != widget.factoryId) _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
      final materialIds = materials.map((m) => m.materialId).toList();
      final suppliers = await _supplierService.getSuppliersForMaterials(
        materialIds,
      );
      final orders = await _orderService.getOrdersForMaterials(materialIds);
      final snapshot = await _capacityService.getSnapshot(widget.factoryId);
      final leadTimeStats = await _supplierService.getActualLeadTimeStats(
        suppliers.map((s) => s.supplierId).toList(),
      );

      // Reorder alerts use the worse of the supplier's promised lead time
      // and their actual average — a habitually-late supplier shouldn't get
      // the benefit of their own claim.
      final leadTimeByMaterial = <int, double>{};
      for (final supplier in suppliers) {
        final materialId = supplier.materialId;
        if (materialId == null) continue;
        final actualAverage = leadTimeStats[supplier.supplierId]?.actualAverageDays;
        final effectiveLeadDays = actualAverage == null
            ? supplier.leadTimeDays.toDouble()
            : (supplier.leadTimeDays > actualAverage
                  ? supplier.leadTimeDays.toDouble()
                  : actualAverage);
        final existing = leadTimeByMaterial[materialId];
        if (existing == null || effectiveLeadDays < existing) {
          leadTimeByMaterial[materialId] = effectiveLeadDays;
        }
      }

      final now = DateTime.now();
      final risks = materials.map((material) {
        final burnRate = snapshot.effectiveCapacity > 0
            ? material.consumptionPerUnit * snapshot.effectiveCapacity
            : null;
        final daysOfCover = (burnRate != null && burnRate > 0)
            ? material.currentStock / burnRate
            : null;
        final stockOutDate = daysOfCover != null
            ? DateTime.now().add(Duration(days: daysOfCover.floor()))
            : null;

        final incomingOrders =
            orders
                .where(
                  (o) =>
                      o.materialId == material.materialId &&
                      _incomingStatuses.contains(o.status) &&
                      o.expectedDelivery != null,
                )
                .toList()
              ..sort((a, b) => a.expectedDelivery!.compareTo(b.expectedDelivery!));

        double? projectedStockOutDay;
        DateTime? projectedStockOutDate;
        if (burnRate != null && burnRate > 0) {
          final incoming = [
            for (final o in incomingOrders)
              (
                o.quantity,
                o.expectedDelivery!
                    .difference(now)
                    .inDays
                    .toDouble()
                    .clamp(0.0, double.infinity),
              ),
          ];
          projectedStockOutDay = _projectedStockOutDay(
            currentStock: material.currentStock,
            burnRatePerDay: burnRate,
            incoming: incoming,
          );
          projectedStockOutDate = projectedStockOutDay != null
              ? now.add(Duration(days: projectedStockOutDay.floor()))
              : null;
        }

        final coveringOrder = incomingOrders.isEmpty
            ? null
            : incomingOrders.first;
        final coveringOrderArrivalDays = coveringOrder?.expectedDelivery!
            .difference(now)
            .inDays
            .clamp(0, 1 << 30);

        return _MaterialRisk(
          material: material,
          burnRatePerDay: burnRate,
          daysOfCover: daysOfCover,
          projectedStockOutDay: projectedStockOutDay,
          stockOutDate: projectedStockOutDate ?? stockOutDate,
          minSupplierLeadDays: leadTimeByMaterial[material.materialId],
          coveringOrder: coveringOrder,
          coveringOrderArrivalDays: coveringOrderArrivalDays,
        );
      }).toList();

      setState(() {
        _risks = risks;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openForm({RawMaterial? material}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MaterialFormScreen(factoryId: widget.factoryId, material: material),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(RawMaterial material) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove material?',
      message:
          'This removes "${material.materialName}" permanently. This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      await _materialService.deleteMaterial(material.materialId);
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete material. Please try again.'),
        ),
      );
    }
  }

  Future<void> _navigateAndRefresh(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final scheme = Theme.of(context).colorScheme;
    final reorderCount = _risks.where((r) => r.needsReorder).length;
    final mostUrgent = _risks.where((r) => r.needsReorder).isEmpty
        ? null
        : (_risks.where((r) => r.needsReorder).toList()
            ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!))).first;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (mostUrgent != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.primaryDark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reorder now — ${mostUrgent.daysOfCover!.toStringAsFixed(0)} days cover, '
                      '${mostUrgent.minSupplierLeadDays!.toStringAsFixed(1)} day lead',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryStat(
                    'Materials',
                    _risks.length.toString(),
                    scheme.primary,
                  ),
                  _summaryStat(
                    'Reorder now',
                    reorderCount.toString(),
                    AppColors.primaryDark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Suppliers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigateAndRefresh(
                SupplierListScreen(factoryId: widget.factoryId),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Purchase orders'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _navigateAndRefresh(
                OrderListScreen(factoryId: widget.factoryId),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Raw materials', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_risks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.inventory_outlined,
                message:
                    'No materials yet. Add one to start tracking supply risk.',
              ),
            )
          else
            for (final risk in _risks) _buildMaterialCard(risk, scheme),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildMaterialCard(_MaterialRisk risk, ColorScheme scheme) {
    final material = risk.material;
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
                    material.materialName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (risk.needsReorder)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Reorder now',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openForm(material: material),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(material),
                    ),
                  ],
                ),
              ],
            ),
            Text('${material.currentStock} ${material.unit} in stock'),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: risk.daysOfCover != null && risk.minSupplierLeadDays != null
                    ? (risk.daysOfCover! / (risk.minSupplierLeadDays! * 3))
                        .clamp(0.0, 1.0)
                    : (risk.daysOfCover == null ? 0 : 1),
                minHeight: 6,
                backgroundColor: AppColors.primaryLight,
                valueColor: AlwaysStoppedAnimation(
                  risk.needsReorder ? AppColors.primaryDark : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (risk.daysOfCover != null) ...[
              Text(
                '${risk.daysOfCover!.toStringAsFixed(1)} days of cover at planned production',
              ),
              if (risk.isCoveredByIncoming)
                Text(
                  'PO-${risk.coveringOrder!.poId} arriving in '
                  '${risk.coveringOrderArrivalDays} day${risk.coveringOrderArrivalDays == 1 ? '' : 's'} — covered.',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (risk.stockOutDate != null)
                Text(
                  'Predicted stock-out: ${risk.stockOutDate!.year}-'
                  '${risk.stockOutDate!.month.toString().padLeft(2, '0')}-'
                  '${risk.stockOutDate!.day.toString().padLeft(2, '0')}',
                ),
            ] else
              const Text(
                'No planned production yet — add machines/manpower to estimate burn rate',
              ),
            if (!risk.hasSupplier)
              Text(
                'No supplier assigned',
                style: TextStyle(color: scheme.outline),
              )
            else
              Text(
                'Fastest supplier lead time (worse of promised/actual): '
                '${risk.minSupplierLeadDays!.toStringAsFixed(1)} days',
              ),
          ],
        ),
      ),
    );
  }
}
