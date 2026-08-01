import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/raw_material.dart';
import '../../services/material_service.dart';
import '../../services/mrp_service.dart';
import '../../services/supply_exceptions.dart';
import '../../services/supply_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import 'material_form_screen.dart';
import 'order_form_screen.dart';
import 'order_list_screen.dart';
import 'supplier_list_screen.dart';

class MaterialListScreen extends StatefulWidget {
  final int factoryId;

  const MaterialListScreen({super.key, required this.factoryId});

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

enum _LoadState { loading, error, ready }

class _MaterialListScreenState extends State<MaterialListScreen> {
  final _materialService = MaterialService();
  final _supplyService = SupplyService();

  _LoadState _state = _LoadState.loading;
  SupplyOverview? _overview;
  bool _needsActionOnly = false;

  // Bumped on every _load() call; a response is only applied if it's still
  // the most recent one requested. Without this, switching factories or
  // pulling to refresh mid-flight can let a slower, stale response
  // overwrite a newer one that already landed.
  int _loadToken = 0;

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
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final overview = await _supplyService.load(widget.factoryId);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _overview = overview;
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load overview: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  List<MaterialPlan> get _sortedPlans {
    final plans = List<MaterialPlan>.from(_overview?.plans ?? const []);
    int priority(SupplyRisk risk) => switch (risk) {
      SupplyRisk.stockedOut => 0,
      SupplyRisk.reorderNow => 1,
      SupplyRisk.watch => 2,
      SupplyRisk.healthy => 3,
      SupplyRisk.noSupplier => 4,
    };
    plans.sort((a, b) {
      final p = priority(a.risk).compareTo(priority(b.risk));
      if (p != 0) return p;
      final aDate = a.orderByDate;
      final bDate = b.orderByDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    if (_needsActionOnly) {
      return plans.where((p) => p.needsAttention).toList();
    }
    return plans;
  }

  Future<void> _openForm({RawMaterial? material}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MaterialFormScreen(factoryId: widget.factoryId, material: material),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(material == null ? 'Material added' : 'Material updated'),
        ),
      );
    }
  }

