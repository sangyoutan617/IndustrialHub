import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/purchase_order.dart';
import '../../models/raw_material.dart';
import '../../services/mrp_service.dart';
import '../../services/supply_service.dart';
import '../../widgets/ai_insight_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import 'material_detail_screen.dart';
import 'material_form_screen.dart';
import 'order_list_screen.dart';
import 'supplier_list_screen.dart';
import 'supply_risk_ui.dart';

class MaterialListScreen extends StatefulWidget {
  final int factoryId;

  /// Optional factory-health banner rendered as the first item in this
  /// screen's own scrollable list — deliberately not a fixed/pinned sibling
  /// above it, so it scrolls away with the rest of the content instead of
  /// permanently occupying screen space.
  final Widget? bottleneckBanner;

  const MaterialListScreen({
    super.key,
    required this.factoryId,
    this.bottleneckBanner,
  });

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

enum _LoadState { loading, error, ready }

class _MaterialListScreenState extends State<MaterialListScreen> {
  final _supplyService = SupplyService();

  _LoadState _state = _LoadState.loading;
  SupplyOverview? _overview;
  bool _needsActionOnly = false;
  final _searchController = TextEditingController();
  String _query = '';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  // Most urgent first — shared by the full list and the "Attention
  // required" highlight section so the two can never disagree on ordering.
  List<MaterialPlan> get _riskSortedPlans {
    final plans = List<MaterialPlan>.from(_overview?.plans ?? const []);
    plans.sort((a, b) {
      final p = supplyRiskPriority(a.risk).compareTo(supplyRiskPriority(b.risk));
      if (p != 0) return p;
      final aDate = a.orderByDate;
      final bDate = b.orderByDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return plans;
  }

  List<MaterialPlan> get _sortedPlans {
    var result = _riskSortedPlans;
    if (_needsActionOnly) {
      result = result.where((p) => p.needsAttention).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((p) => p.material.materialName.toLowerCase().contains(q))
          .toList();
    }
    return result;
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
          content: Text(
            material == null ? 'Material added' : 'Material updated',
          ),
        ),
      );
    }
  }

  Future<void> _navigateAndRefresh(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    _load();
  }

