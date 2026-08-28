import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/demand_forecast.dart';
import '../../services/data_event_service.dart';
import '../../services/demand_service.dart';
import '../../services/notification_service.dart';
import '../../services/stock_service.dart';
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
import 'stock_trend_screen.dart';

class StockDashboardScreen extends StatefulWidget {
  final int factoryId;

  const StockDashboardScreen({super.key, required this.factoryId});

  @override
  State<StockDashboardScreen> createState() => _StockDashboardScreenState();
}

enum _LoadState { loading, error, ready }

class _StockDashboardScreenState extends State<StockDashboardScreen> {
  final _demandService = DemandService();
  final _stockService = StockService();

  _LoadState _state = _LoadState.loading;
  List<ProductCover> _covers = [];
  List<DemandForecast> _forecasts = [];
  int _pendingMovements = 0;

  @override
  void initState() {
    super.initState();
    _load();
    NotificationService.instance.lastDelivery.addListener(_onDeliveryEvent);
    DataEventService.instance.changeEvent.addListener(_onDataEvent);
  }

  @override
  void dispose() {
    NotificationService.instance.lastDelivery.removeListener(_onDeliveryEvent);
    DataEventService.instance.changeEvent.removeListener(_onDataEvent);
    super.dispose();
  }

  void _onDeliveryEvent() {
    if (mounted) {
      _load();
      setState(() {});
    }
  }

