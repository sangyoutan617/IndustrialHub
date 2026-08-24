import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/factory.dart';
import '../../services/admin_service.dart';
import '../../services/bottleneck_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import 'admin_factory_detail_screen.dart';

enum _LoadState { loading, error, ready }

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  final _adminService = AdminService();

  _LoadState _state = _LoadState.loading;
  CrossFactoryStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final stats = await _adminService.crossFactoryStats();
      setState(() {
        _stats = stats;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  // Consistent bottleneck-type -> status mapping, used for both the bar
  // chart bars/legend and the factories table's Bottleneck column.
  AppStatus _bottleneckStatus(FactoryStat stat) {
    if (!stat.bottleneck.hasData) return AppStatus.neutral;
    switch (stat.bottleneck.limiter ?? stat.bottleneck.bottleneckResource) {
      case 'MACHINE':
        return AppStatus.info;
      case 'MANPOWER':
        return AppStatus.warning;
      case 'RAW MATERIAL':
        return AppStatus.danger;
      default:
        return AppStatus.success;
    }
  }

  Color _bottleneckColor(FactoryStat stat) => _bottleneckStatus(stat).color;

  String _bottleneckLabel(BottleneckResult result) {
    if (!result.hasData) return 'No data';
    switch (result.limiter ?? result.bottleneckResource) {
      case 'MACHINE':
        return 'Machine';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return result.limiter ?? result.bottleneckResource;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cross-factory analytics')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        final stats = _stats!;
        if (stats.factories.isEmpty) {
          return EmptyState(
            icon: Icons.factory_outlined,
            message: 'No factories exist yet.',
          );
        }
        return _buildReady(stats);
    }
  }

  Widget _buildReady(CrossFactoryStats stats) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          _buildBenchmarkCard(stats),
          const SizedBox(height: AppSpacing.l),
          _buildChartCard(stats),
          const SizedBox(height: AppSpacing.l),
          _buildTableCard(stats),
        ],
      ),
    );
  }

  Widget _buildBenchmarkCard(CrossFactoryStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Platform benchmark',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: KpiCard(
                    icon: Icons.speed_outlined,
                    label: 'Aggregate achievable/day',
                    value: stats.totalAchievable.toStringAsFixed(0),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: KpiCard(
                    icon: Icons.trending_up,
                    label: 'Aggregate demand/day',
                    value: stats.totalDemand.toStringAsFixed(0),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: KpiCard(
                    icon: Icons.warning_amber_rounded,
                    label: 'Below demand',
                    value: '${stats.factoriesBelowDemand}',
                    unit: 'of ${stats.factories.length}',
                    status: stats.factoriesBelowDemand > 0
                        ? AppStatus.danger
                        : AppStatus.success,
                    statusLabel: stats.factoriesBelowDemand > 0
                        ? 'At risk'
                        : 'On track',
                  ),
                ),
              ],
            ),
            if (stats.ipiReadings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'National IPI (latest, DOSM)',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reading in stats.ipiReadings)
                    Chip(
                      label: Text(
                        '${reading.divisionName ?? 'Div. ${reading.division}'}: ${reading.productionIndex.toStringAsFixed(1)}',
                      ),
                    ),
                ],
              ),
            ],
            if (stats.productivity.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Productivity benchmark (DOSM, by MSIC category)',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final p in stats.productivity)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${p.category}: ${p.belowPeerMedianCount} of ${p.factoryCount} factories below the peer median '
                    'output/worker (avg ${p.avgOutputPerWorker.toStringAsFixed(2)} units/day/worker)'
                    '${p.benchmark.valueAddedPerWorker != null ? ' — DOSM RM ${p.benchmark.valueAddedPerWorker!.toStringAsFixed(0)}/worker/year for context' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Text(
                'DOSM productivity is value-added (RM/year); this app measures physical units/day. Without a selling '
                'price the two cannot be merged into one ratio, so "below benchmark" compares each factory against '
                'the peer median within its own MSIC category instead.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(CrossFactoryStats stats) {
    final bars = stats.factories;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Achievable output/day by factory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendDot('Machine', AppStatus.info.color),
                _legendDot('Manpower', AppStatus.warning.color),
                _legendDot('Raw material', AppStatus.danger.color),
                _legendDot('No bottleneck', AppStatus.success.color),
                _legendDot('No data', AppStatus.neutral.color),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= bars.length) {
                            return const SizedBox.shrink();
                          }
                          final name = bars[index].factory.factoryName;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              name.length > 8
                                  ? '${name.substring(0, 8)}…'
                                  : name,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < bars.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: bars[i].bottleneck.achievable,
                            color: _bottleneckColor(bars[i]),
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _buildTableCard(CrossFactoryStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All factories',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Factory')),
                  DataColumn(label: Text('Achievable/day'), numeric: true),
                  DataColumn(label: Text('Demand/day'), numeric: true),
                  DataColumn(label: Text('Shortfall'), numeric: true),
                  DataColumn(label: Text('Bottleneck')),
                ],
                rows: [
                  for (final stat in stats.factories)
                    DataRow(
                      onSelectChanged: (_) => _openDetail(stat.factory),
                      cells: [
                        DataCell(Text(stat.factory.factoryName)),
                        DataCell(
                          Text(
                            stat.bottleneck.hasData
                                ? stat.bottleneck.achievable.toStringAsFixed(0)
                                : '—',
                          ),
                        ),
                        DataCell(
                          Text(
                            stat.bottleneck.hasData
                                ? stat.bottleneck.requiredPerDay
                                      .toStringAsFixed(0)
                                : '—',
                          ),
                        ),
                        DataCell(
                          Text(
                            stat.bottleneck.shortfall != null
                                ? stat.bottleneck.shortfall!.toStringAsFixed(0)
                                : '—',
                          ),
                        ),
                        DataCell(
                          StatusChip(
                            label: _bottleneckLabel(stat.bottleneck),
                            status: _bottleneckStatus(stat),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(Factory factory) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminFactoryDetailScreen(factory: factory),
      ),
    );
  }
}
