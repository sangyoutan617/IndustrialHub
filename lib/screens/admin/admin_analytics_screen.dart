import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/admin_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

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

  AppStatus _factoryStatus(FactoryStat stat) {
    if (stat.productsWithData == 0) return AppStatus.neutral;
    return stat.productsShort > 0 ? AppStatus.danger : AppStatus.success;
  }

  Color _factoryColor(FactoryStat stat) => _factoryStatus(stat).color;

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
              'Products meeting demand, by factory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendDot(
                  'At risk (some products short)',
                  AppStatus.danger.color,
                ),
                _legendDot('On track', AppStatus.success.color),
                _legendDot('No data', AppStatus.neutral.color),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: _plotHeight + _labelHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFixedYAxis(),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: _barSlotWidth * bars.length,
                        child: BarChart(
                          BarChartData(
                            maxY: 100,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  final stat = bars[group.x.toInt()];
                                  return BarTooltipItem(
                                    '${stat.factory.factoryName}\n',
                                    const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: stat.productsWithData == 0
                                            ? 'No data'
                                            : '${stat.productsMeetingDemand}/${stat.productsWithData} meeting demand '
                                                  '(${rod.toY.toStringAsFixed(0)}%)',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
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
                                      width: 28,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _plotHeight = 180.0;
  static const _labelHeight = 8.0;
  static const _barSlotWidth = 48.0;

  Widget _buildFixedYAxis() {
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: _plotHeight + _labelHeight,
      width: 34,
      child: Column(
        children: [
          SizedBox(
            height: _plotHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('100%', style: style),
                Text('75%', style: style),
                Text('50%', style: style),
                Text('25%', style: style),
                Text('0%', style: style),
              ],
            ),
          ),
          SizedBox(height: _labelHeight),
        ],
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
}
