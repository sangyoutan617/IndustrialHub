import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/stock_movement.dart';
import '../../services/stock_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';

class StockTrendScreen extends StatefulWidget {
  final int factoryId;

  const StockTrendScreen({super.key, required this.factoryId});

  @override
  State<StockTrendScreen> createState() => _StockTrendScreenState();
}

enum _LoadState { loading, error, ready }

const _weeksShown = 12;
const _daysShown = _weeksShown * 7;

const _weekdayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _typeLabels = {
  StockMovementType.productionIn: 'Production',
  StockMovementType.shipmentOut: 'Shipments',
  StockMovementType.damaged: 'Damage',
  StockMovementType.returned: 'Returns',
  StockMovementType.adjustment: 'Adjustments',
};

class _StockTrendScreenState extends State<StockTrendScreen> {
  final _service = StockService();
  _LoadState _state = _LoadState.loading;
  List<StockMovement> _movements = [];
  String? _filter;

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
    final todayAtMidnight = DateTime(today.year, today.month, today.day);
    final currentWeekStart = todayAtMidnight.subtract(
      Duration(days: todayAtMidnight.weekday - 1),
    );
    final start = currentWeekStart.subtract(
      const Duration(days: (_weeksShown - 1) * 7),
    );
    final end = todayAtMidnight;

    final totals = <DateTime, int>{};
    for (var i = 0; i < _daysShown; i++) {
      totals[start.add(Duration(days: i))] = 0;
    }
    for (final m in _movements) {
      if (_filter != null && m.movementType != _filter) continue;
      final day = DateTime(
        m.movementDate.year,
        m.movementDate.month,
        m.movementDate.day,
      );
      if (day.isBefore(start) || day.isAfter(end)) continue;
      if (!totals.containsKey(day)) continue;
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
        _buildFilterChips(),
        const SizedBox(height: AppSpacing.m),
        Text(
          'Each cell is one day — darker means more units moved in or out '
          'that day. Tap a day to see what moved.',
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
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          infoSection,
          const SizedBox(height: AppSpacing.xl),
          heatmapSection,
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('All movements'),
          selected: _filter == null,
          selectedColor: scheme.primaryContainer,
          onSelected: (_) => setState(() => _filter = null),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _filter,
            hint: const Text('Filter by type'),
            borderRadius: BorderRadius.circular(AppRadius.md),
            items: [
              for (final type in StockMovementType.all)
                DropdownMenuItem(value: type, child: Text(_typeLabels[type]!)),
            ],
            onChanged: (value) => setState(() => _filter = value),
          ),
        ),
      ],
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

  Color _cellTextColor(int value, int maxVal) {
    if (value == 0 || maxVal == 0) return AppColors.textMuted;
    final ratio = value / maxVal;
    return ratio <= 0.5 ? AppColors.textSecondary : Colors.white;
  }

  String _monthLabelForColumn(List<DateTime> days, int col) {
    final first = days[col * 7];
    if (col > 0 && days[(col - 1) * 7].month == first.month) return '';
    return _monthAbbr[first.month - 1];
  }

  Widget _buildHeatmap(
    List<DateTime> days,
    Map<DateTime, int> totals,
    int maxVal,
  ) {
    const cellSize = 22.0;
    const cellGap = 4.0;
    const monthLabelHeight = 14.0;
    final labelColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              const SizedBox(height: monthLabelHeight + 4),
              for (var row = 0; row < 7; row++) ...[
                SizedBox(
                  width: 26,
                  height: cellSize,
                  child: Text(
                    _weekdayAbbr[row],
                    style: TextStyle(fontSize: 9, color: labelColor),
                  ),
                ),
                if (row != 6) const SizedBox(height: cellGap),
              ],
            ],
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var col = 0; col < _weeksShown; col++) ...[
                    SizedBox(
                      width: cellSize,
                      height: monthLabelHeight,
                      child: Text(
                        _monthLabelForColumn(days, col),
                        style: TextStyle(fontSize: 9, color: labelColor),
                        softWrap: false,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                    if (col != _weeksShown - 1) const SizedBox(width: cellGap),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
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
                              return GestureDetector(
                                onTap: () => _showDayDetail(day),
                                child: Container(
                                  width: cellSize,
                                  height: cellSize,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _cellColor(value, maxVal),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: _cellTextColor(value, maxVal),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (row != 6) const SizedBox(height: cellGap),
                        ],
                      ],
                    ),
                    if (col != _weeksShown - 1) const SizedBox(width: cellGap),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isOutbound(String movementType) =>
      movementType == StockMovementType.shipmentOut ||
      movementType == StockMovementType.damaged;

  void _showDayDetail(DateTime day) {
    final dayMovements =
        _movements.where((m) {
          final d = DateTime(
            m.movementDate.year,
            m.movementDate.month,
            m.movementDate.day,
          );
          return d == day;
        }).toList()..sort(
          (a, b) => (a.productName ?? '').compareTo(b.productName ?? ''),
        );

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.l,
                0,
                AppSpacing.l,
                AppSpacing.l,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDate(day),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  if (dayMovements.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No movement that day.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: dayMovements.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final m = dayMovements[index];
                          final isOut = _isOutbound(m.movementType);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(m.productName ?? 'Unknown product'),
                            subtitle: Text(
                              m.note != null && m.note!.isNotEmpty
                                  ? '${_typeLabels[m.movementType] ?? m.movementType} · ${m.note}'
                                  : (_typeLabels[m.movementType] ??
                                        m.movementType),
                            ),
                            trailing: Text(
                              '${isOut ? '−' : '+'}${formatWhole(m.quantity.abs())}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isOut ? scheme.error : scheme.primary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegend() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
