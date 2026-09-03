import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/factory.dart';
import '../../models/ipi_benchmark.dart';
import '../../models/msic_code.dart';
import '../../services/capacity_service.dart';
import '../../services/daily_production_service.dart';
import '../../services/factory_service.dart';
import '../../services/product_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';

class BenchmarkScreen extends StatefulWidget {
  final Factory factory;

  const BenchmarkScreen({super.key, required this.factory});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

enum _LoadState { loading, error, needsMsic, ready }

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final _capacityService = CapacityService();
  final _factoryService = FactoryService();
  final _productionService = DailyProductionService();
  final _productService = ProductService();

  _LoadState _state = _LoadState.loading;
  late Factory _factory = widget.factory;

  double _effectiveCapacity = 0;
  MsicCode? _msic;
  List<IpiBenchmark> _ipiTrend = [];
  Map<DateTime, double> _monthlyOutput = {};
  SectorComparison? _comparison;
  bool _isAssigning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final msicCode = _factory.msicCode;
      if (msicCode == null || msicCode.isEmpty) {
        setState(() => _state = _LoadState.needsMsic);
        return;
      }

      final products = await _productService.getProducts(_factory.factoryId);
      final snapshots = await Future.wait(
        products.map(
          (p) => _capacityService.getSnapshot(
            _factory.factoryId,
            productId: p.productId,
          ),
        ),
      );
      final effectiveCapacity = snapshots.fold<double>(
        0,
        (sum, s) => sum + s.effectiveCapacity,
      );
      final msic = await _capacityService.getMsicByCode(msicCode);
      final ipiTrend = await _capacityService.getIpiTrend(
        msic?.division ??
            msicCode.substring(0, msicCode.length >= 2 ? 2 : msicCode.length),
      );

      final monthlyOutput = ipiTrend.isEmpty
          ? <DateTime, double>{}
          : await _productionService.getMonthlyAverageOutput(
              _factory.factoryId,
              since: DateTime(
                ipiTrend.first.date.year,
                ipiTrend.first.date.month,
              ),
            );

      setState(() {
        _effectiveCapacity = effectiveCapacity;
        _msic = msic;
        _ipiTrend = ipiTrend;
        _monthlyOutput = monthlyOutput;
        _comparison = CapacityService.buildSectorComparison(
          ipiTrend: ipiTrend,
          factoryMonthlyOutput: monthlyOutput,
        );
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _assignMsicCode() async {
    if (_isAssigning) return;
    setState(() => _isAssigning = true);
    List<MsicCode> options;
    try {
      options = await _capacityService.getMsicCodes();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAssigning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load MSIC codes. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (options.isEmpty) {
      setState(() => _isAssigning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No MSIC codes found. Import the MSIC lookup CSV first (Section 3/12).',
          ),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<MsicCode>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => ListView.builder(
          controller: scrollController,
          itemCount: options.length,
          itemBuilder: (context, index) {
            final option = options[index];
            return ListTile(
              title: Text(option.msicCode),
              subtitle: Text(option.description),
              onTap: () => Navigator.pop(context, option),
            );
          },
        ),
      ),
    );
    if (selected == null) {
      if (mounted) setState(() => _isAssigning = false);
      return;
    }

    try {
      final updated = await _factoryService.updateMsicCode(
        _factory.factoryId,
        selected.msicCode,
      );
      setState(() => _factory = updated);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Industry code updated')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not assign MSIC code. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark vs Malaysia')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load benchmark data. Please try again.',
          onRetry: _load,
        );
      case _LoadState.needsMsic:
        return EmptyState(
          icon: Icons.category_outlined,
          title: 'No industry code assigned',
          subtitle:
              'Assign an MSIC code to compare against national DOSM benchmarks.',
          actionLabel: 'Assign MSIC code',
          onAction: _assignMsicCode,
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildIndustryCard(),
          const SizedBox(height: 16),
          _buildYourFactoryCard(),
          const SizedBox(height: 16),
          _buildComparisonCard(),
        ],
      ),
    );
  }

  Widget _buildIndustryCard() {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.category_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          _msic?.description ?? _factory.msicCode ?? 'Unknown industry',
        ),
        subtitle: Text('MSIC ${_factory.msicCode}'),
        trailing: TextButton(
          onPressed: _isAssigning ? null : _assignMsicCode,
          child: const Text('Change'),
        ),
      ),
    );
  }

  MapEntry<DateTime, double>? get _latestLoggedMonth {
    if (_monthlyOutput.isEmpty) return null;
    final months = _monthlyOutput.keys.toList()..sort();
    final last = months.last;
    return MapEntry(last, _monthlyOutput[last]!);
  }

  Widget _buildYourFactoryCard() {
    final latest = _latestLoggedMonth;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your factory',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatUnits(_effectiveCapacity)}/day',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              'Effective capacity',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    'Actual output',
                    latest != null
                        ? '${formatUnits(latest.value)}/day'
                        : 'Not logged',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile(
                    'Latest month',
                    latest != null ? formatMonth(latest.key) : '-',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard() {
    final comparison = _comparison;
    final divisionLabel = _ipiTrend.isEmpty
        ? null
        : 'Division ${_ipiTrend.first.division}'
              '${_ipiTrend.first.divisionName != null ? ' — ${_ipiTrend.first.divisionName}' : ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your production vs sector',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (divisionLabel != null) Text(divisionLabel),
            const SizedBox(height: 12),
            if (_ipiTrend.isEmpty)
              const Text('No IPI data found for this division yet.')
            else if (comparison == null)
              _buildSectorOnly()
            else
              _buildComparisonChart(comparison),
            const SizedBox(height: 8),
            Text(
              'Industrial data sourced from Department of Statistics Malaysia (DOSM) via data.gov.my, '
              'licensed under CC BY 4.0.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectorOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              titlesData: _hiddenTitles,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                _series([
                  for (var i = 0; i < _ipiTrend.length; i++)
                    FlSpot(i.toDouble(), _ipiTrend[i].productionIndex),
                ], Theme.of(context).colorScheme.tertiary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sector index only — log at least two months of production within '
          'this window to see your factory charted against it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildComparisonChart(SectorComparison comparison) {
    final scheme = Theme.of(context).colorScheme;
    final points = comparison.points;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legendDot('Your output', scheme.primary),
            const SizedBox(width: 16),
            _legendDot('Sector (IPI)', scheme.tertiary),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              titlesData: _hiddenTitles,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 100,
                    color: scheme.outlineVariant,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ],
              ),
              lineBarsData: [
                _series([
                  for (var i = 0; i < points.length; i++)
                    FlSpot(i.toDouble(), points[i].sectorIndex),
                ], scheme.tertiary),
                _series([
                  for (var i = 0; i < points.length; i++)
                    FlSpot(i.toDouble(), points[i].factoryIndex),
                ], scheme.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Since ${formatMonth(comparison.baseMonth)}, your output is '
          '${_signedPercent(comparison.factoryChangePercent)} and the sector is '
          '${_signedPercent(comparison.sectorChangePercent)}.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Both lines are rebased to 100 at ${formatMonth(comparison.baseMonth)} '
          'because DOSM publishes IPI as an index, not a unit count. That makes '
          'the growth rates comparable — the levels themselves are in different '
          'units and are not.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _signedPercent(double change) =>
      '${change >= 0 ? '+' : ''}${formatPercent(change)}';

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static const _hiddenTitles = FlTitlesData(
    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );

  LineChartBarData _series(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      dotData: const FlDotData(show: false),
      color: color,
      barWidth: 3,
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.15),
      ),
    );
  }
}
