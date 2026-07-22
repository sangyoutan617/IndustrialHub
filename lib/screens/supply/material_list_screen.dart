import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/raw_material.dart';
import '../../services/capacity_service.dart';
import '../../services/material_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'material_form_screen.dart';
import 'order_list_screen.dart';
import 'supplier_list_screen.dart';

class _MaterialRisk {
  final RawMaterial material;
  final double? burnRatePerDay;
  final double? daysOfCover;
  final DateTime? stockOutDate;
  final int? minSupplierLeadDays;

  _MaterialRisk({
    required this.material,
    this.burnRatePerDay,
    this.daysOfCover,
    this.stockOutDate,
    this.minSupplierLeadDays,
  });

  bool get needsReorder =>
      daysOfCover != null &&
      minSupplierLeadDays != null &&
      daysOfCover! <= minSupplierLeadDays!;

  bool get hasSupplier => minSupplierLeadDays != null;
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
      final snapshot = await _capacityService.getSnapshot(widget.factoryId);

      final leadTimeByMaterial = <int, int>{};
      for (final supplier in suppliers) {
        final materialId = supplier.materialId;
        if (materialId == null) continue;
        final existing = leadTimeByMaterial[materialId];
        if (existing == null || supplier.leadTimeDays < existing) {
          leadTimeByMaterial[materialId] = supplier.leadTimeDays;
        }
      }

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
        return _MaterialRisk(
          material: material,
          burnRatePerDay: burnRate,
          daysOfCover: daysOfCover,
          stockOutDate: stockOutDate,
          minSupplierLeadDays: leadTimeByMaterial[material.materialId],
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
                      '${mostUrgent.minSupplierLeadDays} day lead',
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
              if (risk.stockOutDate != null)
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
                'Fastest supplier lead time: ${risk.minSupplierLeadDays} days',
              ),
          ],
        ),
      ),
    );
  }
}
