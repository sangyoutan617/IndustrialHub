import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/demand_forecast.dart';
import '../../services/demand_service.dart';
import '../../widgets/ai_insight_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import 'demand_form_screen.dart';
import 'stock_cover_loader.dart';
import 'stock_list_screen.dart';
import 'stock_product_detail_screen.dart';

class StockDashboardScreen extends StatefulWidget {
  final int factoryId;

  /// Optional factory-health banner rendered as the first item in this
  /// screen's own scrollable list — deliberately not a fixed/pinned sibling
  /// above it, so it scrolls away with the rest of the content instead of
  /// permanently occupying screen space.
  final Widget? bottleneckBanner;

  const StockDashboardScreen({
    super.key,
    required this.factoryId,
    this.bottleneckBanner,
  });

  @override
  State<StockDashboardScreen> createState() => _StockDashboardScreenState();
}

enum _LoadState { loading, error, ready }

class _StockDashboardScreenState extends State<StockDashboardScreen> {
  final _demandService = DemandService();

  _LoadState _state = _LoadState.loading;
  List<ProductCover> _covers = [];
  List<DemandForecast> _forecasts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StockDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryId != widget.factoryId) _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final overview = await loadStockOverview(widget.factoryId);
      if (!mounted) return;
      setState(() {
        _covers = overview.covers;
        _forecasts = overview.forecasts;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openDemandForm({DemandForecast? forecast}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            DemandFormScreen(factoryId: widget.factoryId, forecast: forecast),
      ),
    );
    if (saved == true) {
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forecast == null
                ? 'Demand forecast added'
                : 'Demand forecast updated',
          ),
        ),
      );
    }
  }

  Future<void> _deleteDemand(DemandForecast forecast) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove demand forecast?',
      message:
          'This removes the forecast for "${forecast.productName}" permanently.',
    );
    if (!confirmed) return;
    try {
      await _demandService.deleteForecast(forecast.demandId);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Demand forecast removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete forecast. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openStockList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockListScreen(factoryId: widget.factoryId),
      ),
    );
    _load();
  }

  Future<void> _openDetail(ProductCover cover) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockProductDetailScreen(
          factoryId: widget.factoryId,
          stockId: cover.stock.stockId,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
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
    final withCover = _covers.where((c) => c.daysOfCover != null).toList();
    final mostUrgent = withCover.isEmpty
        ? null
        : (withCover.toList()
                ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!)))
              .first;
    final criticalItems = withCover.where((c) => c.needsAttention).toList()
      ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!));

    // AI card is built once so rotating between portrait/landscape never
    // recreates — and re-fetches — it.
    final aiInsight = withCover.isNotEmpty
        ? AiInsightCard(buildPrompt: _buildStockPrompt, system: _stockSystem)
        : null;

    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          return _buildLandscape(
            mostUrgent: mostUrgent,
            criticalItems: criticalItems,
            aiInsight: aiInsight,
          );
        }
        return _buildPortrait(
          mostUrgent: mostUrgent,
          criticalItems: criticalItems,
          aiInsight: aiInsight,
        );
      },
    );
  }

  Widget _buildPortrait({
    required ProductCover? mostUrgent,
    required List<ProductCover> criticalItems,
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
          _buildCoverSummaryCard(mostUrgent),
          const SizedBox(height: AppSpacing.l),
          if (aiInsight != null) ...[aiInsight, const SizedBox(height: AppSpacing.l)],
          _buildSummaryStatsRow(),
          const SizedBox(height: AppSpacing.l),
          if (criticalItems.isNotEmpty) ...[
            _buildCriticalSection(criticalItems),
            const SizedBox(height: AppSpacing.l),
          ],
          _buildCoverListSection(),
          const SizedBox(height: AppSpacing.xl),
          _buildDemandSection(),
        ],
      ),
    );
  }

  Widget _buildLandscape({
    required ProductCover? mostUrgent,
    required List<ProductCover> criticalItems,
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
            // Left: overview story — cover, stats, critical, AI.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.bottleneckBanner != null) ...[
                    widget.bottleneckBanner!,
                    const SizedBox(height: AppSpacing.l),
                  ],
                  _buildCoverSummaryCard(mostUrgent),
                  const SizedBox(height: AppSpacing.l),
                  _buildSummaryStatsRow(),
                  if (criticalItems.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.l),
                    _buildCriticalSection(criticalItems),
                  ],
                  if (aiInsight != null) ...[
                    const SizedBox(height: AppSpacing.l),
                    aiInsight,
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.l),
            // Right: full products list + demand forecast.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCoverListSection(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildDemandSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverSummaryCard(ProductCover? mostUrgent) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).stockDaysOfCover,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              mostUrgent != null ? formatDays(mostUrgent.daysOfCover!) : '—',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            if (mostUrgent?.stockOutDate != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Stock-out predicted: ${formatDate(mostUrgent!.stockOutDate!)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStatsRow() {
    final scheme = Theme.of(context).colorScheme;
    final lowStockCount = _covers.where((c) => c.needsAttention).length;
    final overstockCount = _covers
        .where(
          (c) =>
              c.requiredPerDay != null &&
              c.requiredPerDay! > 0 &&
              c.daysOfCover! > overstockDaysThreshold,
        )
        .length;
    return Row(
      children: [
        Expanded(
          child: _summaryStat('Products', _covers.length.toString(), scheme.primary),
        ),
        Expanded(
          child: _summaryStat(
            'Low stock',
            lowStockCount.toString(),
            AppStatus.danger.color,
          ),
        ),
        Expanded(
          child: _summaryStat(
            'Overstocked',
            overstockCount.toString(),
            AppStatus.info.color,
          ),
        ),
      ],
    );
  }

  // Top-N urgent products, highlighted above the full list — same pattern
  // as the Supply module's "Attention required" section, so a manager sees
  // what needs a decision first instead of scanning every product.
  Widget _buildCriticalSection(List<ProductCover> criticalItems) {
    return Card(
      color: AppStatus.danger.background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppStatus.danger.color, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Critical products',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppStatus.danger.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            for (final cover in criticalItems.take(3)) ...[
              InkWell(
                onTap: () => _openDetail(cover),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(cover.stock.productName)),
                      Text(
                        formatDays(cover.daysOfCover!),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppStatus.danger.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCoverListSection() {
    if (_covers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
          message: 'No products yet. Add one from Finished Stock above.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Days of cover'),
        for (final cover in _covers) ...[
          _buildCoverCard(cover),
          const SizedBox(height: AppSpacing.s),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openStockList,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Log stock movement'),
          ),
        ),
      ],
    );
  }

  Widget _buildDemandSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Demand forecast',
          trailing: TextButton.icon(
            onPressed: () => _openDemandForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add demand'),
          ),
        ),
        if (_forecasts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: EmptyState(
              icon: Icons.trending_up,
              message: 'No demand forecasts set yet.',
            ),
          )
        else
          for (final forecast in _forecasts)
            Card(
              child: ListTile(
                title: Text(forecast.productName),
                subtitle: Text('${forecast.requiredPerDay} units/day required'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openDemandForm(forecast: forecast),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteDemand(forecast),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // Deterministic figures only — days of cover and stock-out dates are all
  // computed in _load(). The AI card just narrates them; it never does the
  // arithmetic. Mirrors the Module 1 (capacity) bottleneck insight.
  static const _stockSystem =
      'You are a factory inventory assistant. You are given figures that '
      'have already been computed — never invent or recalculate numbers. In '
      '2-3 short, plain-language sentences for a factory manager, explain the '
      'finished-goods stock situation — which product runs out first and '
      'whether any are low or overstocked — and give one concrete next step '
      'based only on the numbers provided. No markdown, no headings, under 80 '
      'words.';

  String _buildStockPrompt() {
    final withCover = _covers.where((c) => c.daysOfCover != null).toList()
      ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!));
    final lowStock = _covers
        .where(
          (c) =>
              c.requiredPerDay != null &&
              c.requiredPerDay! > 0 &&
              c.daysOfCover! < lowCoverDaysThreshold,
        )
        .length;
    final overstock = _covers
        .where(
          (c) =>
              c.requiredPerDay != null &&
              c.requiredPerDay! > 0 &&
              c.daysOfCover! > overstockDaysThreshold,
        )
        .length;

    final buffer = StringBuffer()
      ..writeln('Finished-goods products tracked: ${_covers.length}')
      ..writeln(
        'Low-stock (under $lowCoverDaysThreshold days of cover): $lowStock',
      )
      ..writeln(
        'Overstocked (over $overstockDaysThreshold days of cover): $overstock',
      );

    if (withCover.isNotEmpty) {
      final m = withCover.first;
      buffer.writeln(
        'Closest to stock-out: ${m.stock.productName} — '
        '${m.stock.currentQuantity} units in stock, demand '
        '${m.requiredPerDay}/day, ${m.daysOfCover!.toStringAsFixed(1)} days of '
        'cover${m.stockOutDate != null ? ', predicted stock-out ${formatDate(m.stockOutDate!)}' : ''}.',
      );
    }
    for (final c in withCover) {
      buffer.writeln(
        '- ${c.stock.productName}: ${c.stock.currentQuantity} units, '
        '${c.daysOfCover!.toStringAsFixed(1)} days of cover (${c.status}).',
      );
    }

    final noDemand = _covers
        .where((c) => c.requiredPerDay == null || c.requiredPerDay == 0)
        .map((c) => c.stock.productName)
        .toList();
    if (noDemand.isNotEmpty) {
      buffer.writeln(
        'Products with no demand forecast set (cover cannot be computed): '
        '${noDemand.join(', ')}.',
      );
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildCoverCard(ProductCover cover) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => _openDetail(cover),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    cover.stock.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(label: cover.status, status: cover.appStatus),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Text('${cover.stock.currentQuantity} units in stock'),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: cover.requiredPerDay != null && cover.requiredPerDay! > 0
                    ? (cover.stock.currentQuantity /
                              (cover.requiredPerDay! * overstockDaysThreshold))
                          .clamp(0.0, 1.0)
                    : 0,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(cover.appStatus.color),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (cover.daysOfCover != null) ...[
              Text(
                'Demand ${cover.requiredPerDay}/day · '
                '${cover.daysOfCover!.toStringAsFixed(1)} days of cover',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (cover.stockOutDate != null)
                Text(
                  'Predicted stock-out: ${formatDate(cover.stockOutDate!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ] else
              Text(
                'No demand set',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}
