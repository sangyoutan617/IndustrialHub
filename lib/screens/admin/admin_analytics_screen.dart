import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/factory.dart';
import '../../services/admin_service.dart';
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

  // Consistent status mapping for a factory's overall picture, used for
  // both the bar chart bars and the factories table's row.
  AppStatus _factoryStatus(FactoryStat stat) {
    if (stat.productsWithData == 0) return AppStatus.neutral;
    return stat.productsShort > 0 ? AppStatus.danger : AppStatus.success;
  }

  Color _factoryColor(FactoryStat stat) => _factoryStatus(stat).color;

  String _resourceLabel(String? resource) {
    switch (resource) {
      case 'MACHINE':
        return 'Machine';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      case null:
        return '—';
      default:
        return resource;
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
    final benchmarkCard = _buildBenchmarkCard(stats);
    final chartCard = _buildChartCard(stats);
    final tableCard = _buildTableCard(stats);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          benchmarkCard,
          const SizedBox(height: AppSpacing.l),
          chartCard,
          const SizedBox(height: AppSpacing.l),
          tableCard,
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
            // Achievable/demand are no longer summed platform-wide — a
            // factory's products can be in different units, and summing
            // across factories compounds that. "X of Y products meeting
            // demand" is the one figure that stays meaningful regardless of
            // what any given product is measured in.
            Row(
              children: [
                Expanded(
                  child: KpiCard(
                    icon: Icons.speed_outlined,
                    label: 'Products meeting demand',
                    value: '${stats.totalProductsMeetingDemand}',
                    unit: 'of ${stats.totalProductsWithData}',
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: KpiCard(
                    icon: Icons.warning_amber_rounded,
                    label: 'Factories at risk',
                    value: '${stats.factoriesAtRisk}',
                    unit: 'of ${stats.factories.length}',
                    status: stats.factoriesAtRisk > 0
                        ? AppStatus.danger
                        : AppStatus.success,
                    statusLabel: stats.factoriesAtRisk > 0
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
                    '${p.benchmark.valueAddedPerWorker != null ? ' — DOSM RM ${formatWhole(p.benchmark.valueAddedPerWorker!)}/worker/year for context' : ''}',
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

  // Percent of products meeting demand, not raw achievable units — a
  // factory's products can be in different units, so a bar chart of raw
  // achievable output isn't comparable factory-to-factory (or even
  // product-to-product within one factory). Percent-meeting-demand is.
  Widget _buildChartCard(CrossFactoryStats stats) {
    final bars = stats.factories;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Products meeting demand, by factory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendDot('At risk (some products short)', AppStatus.danger.color),
                _legendDot('On track', AppStatus.success.color),
                _legendDot('No data', AppStatus.neutral.color),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) =>
                            Text('${value.toInt()}%', style: Theme.of(context).textTheme.labelSmall),
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
                            toY: bars[i].productsWithData == 0
                                ? 0
                                : bars[i].productsMeetingDemand /
                                      bars[i].productsWithData *
                                      100,
                            color: _factoryColor(bars[i]),
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
                  DataColumn(label: Text('Products'), numeric: true),
                  DataColumn(label: Text('Meeting demand'), numeric: true),
                  DataColumn(label: Text('Short'), numeric: true),
                  DataColumn(label: Text('Common bottleneck')),
                ],
                rows: [
                  for (final stat in stats.factories)
                    DataRow(
                      onSelectChanged: (_) => _openDetail(stat.factory),
                      cells: [
                        DataCell(Text(stat.factory.factoryName)),
                        DataCell(Text('${stat.productsWithData}')),
                        DataCell(Text('${stat.productsMeetingDemand}')),
                        DataCell(Text('${stat.productsShort}')),
                        DataCell(
                          StatusChip(
                            label: _resourceLabel(stat.dominantBottleneckResource),
                            status: _factoryStatus(stat),
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