  void _openDetail(MaterialPlan plan) {
    _navigateAndRefresh(
      MaterialDetailScreen(
        factoryId: widget.factoryId,
        materialId: plan.material.materialId,
      ),
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
    final overview = _overview!;
    final plans = overview.plans;

    // Partitioned so criticalCount + attentionCount always equals the
    // number of plans the "Needs action" filter below would show — a
    // material that's below its reorder level but not yet
    // watch/reorderNow used to be invisible in both headline numbers
    // while still showing up once the filter chip was tapped.
    bool isCritical(MaterialPlan p) =>
        p.risk == SupplyRisk.reorderNow || p.risk == SupplyRisk.stockedOut;
    final criticalCount = plans.where(isCritical).length;
    final attentionCount = plans
        .where(
          (p) =>
              !isCritical(p) &&
              (p.risk == SupplyRisk.watch || p.belowReorderLevel),
        )
        .length;
    final healthyCount = plans.length - criticalCount - attentionCount;
    final noCapacityData = overview.plannedProductionPerDay <= 0;

    final attentionItems = _riskSortedPlans
        .where((p) => p.needsAttention)
        .take(3)
        .toList();

    // Purchase-order status counts — computed from overview.orders, which
    // SupplyService.load already fetched for this same screen load, so this
    // costs zero extra queries.
    final poCounts = <String, int>{};
    for (final o in overview.orders) {
      poCounts[o.status] = (poCounts[o.status] ?? 0) + 1;
    }

    // Built once and handed to whichever layout (portrait/landscape) is
    // active below, so rotating never recreates — and re-fetches — the AI
    // card.
    final aiInsight = plans.isNotEmpty
        ? AiInsightCard(
            buildPrompt: () => _buildSupplyPrompt(overview),
            system: _supplySystem,
          )
        : null;

    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          return _buildLandscape(
            overview: overview,
            plans: plans,
            criticalCount: criticalCount,
            attentionCount: attentionCount,
            healthyCount: healthyCount,
            noCapacityData: noCapacityData,
            attentionItems: attentionItems,
            poCounts: poCounts,
            aiInsight: aiInsight,
          );
        }
        return _buildPortrait(
          overview: overview,
          plans: plans,
          criticalCount: criticalCount,
          attentionCount: attentionCount,
          healthyCount: healthyCount,
          noCapacityData: noCapacityData,
          attentionItems: attentionItems,
          poCounts: poCounts,
          aiInsight: aiInsight,
        );
      },
    );
  }

  Widget _buildPortrait({
    required SupplyOverview overview,
    required List<MaterialPlan> plans,
    required int criticalCount,
    required int attentionCount,
    required int healthyCount,
    required bool noCapacityData,
    required List<MaterialPlan> attentionItems,
    required Map<String, int> poCounts,
    required Widget? aiInsight,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          if (widget.bottleneckBanner != null) ...[
            widget.bottleneckBanner!,
            const SizedBox(height: AppSpacing.l),
          ],
          if (noCapacityData) ...[
            const InfoBanner(
              status: AppStatus.warning,
              message:
                  'No capacity set up yet — add machines or shifts on '
                  'the Capacity tab, otherwise stock-out predictions '
                  'below can\'t be calculated and every material will '
                  'read as safe.',
            ),
            const SizedBox(height: AppSpacing.l),
          ],
          _buildHealthCard(overview, criticalCount, attentionCount, healthyCount),
          const SizedBox(height: AppSpacing.l),
          if (attentionItems.isNotEmpty) ...[
            _buildAttentionSection(attentionItems),
            const SizedBox(height: AppSpacing.l),
          ],
          if (aiInsight != null) ...[aiInsight, const SizedBox(height: AppSpacing.l)],
          _buildMaterialsSection(plans),
          const SizedBox(height: AppSpacing.l),
          _buildPurchaseOrdersSection(poCounts),
          const SizedBox(height: AppSpacing.s),
          _buildSuppliersRow(),
        ],
      ),
    );
  }

  Widget _buildLandscape({
    required SupplyOverview overview,
    required List<MaterialPlan> plans,
    required int criticalCount,
    required int attentionCount,
    required int healthyCount,
    required bool noCapacityData,
    required List<MaterialPlan> attentionItems,
    required Map<String, int> poCounts,
    required Widget? aiInsight,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: overview story — health, attention, AI.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.bottleneckBanner != null) ...[
                    widget.bottleneckBanner!,
                    const SizedBox(height: AppSpacing.l),
                  ],
                  if (noCapacityData) ...[
                    const InfoBanner(
                      status: AppStatus.warning,
                      message:
                          'No capacity set up yet — add machines or shifts '
                          'on the Capacity tab, otherwise stock-out '
                          'predictions can\'t be calculated and every '
                          'material will read as safe.',
                    ),
                    const SizedBox(height: AppSpacing.l),
                  ],
                  _buildHealthCard(
                    overview,
                    criticalCount,
                    attentionCount,
                    healthyCount,
                  ),
                  if (attentionItems.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.l),
                    _buildAttentionSection(attentionItems),
                  ],
                  if (aiInsight != null) ...[
                    const SizedBox(height: AppSpacing.l),
                    aiInsight,
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.l),
            // Right: materials list + purchase orders / suppliers.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMaterialsSection(plans),
                  const SizedBox(height: AppSpacing.l),
                  _buildPurchaseOrdersSection(poCounts),
                  const SizedBox(height: AppSpacing.s),
                  _buildSuppliersRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard(
    SupplyOverview overview,
    int criticalCount,
    int attentionCount,
    int healthyCount,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Supply health', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: _summaryStat(
                    'Critical',
                    criticalCount.toString(),
                    AppStatus.danger.color,
                  ),
                ),
                Expanded(
                  child: _summaryStat(
                    'Needs attention',
                    attentionCount.toString(),
                    AppStatus.warning.color,
                  ),
                ),
                Expanded(
                  child: _summaryStat(
                    'Healthy',
                    healthyCount.toString(),
                    AppStatus.success.color,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Planned production: '
              '${formatUnits(overview.plannedProductionPerDay)}/day',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
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
    );
  }

  Widget _buildAttentionSection(List<MaterialPlan> attentionItems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Attention required',
          trailing: TextButton(
            onPressed: () => setState(() => _needsActionOnly = true),
            child: const Text('View all risks'),
          ),
        ),
        for (final plan in attentionItems) _buildAttentionCard(plan),
      ],
    );
  }

  Widget _buildAttentionCard(MaterialPlan plan) {
    final riskStatus = supplyRiskStatus(plan.risk);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      color: riskStatus.background,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _openDetail(plan),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              Icon(riskStatus.icon, color: riskStatus.color),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.material.materialName,
                      style: TextStyle(fontWeight: FontWeight.w700, color: riskStatus.color),
                    ),
                    Text(
                      plan.daysOfCover != null
                          ? '${formatDays(plan.daysOfCover!)} of cover'
                          : supplyRiskLabel(plan.risk),
                      style: TextStyle(color: riskStatus.color),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: riskStatus.color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialsSection(List<MaterialPlan> plans) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context).supplyRawMaterials,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FilterChip(
              label: const Text('Needs action'),
              selected: _needsActionOnly,
              onSelected: (v) => setState(() => _needsActionOnly = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        if (plans.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search materials',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        if (plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.inventory_outlined,
              title: 'No materials yet',
              subtitle:
                  'Add your first material to start tracking supply risk.',
            ),
          )
        else if (_sortedPlans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: _query.isNotEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No materials match that search',
                  )
                : const EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'Nothing needs action right now',
                  ),
          )
        else
          for (final plan in _sortedPlans) _buildMaterialCard(plan),
      ],
    );
  }

  Widget _buildPurchaseOrdersSection(Map<String, int> poCounts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Purchase orders'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (poCounts.isEmpty)
                  Text(
                    'No purchase orders yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  Wrap(
                    spacing: AppSpacing.l,
                    runSpacing: AppSpacing.s,
                    children: [
                      for (final status in PurchaseOrderStatus.all)
                        if (poCounts[status] != null)
                          _summaryStat(
                            status,
                            poCounts[status].toString(),
                            Theme.of(context).colorScheme.onSurface,
                          ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _navigateAndRefresh(
                      OrderListScreen(factoryId: widget.factoryId),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('View purchase orders'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuppliersRow() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_shipping_outlined),
        title: const Text('Suppliers'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _navigateAndRefresh(
          SupplierListScreen(factoryId: widget.factoryId),
        ),
      ),
    );
  }

  // Deterministic figures only — burn rates, days of cover, stock-out and
  // order-by dates, and suggested order quantities are all computed by
  // MrpService (SupplyService.load). The AI card just narrates them; it
  // never runs the arithmetic. Mirrors the Module 1 / Module 2 insights.
  static const _supplySystem =
      'You are a factory supply-chain assistant. You are given figures that '
      'have already been computed — never invent or recalculate numbers. In '
      '2-3 short, plain-language sentences for a factory manager, explain the '
      'raw-material supply risk — which material must be reordered first and '
      'from which supplier — and give one concrete next step based only on '
      'the numbers provided. No markdown, no headings, under 80 words.';

  String _buildSupplyPrompt(SupplyOverview overview) {
    final plans = overview.plans;
    bool isReorder(MaterialPlan p) =>
        p.risk == SupplyRisk.reorderNow || p.risk == SupplyRisk.stockedOut;
    final reorderCount = plans.where(isReorder).length;
    final watchCount = plans
        .where(
          (p) =>
              !isReorder(p) &&
              (p.risk == SupplyRisk.watch || p.belowReorderLevel),
        )
        .length;
    final noSupplierCount = plans
        .where((p) => p.risk == SupplyRisk.noSupplier)
        .length;
    final overdueOrders = plans.fold<int>(
      0,
      (sum, p) => sum + p.overdueOrderCount,
    );

    final buffer = StringBuffer()
      ..writeln('Raw materials tracked: ${plans.length}')
      ..writeln(
        'Reorder now (out of stock or past order-by date): $reorderCount',
      )
      ..writeln(
        'Watch (order-by date near, or below reorder level): $watchCount',
      )
      ..writeln('Materials with no supplier linked: $noSupplierCount')
      ..writeln('Open purchase orders already overdue: $overdueOrders')
      ..writeln(
        'Planned production: ${formatUnits(overview.plannedProductionPerDay)}/day'
        '${overview.productionFromForecast ? ' (from demand forecast)' : ' (assuming full capacity)'}',
      );
    if (overview.plannedProductionPerDay <= 0) {
      buffer.writeln(
        'No capacity data is set, so burn rates and stock-out dates cannot be '
        'projected — treat risk as unknown, not safe.',
      );
    }

    final attention = _riskSortedPlans.where((p) => p.needsAttention).toList();

    if (attention.isEmpty) {
      buffer.writeln('No materials currently need action.');
    }
    for (final p in attention) {
      final line = StringBuffer(
        '- ${p.material.materialName} [${supplyRiskLabel(p.risk)}]: '
        'on hand ${formatNumber(p.onHand)}, burn ${formatNumber(p.burnRatePerDay)}/day',
      );
      if (p.daysOfCover != null) {
        line.write(', ${p.daysOfCover!.toStringAsFixed(1)} days of cover');
      }
      if (p.stockOutDate != null) {
        line.write(', stock-out ${formatDate(p.stockOutDate!)}');
      }
      if (p.orderByDate != null) {
        line.write(', order by ${formatDate(p.orderByDate!)}');
      }
      if (p.bestSupplier != null && p.effectiveLeadDays != null) {
        line.write(
          ', best supplier ${p.bestSupplier!.supplierName} '
          '(~${p.effectiveLeadDays} day lead)',
        );
      }
      if (p.suggestedQty != null && p.suggestedQty! > 0) {
        line.write(', suggested order ${formatNumber(p.suggestedQty!)}');
      }
      buffer.writeln(line.toString());
    }
    return buffer.toString();
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
        Text(label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }

  // Compact, scannable row: name / stock / days of cover / status. Deeper
  // detail (overdue batches, reorder-level breach, recommended supplier,
  // suggested quantity, edit/delete) lives on MaterialDetailScreen now
  // instead of being crammed into this list row.
  Widget _buildMaterialCard(MaterialPlan plan) {
    final material = plan.material;
    final riskStatus = supplyRiskStatus(plan.risk);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _openDetail(plan),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l,
            vertical: AppSpacing.m,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.materialName,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatNumber(material.currentStock)} ${material.unit}'
                      '${plan.daysOfCover != null ? '  ·  ${formatDays(plan.daysOfCover!)} of cover' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              StatusChip(label: supplyRiskLabel(plan.risk), status: riskStatus, dense: true),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
