import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/stock_movement.dart';
import '../../services/stock_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_two_pane.dart';

/// Factory-wide stock activity as a calendar heatmap, not a line chart —
/// deliberately distinct from Capacity's trend and IPI charts. Plain
/// widgets only, no chart package.
class StockTrendScreen extends StatefulWidget {
  final int factoryId;

  const StockTrendScreen({super.key, required this.factoryId});

  @override
  State<StockTrendScreen> createState() => _StockTrendScreenState();
}

enum _LoadState { loading, error, ready }

const _weeksShown = 12;
const _daysShown = _weeksShown * 7;

class _StockTrendScreenState extends State<StockTrendScreen> {
  final _service = StockService();
  _LoadState _state = _LoadState.loading;
  List<StockMovement> _movements = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final movements = await _service.getMovementsForFactory(
        widget.factoryId,
      );
      if (!mounted) return;
      setState(() {
        _movements = movements;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock activity')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load stock activity. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: _daysShown - 1));

    // Absolute units moved per day, all movement types combined. Only the
    // pre-seeded _daysShown keys are ever read below, so a movement outside
    // [start, today] (e.g. a forward-dated one) is dropped rather than
    // silently added as an extra, unread map entry.
    final end = DateTime(today.year, today.month, today.day);
    final totals = <DateTime, int>{};
    for (var i = 0; i < _daysShown; i++) {
      totals[start.add(Duration(days: i))] = 0;
    }
    for (final m in _movements) {
      final day = DateTime(
        m.movementDate.year,
        m.movementDate.month,
        m.movementDate.day,
      );
      if (day.isBefore(start) || day.isAfter(end)) continue;
      totals.update(day, (v) => v + m.quantity.abs());
    }

    final days = totals.keys.toList()..sort();
    final maxVal = totals.values.fold<int>(0, (a, b) => a > b ? a : b);
    final totalMoved = totals.values.fold<int>(0, (a, b) => a + b);
    final busiest = totals.entries.isEmpty
        ? null
        : totals.entries.reduce((a, b) => b.value > a.value ? b : a);

    if (_movements.isEmpty) {
      return const EmptyState(
        icon: Icons.pending_actions_outlined,
        title: 'No stock movements yet',
        subtitle:
            'Record production, shipments or adjustments to see activity here.',
      );
    }

    final infoSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last $_weeksShown weeks',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${formatDate(start)} – ${formatDate(today)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.l),
        Row(
          children: [
            Expanded(child: _statTile('Units moved', formatNumber(totalMoved))),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: _statTile(
                'Busiest day',
                busiest != null && busiest.value > 0
                    ? formatDate(busiest.key)
                    : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        Text(
          'Each cell is one day — darker means more units moved in or out '
          'that day (production, shipments, damage, returns and '
          'adjustments combined). Tap a day for its total.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );

    final heatmapSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeatmap(days, totals, maxVal),
        const SizedBox(height: AppSpacing.m),
        _buildLegend(),
      ],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsiveTwoPane(
        portrait: (context) => ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            infoSection,
            const SizedBox(height: AppSpacing.xl),
            heatmapSection,
          ],
        ),
        landscape: (context) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: heatmapSection,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: infoSection,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.primaryDark.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Color _cellColor(int value, int maxVal) {
    if (value == 0 || maxVal == 0) return AppColors.border;
    final ratio = value / maxVal;
    if (ratio <= 0.25) return AppColors.primaryLight;
    if (ratio <= 0.5) return AppColors.primaryAccent.withValues(alpha: 0.55);
    if (ratio <= 0.75) return AppColors.primaryAccent;
    return AppColors.primaryDark;
  }

  // 12 columns of 7 day-cells, not aligned to real weekdays.
  Widget _buildHeatmap(
    List<DateTime> days,
    Map<DateTime, int> totals,
    int maxVal,
  ) {
    const cellSize = 16.0;
    const cellGap = 4.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var col = 0; col < _weeksShown; col++) ...[
            Column(
              children: [
                for (var row = 0; row < 7; row++) ...[
                  Builder(
                    builder: (context) {
                      final index = col * 7 + row;
                      final day = days[index];
                      final value = totals[day] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: cellGap),
                        child: GestureDetector(
                          onTap: () => _showDayTotal(day, value),
                          child: Container(
                            width: cellSize,
                            height: cellSize,
                            decoration: BoxDecoration(
                              color: _cellColor(value, maxVal),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
            if (col != _weeksShown - 1) const SizedBox(width: cellGap),
          ],
        ],
      ),
    );
  }

  void _showDayTotal(DateTime day, int value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value > 0
              ? '${formatDate(day)}: ${formatNumber(value)} units moved'
              : '${formatDate(day)}: no movement',
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text('Less', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        const SizedBox(width: 6),
        for (final c in [
          AppColors.border,
          AppColors.primaryLight,
          AppColors.primaryAccent.withValues(alpha: 0.55),
          AppColors.primaryAccent,
          AppColors.primaryDark,
        ]) ...[
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
          ),
        ],
        const SizedBox(width: 4),
        Text('More', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