  Future<void> _openReorderForm(MaterialPlan plan) async {
    final supplier = plan.bestSupplier;
    if (supplier == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderFormScreen(
          factoryId: widget.factoryId,
          prefill: OrderFormPrefill(
            materialId: plan.material.materialId,
            supplierId: supplier.supplierId,
            quantity: plan.suggestedQty,
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase order created')),
      );
    }
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
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material removed')),
      );
    } on SupplyInUseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      debugPrint('supply: failed to delete material: $e');
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
    if (!mounted) return;
    _load();
  }

  void _showProjection(MaterialPlan plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProjectionSheet(plan: plan),
    );
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
        return ErrorState(
          message: 'Could not load materials. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final scheme = Theme.of(context).colorScheme;
    final overview = _overview!;
    final plans = overview.plans;
    // Partitioned so reorderCount + watchCount always equals the number of
    // plans the "Needs action" filter below would show — a material that's
    // below its reorder level but not yet risk::watch/reorderNow used to be
    // invisible in both headline numbers while still showing up once the
    // filter chip was tapped.
    bool isReorder(MaterialPlan p) =>
        p.risk == SupplyRisk.reorderNow || p.risk == SupplyRisk.stockedOut;
    final reorderCount = plans.where(isReorder).length;
    final watchCount = plans
        .where(
          (p) =>
              !isReorder(p) && (p.risk == SupplyRisk.watch || p.belowReorderLevel),
        )
        .length;
    final noCapacityData = overview.plannedProductionPerDay <= 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (noCapacityData)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primaryDark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No capacity set up yet — add machines or shifts on '
                      'the Capacity tab, otherwise stock-out predictions '
                      'below can\'t be calculated and every material will '
                      'read as safe.',
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _summaryStat('Materials', plans.length.toString(), scheme.primary),
                      _summaryStat(
                        'Reorder now',
                        reorderCount.toString(),
                        scheme.error,
                      ),
                      _summaryStat(
                        'Watch',
                        watchCount.toString(),
                        Colors.orange.shade800,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    'Planned production: '
                    '${formatUnits(overview.plannedProductionPerDay)}/day',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    overview.productionFromForecast
                        ? 'from demand forecast'
                        : 'assuming full capacity — set a demand forecast to refine this',
                    style: Theme.of(context).textTheme.bodySmall,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Raw materials', style: Theme.of(context).textTheme.titleMedium),
              FilterChip(
                label: const Text('Needs action'),
                selected: _needsActionOnly,
                onSelected: (v) => setState(() => _needsActionOnly = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (plans.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.inventory_outlined,
                title: 'No materials yet',
                subtitle: 'Add your first material to start tracking supply risk.',
              ),
            )
          else if (_sortedPlans.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Nothing needs action right now',
              ),
            )
          else
            for (final plan in _sortedPlans) _buildMaterialCard(plan, scheme),
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

  Color _riskColor(SupplyRisk risk, ColorScheme scheme) {
    switch (risk) {
      case SupplyRisk.stockedOut:
      case SupplyRisk.reorderNow:
        return scheme.error;
      case SupplyRisk.watch:
        return Colors.orange.shade800;
      case SupplyRisk.noSupplier:
        return scheme.outline;
      case SupplyRisk.healthy:
        return AppColors.primaryDark;
    }
  }

  String _riskLabel(SupplyRisk risk) {
    switch (risk) {
      case SupplyRisk.stockedOut:
        return 'Stocked out';
      case SupplyRisk.reorderNow:
        return 'Reorder now';
      case SupplyRisk.watch:
        return 'Watch';
      case SupplyRisk.noSupplier:
        return 'No supplier';
      case SupplyRisk.healthy:
        return 'Healthy';
    }
  }

  Widget _buildMaterialCard(MaterialPlan plan, ColorScheme scheme) {
    final material = plan.material;
    final riskColor = _riskColor(plan.risk, scheme);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProjection(plan),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _riskLabel(plan.risk),
                      style: TextStyle(
                        color: riskColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
              Text(
                '${formatNumber(material.currentStock)} ${material.unit} in stock'
                '${plan.inboundTotal > 0 ? ' · ${formatNumber(plan.inboundTotal)} ${material.unit} inbound' : ''}',
              ),
              if (plan.overdueOrderCount > 0)
                Text(
                  '${plan.overdueOrderCount} '
                  '${plan.overdueOrderCount == 1 ? 'batch' : 'batches'} overdue '
                  '(${formatNumber(plan.overdueInboundTotal)} ${material.unit}) '
                  '— cover below assumes it still arrives',
                  style: TextStyle(color: scheme.error),
                ),
              if (plan.belowReorderLevel)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Below reorder level (${formatNumber(material.reorderLevel)} ${material.unit})',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (plan.daysOfCover != null) ...[
                Text(
                  '${formatDays(plan.daysOfCover!)} of cover at planned production',
                ),
                if (plan.stockOutDate != null)
                  Text('Predicted stock-out: ${formatDate(plan.stockOutDate!)}'),
              ] else
                Text(
                  '${MrpService.defaultHorizonDays}+ days of cover — no stock-out projected',
                ),
              if (plan.orderByDate != null && plan.bestSupplier != null)
                Text(
                  'Order by ${formatDate(plan.orderByDate!)} — '
                  '${plan.bestSupplier!.supplierName}, '
                  '${plan.effectiveLeadDays} day effective lead',
                  style: TextStyle(color: riskColor, fontWeight: FontWeight.w600),
                )
              else if (plan.bestSupplier == null)
                Text(
                  'No supplier assigned',
                  style: TextStyle(color: scheme.outline),
                ),
              if ((plan.risk == SupplyRisk.reorderNow ||
                      plan.risk == SupplyRisk.stockedOut ||
                      plan.risk == SupplyRisk.watch) &&
                  plan.bestSupplier != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.tonal(
                    onPressed: () => _openReorderForm(plan),
                    child: Text(
                      'Reorder ${plan.suggestedQty != null ? formatNumber(plan.suggestedQty!) : ''} ${material.unit}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectionSheet extends StatelessWidget {
  final MaterialPlan plan;

  const _ProjectionSheet({required this.plan});

  @override
  Widget build(BuildContext context) {
    final days = plan.dailyBalances.length > 30
        ? plan.dailyBalances.sublist(0, 30)
        : plan.dailyBalances;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plan.material.materialName} — 30-day projection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < days.length; i++)
                          FlSpot(i.toDouble(), days[i]),
                      ],
                      isCurved: true,
                      dotData: const FlDotData(show: false),
                      color: AppColors.primary,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              plan.stockOutDate != null
                  ? 'Balance is projected to cross zero on '
                        '${formatDate(plan.stockOutDate!)}.'
                  : 'Balance stays positive for the shown window.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
