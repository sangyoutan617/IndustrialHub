import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/factory.dart';
import '../../models/ipi_benchmark.dart';
import '../../models/msic_code.dart';
import '../../models/productivity_benchmark.dart';
import '../../services/capacity_service.dart';
import '../../services/factory_service.dart';
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

  _LoadState _state = _LoadState.loading;
  late Factory _factory = widget.factory;

  double? _outputPerWorker;
  double _effectiveCapacity = 0;
  int _totalWorkers = 0;
  MsicCode? _msic;
  ProductivityBenchmark? _productivity;
  List<IpiBenchmark> _ipiTrend = [];
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

      final snapshot = await _capacityService.getSnapshot(_factory.factoryId);
      final msic = await _capacityService.getMsicByCode(msicCode);
      final productivity = msic?.category != null
          ? await _capacityService.getProductivityBenchmark(msic!.category!)
          : null;
      final ipiTrend = await _capacityService.getIpiTrend(
        msic?.division ??
            msicCode.substring(0, msicCode.length >= 2 ? 2 : msicCode.length),
      );

      setState(() {
        _outputPerWorker = _capacityService.outputPerWorker(snapshot);
        _effectiveCapacity = snapshot.effectiveCapacity;
        _totalWorkers = snapshot.shifts.fold<int>(
          0,
          (sum, s) => sum + s.workerCount,
        );
        _msic = msic;
        _productivity = productivity;
        _ipiTrend = ipiTrend;
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
    final topCard = Card(
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
    final yourFactoryCard = _buildYourFactoryCard();
    final productivityCard = _buildProductivityCard();
    final ipiCard = _buildIpiCard();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          topCard,
          const SizedBox(height: 16),
          yourFactoryCard,
          const SizedBox(height: 16),
          productivityCard,
          const SizedBox(height: 16),
          ipiCard,
        ],
      ),
    );
  }

  Widget _buildYourFactoryCard() {
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statTile('Total workers', '$_totalWorkers')),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile(
                    'Output / worker',
                    _outputPerWorker != null
                        ? '${formatUnits(_outputPerWorker!)}/day'
                        : 'n/a',
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

  Widget _buildProductivityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'National labour productivity (DOSM)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_productivity == null)
              const Text('No productivity benchmark found for this sector yet.')
            else ...[
              Text('Sector: ${_productivity!.sector} (${_productivity!.year})'),
              if (_productivity!.valueAddedPerWorker != null)
                Text(
                  'Value added per worker: RM ${formatNumber(_productivity!.valueAddedPerWorker!)} / year',
                ),
              if (_productivity!.valueAddedPerHour != null)
                Text(
                  'Value added per hour: RM ${formatNumber(_productivity!.valueAddedPerHour!)}',
                ),
              const SizedBox(height: 8),
              Text(
                'Shown side-by-side for context — your output is in physical units/day while the '
                'DOSM figure is value-added (RM) per year, so they are not directly comparable as a '
                'single percentage without your average selling price per unit.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIpiCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Industrial Production Index trend (DOSM)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_ipiTrend.isEmpty)
              const Text('No IPI data found for this division yet.')
            else ...[
              Text(
                'Division ${_ipiTrend.first.division}${_ipiTrend.first.divisionName != null ? ' — ${_ipiTrend.first.divisionName}' : ''}',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < _ipiTrend.length; i++)
                            FlSpot(i.toDouble(), _ipiTrend[i].productionIndex),
                        ],
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 3,
                        belowBarData: BarAreaData(
                          show: true,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Latest reading: ${formatNumber(_ipiTrend.last.productionIndex)} '
                '(${_ipiTrend.length} month${_ipiTrend.length == 1 ? '' : 's'} shown)',
              ),
            ],
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
}