  void _onDataEvent() {
    final event = DataEventService.instance.changeEvent.value;
    if (mounted && event != null && event.factoryId == widget.factoryId) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant StockDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryId != widget.factoryId) _load();
  }

  // [showErrors] is only true for an explicit user retry (the pending-sync
  // pill's "Retry" button) — a silent background load never interrupts the
  // user, and a conflict it finds stays pending rather than being dropped
  // with nobody having seen why.
  Future<void> _load({bool showErrors = false}) async {
    setState(() => _state = _LoadState.loading);
    try {
      final syncFailures = await _stockService.syncPendingMovements(
        dropConflicts: showErrors,
      );
      final overview = await loadStockOverview(widget.factoryId);
      final pending = await _stockService.pendingMovementCount();
      if (!mounted) return;
      setState(() {
        _covers = overview.covers;
        _forecasts = overview.forecasts;
        _pendingMovements = pending;
        _state = _LoadState.ready;
      });
      if (showErrors && syncFailures.isNotEmpty) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: AppColors.dangerLight,
            content: Text(
              syncFailures.first,
              style: const TextStyle(color: AppColors.danger),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.danger),
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).hideCurrentMaterialBanner(),
              ),
            ],
          ),
        );
      }
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

  void _openStockTrend() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockTrendScreen(factoryId: widget.factoryId),
      ),
    );
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
    // Most overstocked first, same ordering convention as criticalItems.
    final overstockItems =
        withCover.where((c) => c.daysOfCover! > overstockDaysThreshold).toList()
          ..sort((a, b) => b.daysOfCover!.compareTo(a.daysOfCover!));

    // AI card is built once so rotating between portrait/landscape never
    // recreates — and re-fetches — it.
    final aiInsight = withCover.isNotEmpty
        ? AiInsightCard(buildPrompt: _buildStockPrompt, system: _stockSystem)
        : null;

    // Single scanning column, top to bottom, in every orientation — landscape
    // gets the same flow with more horizontal room via ResponsiveShell,
    // rather than being split into two columns.
    return _buildPortrait(
      mostUrgent: mostUrgent,
      criticalItems: criticalItems,
      overstockItems: overstockItems,
      aiInsight: aiInsight,
    );
  }

  Widget _buildPortrait({
    required ProductCover? mostUrgent,
    required List<ProductCover> criticalItems,
    required List<ProductCover> overstockItems,
    required Widget? aiInsight,
  }) {
    final delivery = NotificationService.instance.lastDelivery.value;
    final showDeliveryBanner =
        delivery != null && delivery.factoryId == widget.factoryId;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          if (showDeliveryBanner) ...[
            _buildDeliveryBanner(delivery),
            const SizedBox(height: AppSpacing.l),
          ],
          if (_pendingMovements > 0) ...[
            _buildPendingSyncBanner(),
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
          if (overstockItems.isNotEmpty) ...[
            _buildOverstockSection(overstockItems),
            const SizedBox(height: AppSpacing.l),
          ],
          _buildCoverListSection(),
          const SizedBox(height: AppSpacing.xl),
          _buildDemandSection(),
        ],
      ),
    );
  }

  Widget _buildDeliveryBanner(MaterialDeliveryEvent delivery) {
    final theme = Theme.of(context);
    final formattedQty = formatUnits(delivery.quantity);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            color: AppColors.success,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Raw Material Delivered',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                Text(
                  '$formattedQty of ${delivery.materialName} arrived in stock. Tap to update projections.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () {
              _load();
              NotificationService.instance.clearDeliveryAlert();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Stock data refreshed with latest materials'),
                ),
              );
            },
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Update'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppColors.success),
            tooltip: 'Dismiss',
            onPressed: () {
              NotificationService.instance.clearDeliveryAlert();
            },
          ),
        ],
      ),
    );
  }

  // Movements recorded while offline (queued in local SQLite) that haven't
  // reached Supabase yet — see StockOfflineQueueService. A slim status pill
  // rather than InfoBanner, since this is a live "syncing" state, not a
  // one-off warning notice.
  Widget _buildPendingSyncBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              '$_pendingMovements pending sync',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _load(showErrors: true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
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
                      Expanded(
                        child: Text(
                          cover.stock.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

  // Same visual weight as _buildCriticalSection — overstock is wasted
  // capital too, not just a number in the summary row.
  Widget _buildOverstockSection(List<ProductCover> overstockItems) {
    return Card(
      color: AppStatus.info.background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: AppStatus.info.color, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Overstocked — capital tied up',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppStatus.info.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            for (final cover in overstockItems.take(3)) ...[
              InkWell(
                onTap: () => _openDetail(cover),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          cover.stock.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${formatDays(cover.daysOfCover!)} of cover',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppStatus.info.color,
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
        const SizedBox(height: AppSpacing.s),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_view_month_outlined),
            title: const Text('Stock activity'),
            subtitle: const Text('Last 12 weeks, at a glance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openStockTrend,
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
                title: Text(
                  forecast.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${formatNumber(forecast.requiredPerDay)} units/day required',
                ),
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
        '${formatNumber(m.stock.currentQuantity)} units in stock, demand '
        '${formatNumber(m.requiredPerDay!)}/day, ${m.daysOfCover!.toStringAsFixed(1)} days of '
        'cover${m.stockOutDate != null ? ', predicted stock-out ${formatDate(m.stockOutDate!)}' : ''}.',
      );
    }
    for (final c in withCover) {
      buffer.writeln(
        '- ${c.stock.productName}: ${formatNumber(c.stock.currentQuantity)} units, '
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
        // FittedBox so a wide space-formatted count doesn't pinch when
        // this 3-up row lands inside a half-width landscape column.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCoverCard(ProductCover cover) {
    final theme = Theme.of(context);
    // Zero stock gets a stronger treatment than the "Low stock" chip alone —
    // the whole card goes solid red, not just a tinted background.
    final isOutOfStock = cover.stock.currentQuantity == 0;
    final primaryTextColor = isOutOfStock ? Colors.white : theme.colorScheme.onSurface;
    final secondaryTextColor = isOutOfStock
        ? Colors.white.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      color: isOutOfStock ? AppColors.danger : null,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: const Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    StatusChip(label: cover.status, status: cover.appStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                '${formatNumber(cover.stock.currentQuantity)} units in stock',
                style: TextStyle(color: primaryTextColor),
              ),
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
                  backgroundColor: isOutOfStock
                      ? Colors.white.withValues(alpha: 0.3)
                      : theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    isOutOfStock ? Colors.white : cover.appStatus.color,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (cover.daysOfCover != null) ...[
                Text(
                  'Demand ${formatNumber(cover.requiredPerDay!)}/day · '
                  '${cover.daysOfCover!.toStringAsFixed(1)} days of cover',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryTextColor,
                  ),
                ),
                if (cover.stockOutDate != null)
                  Text(
                    'Predicted stock-out: ${formatDate(cover.stockOutDate!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
              ] else
                Text(
                  'No demand set',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryTextColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
