import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../models/purchase_order.dart';
import '../../models/raw_material_movement.dart';
import '../../services/bom_service.dart';
import '../../services/material_movement_service.dart';
import '../../services/material_service.dart';
import '../../services/mrp_service.dart';
import '../../services/supply_exceptions.dart';
import '../../services/supply_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/material_projection_sheet.dart';
import '../../widgets/status.dart';
import '../products/product_detail_screen.dart';
import 'material_form_screen.dart';
import 'order_form_screen.dart';
import 'supplier_comparison_screen.dart';
import 'supply_risk_ui.dart';

class MaterialDetailScreen extends StatefulWidget {
  final int factoryId;
  final int materialId;

  const MaterialDetailScreen({
    super.key,
    required this.factoryId,
    required this.materialId,
  });

  @override
  State<MaterialDetailScreen> createState() => _MaterialDetailScreenState();
}

enum _LoadState { loading, error, notFound, ready }

class _MaterialDetailScreenState extends State<MaterialDetailScreen> {
  final _supplyService = SupplyService();
  final _materialService = MaterialService();
  final _movementService = MaterialMovementService();
  final _bomService = BomService();

  _LoadState _state = _LoadState.loading;
  MaterialPlan? _plan;
  List<RawMaterialMovement> _movements = [];
  List<Product> _usedInProducts = [];
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
      final overview = await _supplyService.load(widget.factoryId);
      if (!mounted || token != _loadToken) return;
      MaterialPlan? plan;
      for (final p in overview.plans) {
        if (p.material.materialId == widget.materialId) {
          plan = p;
          break;
        }
      }
      List<RawMaterialMovement> movements = const [];
      List<Product> usedIn = const [];
      if (plan != null) {
        try {
          movements = await _movementService.getMovements(widget.materialId);
        } catch (e) {
          debugPrint('supply: failed to load material ledger: $e');
        }
        try {
          usedIn = await _bomService.getProductsUsing(widget.materialId);
        } catch (e) {
          debugPrint('supply: failed to load products using material: $e');
        }
      }
      if (!mounted || token != _loadToken) return;
      setState(() {
        _plan = plan;
        _movements = movements;
        _usedInProducts = usedIn;
        _state = plan != null ? _LoadState.ready : _LoadState.notFound;
      });
    } catch (e) {
      debugPrint('supply: failed to load material detail: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MaterialFormScreen(
          factoryId: widget.factoryId,
          material: _plan!.material,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    _load();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Material updated')));
  }

  Future<void> _delete() async {
    final material = _plan!.material;
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
      Navigator.of(context).pop(true);
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

  Future<void> _openReorderForm() async {
    final plan = _plan!;
    final supplier = plan.bestSupplier;
    if (supplier == null) return;
    final saved = await Navigator.of(context).push<dynamic>(
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
    if (!mounted || saved == null) return;
    _load();
    final poNumber = saved is PurchaseOrder ? ' ${formatPoNumber(saved.poId)}' : '';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Purchase order$poNumber created')));
  }

  Future<void> _recordUsage() async {
    final material = _plan!.material;
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isDeduct = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adjust stock'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor:
                          Theme.of(context).colorScheme.primary,
                      selectedForegroundColor:
                          Theme.of(context).colorScheme.onPrimary,
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('+ Add')),
                      ButtonSegment(value: true, label: Text('- Deduct')),
                    ],
                    selected: {isDeduct},
                    onSelectionChanged: (selection) =>
                        setDialogState(() => isDeduct = selection.first),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  TextFormField(
                    controller: qtyController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount (${material.unit})',
                    ),
                    validator: (v) {
                      final parsed = double.tryParse((v ?? '').trim());
                      if (parsed == null || parsed <= 0) {
                        return 'Enter a positive amount';
                      }
                      if (isDeduct && parsed > material.currentStock) {
                        return 'Deduction cannot exceed current stock '
                            '(${formatNumber(material.currentStock)} ${material.unit})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.m),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final qty = double.parse(qtyController.text.trim());
    final finalQty = isDeduct ? -qty : qty;
    try {
      await _movementService.recordMovement(
        materialId: material.materialId,
        factoryId: widget.factoryId,
        movementType: RawMaterialMovementType.adjustment,
        quantity: finalQty,
        movementDate: DateTime.now(),
        note: noteController.text.trim().isEmpty
            ? null
            : noteController.text.trim(),
      );
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Stock updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openComparison() {
    final plan = _plan!;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierComparisonScreen(
          factoryId: widget.factoryId,
          materialId: plan.material.materialId,
          materialName: plan.material.materialName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Inventory'),
        actions: _state == _LoadState.ready
            ? [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit material',
                  onPressed: _edit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove material',
                  onPressed: _delete,
                ),
              ]
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load this material. Please try again.',
          onRetry: _load,
        );
      case _LoadState.notFound:
        return const ErrorStateNotFound();
      case _LoadState.ready:
        return _buildReady(_plan!);
    }
  }

  Widget _buildReady(MaterialPlan plan) {
    final material = plan.material;
    final theme = Theme.of(context);
    final riskStatus = supplyRiskStatus(plan.risk);
    final riskLabel = supplyRiskLabel(plan.risk);
    final canReorder =
        (plan.risk == SupplyRisk.reorderNow ||
            plan.risk == SupplyRisk.stockedOut ||
            plan.risk == SupplyRisk.watch) &&
        plan.bestSupplier != null;

    return RefreshIndicator(
      onRefresh: _load,
      child: _buildPortrait(
        plan: plan,
        material: material,
        theme: theme,
        riskStatus: riskStatus,
        riskLabel: riskLabel,
        canReorder: canReorder,
      ),
    );
  }

  List<Widget> _headerAndMetrics({
    required MaterialPlan plan,
    required dynamic material,
    required ThemeData theme,
    required AppStatus riskStatus,
    required String riskLabel,
  }) {
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              material.materialName,
              style: theme.textTheme.titleLarge,
            ),
          ),
          StatusChip(label: riskLabel, status: riskStatus),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        _riskExplanation(plan),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.l),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l,
            vertical: AppSpacing.s,
          ),
          child: Column(
            children: [
              MetricRow(
                label: 'Current stock',
                value: '${formatNumber(material.currentStock)} ${material.unit}',
                reserveBadgeSpace: true,
              ),
              MetricRow(
                label: 'Reorder level',
                value: '${formatNumber(plan.reorderLevel)} ${material.unit}',
                status: plan.belowReorderLevel ? AppStatus.danger : null,
                statusLabel: plan.belowReorderLevel ? 'Below' : null,
                reserveBadgeSpace: true,
              ),
              MetricRow(
                label: 'Days of cover',
                value: plan.daysOfCover != null
                    ? formatDays(plan.daysOfCover!)
                    : '${MrpService.defaultHorizonDays}+ days',
                reserveBadgeSpace: true,
              ),
              MetricRow(
                label: 'Expected stock-out',
                value: plan.stockOutDate != null
                    ? formatDate(plan.stockOutDate!)
                    : 'Not projected',
                reserveBadgeSpace: true,
              ),
              MetricRow(
                label: 'Latest safe order date',
                value: plan.orderByDate != null
                    ? formatDate(plan.orderByDate!)
                    : '—',
                reserveBadgeSpace: true,
              ),
              MetricRow(
                label: 'Burn rate',
                value:
                    '${formatRate(plan.burnRatePerDay)} ${material.unit}/day',
                reserveBadgeSpace: true,
              ),
              if (plan.inboundTotal > 0)
                MetricRow(
                  label: 'Inbound (open orders)',
                  value:
                      '${formatNumber(plan.inboundTotal)} ${material.unit}',
                  status: plan.overdueOrderCount > 0
                      ? AppStatus.warning
                      : null,
                  statusLabel: plan.overdueOrderCount > 0
                      ? '${plan.overdueOrderCount} overdue'
                      : null,
                  reserveBadgeSpace: true,
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.s),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showMaterialProjectionSheet(context, plan),
          icon: const Icon(Icons.show_chart, size: 18),
          label: const Text('View 30-day trend'),
        ),
      ),
      ..._usedInSection(theme),
    ];
  }

  List<Widget> _usedInSection(ThemeData theme) {
    return [
      const SectionHeader(title: 'Used in'),
      if (_usedInProducts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
          child: Text(
            'No product currently lists this material in its recipe.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        )
      else
        Card(
          child: Column(
            children: [
              for (final product in _usedInProducts)
                ListTile(
                  title: Text(product.productName),
                  subtitle: product.isGeneral ? const Text('General') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(product: product),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _ledgerAndAction({
    required MaterialPlan plan,
    required dynamic material,
    required ThemeData theme,
    required bool canReorder,
  }) {
    return [
      const SectionHeader(title: 'Stock ledger'),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _recordUsage,
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('Adjust stock'),
        ),
      ),
      const SizedBox(height: AppSpacing.s),
      if (_movements.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
          child: Text(
            'No stock movements recorded yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        )
      else
        Card(
          child: SizedBox(
            height: 240,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final m in _movements.take(20))
                  _ledgerTile(m, material.unit, theme),
              ],
            ),
          ),
        ),
      const SectionHeader(title: 'Recommended action'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (plan.bestSupplier != null) ...[
                MetricRow(
                  label: 'Recommended supplier',
                  value: plan.bestSupplier!.supplierName,
                ),
                MetricRow(
                  label: 'Effective lead time',
                  value: '${plan.effectiveLeadDays} days',
                ),
                MetricRow(
                  label: 'Suggested order quantity',
                  value: plan.suggestedQty != null && plan.suggestedQty! > 0
                      ? '${formatNumber(plan.suggestedQty!)} ${material.unit}'
                      : 'None needed',
                ),
              ] else
                Text(
                  'No supplier is linked to this material yet — add one to '
                  'get a reorder recommendation.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppStatus.neutral.color,
                  ),
                ),
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _openComparison,
                      child: const Text('Compare suppliers'),
                    ),
                  ),
                  if (canReorder &&
                      plan.suggestedQty != null &&
                      plan.suggestedQty! > 0) ...[
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: FilledButton(
                        onPressed: _openReorderForm,
                        child: const Text('Create purchase order'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildPortrait({
    required MaterialPlan plan,
    required dynamic material,
    required ThemeData theme,
    required AppStatus riskStatus,
    required String riskLabel,
    required bool canReorder,
  }) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        ..._headerAndMetrics(
          plan: plan,
          material: material,
          theme: theme,
          riskStatus: riskStatus,
          riskLabel: riskLabel,
        ),
        ..._ledgerAndAction(
          plan: plan,
          material: material,
          theme: theme,
          canReorder: canReorder,
        ),
      ],
    );
  }

  Widget _ledgerTile(RawMaterialMovement m, String unit, ThemeData theme) {
    final isOut =
        m.movementType == RawMaterialMovementType.consumption ||
        (m.movementType == RawMaterialMovementType.adjustment &&
            m.quantity < 0);
    final label = switch (m.movementType) {
      RawMaterialMovementType.consumption => 'Consumption',
      RawMaterialMovementType.receipt => 'Receipt',
      _ => 'Adjustment',
    };
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(
        m.note != null
            ? '${formatDate(m.movementDate)} · ${m.note}'
            : formatDate(m.movementDate),
      ),
      trailing: Text(
        '${isOut ? '−' : '+'}${formatNumber(m.quantity.abs())} $unit',
        style: TextStyle(
          color: isOut ? AppColors.danger : AppColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _riskExplanation(MaterialPlan plan) {
    if (plan.risk == SupplyRisk.stockedOut) {
      return 'Out of stock now. Cover assumes any overdue inbound batches still arrive.';
    }
    if (plan.overdueOrderCount > 0) {
      return '${plan.overdueOrderCount} inbound '
          '${plan.overdueOrderCount == 1 ? 'batch is' : 'batches are'} overdue — '
          'the cover figures below assume they still arrive.';
    }
    if (plan.belowReorderLevel) {
      return 'Current stock is below the reorder level set for this material.';
    }
    if (plan.risk == SupplyRisk.reorderNow) {
      return 'The latest safe order date has passed — order now to avoid a stock-out.';
    }
    if (plan.risk == SupplyRisk.watch) {
      return 'The latest safe order date is approaching.';
    }
    if (plan.risk == SupplyRisk.noSupplier) {
      return 'No supplier is linked, so a reorder recommendation can\'t be made.';
    }
    return 'Stock is comfortably covering planned production.';
  }
}

class ErrorStateNotFound extends StatelessWidget {
  const ErrorStateNotFound({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: Text('This material no longer exists.')),
    );
  }
}
