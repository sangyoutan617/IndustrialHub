import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/daily_production.dart';
import '../../models/factory.dart';
import '../../services/daily_production_service.dart';
import '../../services/material_movement_service.dart';
import '../../services/material_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

enum _Granularity { day, rollingWeek, month }

enum _LoadState { loading, error, ready }

class ProductionTrendScreen extends StatefulWidget {
  final Factory factory;

  const ProductionTrendScreen({super.key, required this.factory});

  @override
  State<ProductionTrendScreen> createState() => _ProductionTrendScreenState();
}

class _TrendPoint {
  final String label;
  final double? actual;
  final double? ceiling;

  const _TrendPoint({required this.label, this.actual, this.ceiling});
}

class _ProductionTrendScreenState extends State<ProductionTrendScreen> {
  final _service = DailyProductionService();
  final _materialService = MaterialService();
  final _movementService = MaterialMovementService();

  _LoadState _state = _LoadState.loading;
  _Granularity _granularity = _Granularity.day;
  List<DailyProduction> _raw = [];
  bool _isLogging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _fetchDays {
    switch (_granularity) {
      case _Granularity.day:
        return 30;
      case _Granularity.rollingWeek:
        return 36;
      case _Granularity.month:
        return 365;
    }
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final rows = await _service.getTrend(
        widget.factory.factoryId,
        days: _fetchDays,
      );
      if (!mounted) return;
      setState(() {
        _raw = rows;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  void _setGranularity(_Granularity granularity) {
    if (granularity == _granularity) return;
    setState(() => _granularity = granularity);
    _load();
  }

  Future<void> _openLogDialog() async {
    final outputController = TextEditingController();
    final downtimeController = TextEditingController(text: '0');
    var logDate = DateTime.now();

    try {
      await _runLogDialog(outputController, downtimeController, logDate);
    } finally {
      outputController.dispose();
      downtimeController.dispose();
    }
  }

  Future<void> _runLogDialog(
    TextEditingController outputController,
    TextEditingController downtimeController,
    DateTime logDate,
  ) async {
    var deductMaterials = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log production'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  '${logDate.year}-${logDate.month.toString().padLeft(2, '0')}-${logDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: logDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setDialogState(() => logDate = picked);
                  }
                },
              ),
              TextField(
                controller: outputController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Actual output'),
              ),
              TextField(
                controller: downtimeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Downtime hours'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: deductMaterials,
                onChanged: (v) =>
                    setDialogState(() => deductMaterials = v ?? true),
                title: const Text('Deduct raw materials used'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final actualOutput = int.tryParse(outputController.text);
    if (actualOutput == null) return;
    final downtimeHours = double.tryParse(downtimeController.text) ?? 0;

    setState(() => _isLogging = true);
    try {
      await _service.logProduction(
        factoryId: widget.factory.factoryId,
        logDate: logDate,
        actualOutput: actualOutput,
        downtimeHours: downtimeHours,
      );
      if (deductMaterials && actualOutput > 0) {
        await _consumeMaterials(actualOutput, logDate);
      }
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Production logged')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not log production. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLogging = false);
    }
  }

  /// Deducts the raw material this output consumed, and warns (non-blocking)
  /// about any material that didn't have enough stock. Best-effort — a
  /// consumption failure never undoes the already-logged production.
  Future<void> _consumeMaterials(int units, DateTime date) async {
    try {
      final materials = await _materialService.getMaterials(
        widget.factory.factoryId,
      );
      final skipped = await _movementService.recordProductionConsumption(
        factoryId: widget.factory.factoryId,
        materials: materials,
        unitsProduced: units,
        date: date,
      );
      if (!mounted || skipped.isEmpty) return;
      final names = materials
          .where((m) => skipped.contains(m.materialId))
          .map((m) => m.materialName)
          .join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not enough stock to fully deduct: $names')),
      );
    } catch (e) {
      debugPrint('capacity: material consumption failed: $e');
    }
  }

  List<_TrendPoint> get _points {
    switch (_granularity) {
      case _Granularity.day:
        return [
          for (final row in _raw)
            _TrendPoint(
              label: '${row.logDate.month}/${row.logDate.day}',
              actual: row.actualOutput.toDouble(),
              ceiling: row.effectiveCeiling,
            ),
        ];
      case _Granularity.rollingWeek:
        return _rollingWeekPoints();
      case _Granularity.month:
        return _monthlyPoints();
    }
  }

  List<_TrendPoint> _rollingWeekPoints() {
    if (_raw.isEmpty) return [];
    final byDate = {for (final row in _raw) _dateKey(row.logDate): row};
    final last = _dateOnly(_raw.last.logDate);
    final points = <_TrendPoint>[];
    for (var i = 29; i >= 0; i--) {
      final anchor = last.subtract(Duration(days: i));
      final windowRows = <DailyProduction>[];
      for (var d = 0; d < 7; d++) {
        final day = anchor.subtract(Duration(days: d));
        final row = byDate[_dateKey(day)];
        if (row != null) windowRows.add(row);
      }
      if (windowRows.isEmpty) continue;
      final avgActual =
          windowRows.fold<double>(0, (sum, r) => sum + r.actualOutput) /
          windowRows.length;
      final ceilingRows = windowRows
          .where((r) => r.effectiveCeiling != null)
          .toList();
      final avgCeiling = ceilingRows.isEmpty
          ? null
          : ceilingRows.fold<double>(0, (sum, r) => sum + r.effectiveCeiling!) /
                ceilingRows.length;
      points.add(
        _TrendPoint(
          label: '${anchor.month}/${anchor.day}',
          actual: avgActual,
          ceiling: avgCeiling,
        ),
      );
    }
    return points;
  }

  List<_TrendPoint> _monthlyPoints() {
    if (_raw.isEmpty) return [];
    final byMonth = <String, List<DailyProduction>>{};
    for (final row in _raw) {
      final key =
          '${row.logDate.year}-${row.logDate.month.toString().padLeft(2, '0')}';
      byMonth.putIfAbsent(key, () => []).add(row);
    }
    final sortedKeys = byMonth.keys.toList()..sort();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return [
      for (final key in sortedKeys) _monthPoint(key, byMonth[key]!, monthNames),
    ];
  }

  _TrendPoint _monthPoint(
    String key,
    List<DailyProduction> rows,
    List<String> monthNames,
  ) {
    final month = int.parse(key.split('-')[1]);
    final avgActual =
        rows.fold<double>(0, (sum, r) => sum + r.actualOutput) / rows.length;
    final ceilingRows = rows.where((r) => r.effectiveCeiling != null).toList();
    final avgCeiling = ceilingRows.isEmpty
        ? null
        : ceilingRows.fold<double>(0, (sum, r) => sum + r.effectiveCeiling!) /
              ceilingRows.length;
    return _TrendPoint(
      label: monthNames[month - 1],
      actual: avgActual,
      ceiling: avgCeiling,
    );
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  String? get _summaryLine {
    final last30 = _raw.where(
      (row) => row.logDate.isAfter(
        DateTime.now().subtract(const Duration(days: 30)),
      ),
    );
    final counts = <String, int>{};
    for (final row in last30) {
      final label = _bottleneckLabel(row.bottleneck);
      if (label == null) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final dominant = counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return '${dominant.key}-bound on ${dominant.value} of the last 30 days';
  }

  String? _bottleneckLabel(String? resource) {
    switch (resource) {
      case 'MACHINE':
        return 'Machine';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Production trend')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLogging ? null : _openLogDialog,
        icon: const Icon(Icons.add),
        label: const Text('Log production'),
      ),
    );
  }

  Widget _buildBody() {
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
    final points = _points;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SegmentedButton<_Granularity>(
              segments: const [
                ButtonSegment(value: _Granularity.day, label: Text('Day')),
                ButtonSegment(
                  value: _Granularity.rollingWeek,
                  label: Text('7-day avg'),
                ),
                ButtonSegment(value: _Granularity.month, label: Text('Month')),
              ],
              selected: {_granularity},
              onSelectionChanged: (selection) =>
                  _setGranularity(selection.first),
            ),
          ),
          const SizedBox(height: 16),
          if (_summaryLine != null)
            InfoBanner(message: _summaryLine!, status: AppStatus.warning),
          const SizedBox(height: 16),
          if (points.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: EmptyState(
                icon: Icons.show_chart,
                message:
                    'No production logged yet. Use "Log production" to start tracking output against your daily ceiling.',
              ),
            )
          else
            _buildChartCard(points),
          if (_downtimeRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildDowntimeCard(),
          ],
        ],
      ),
    );
  }

  /// Factory-level daily downtime — the spec's own wording asks for this
  /// "per machine," but downtime_hours only exists on daily_production (one
  /// total per factory per day, from Priority 3). There's no per-machine
  /// downtime data anywhere in the schema, so this is a daily total with a
  /// "worst day" flag instead of a per-machine breakdown.
  List<DailyProduction> get _downtimeRows {
    final since = DateTime.now().subtract(const Duration(days: 30));
    return _raw.where((row) => row.logDate.isAfter(since)).toList()
      ..sort((a, b) => a.logDate.compareTo(b.logDate));
  }

  Widget _buildDowntimeCard() {
    final rows = _downtimeRows;
    final totalDowntime = rows.fold<double>(
      0,
      (sum, r) => sum + r.downtimeHours,
    );
    final worst = rows.reduce(
      (a, b) => a.downtimeHours >= b.downtimeHours ? a : b,
    );
    final maxDowntime = rows
        .map((r) => r.downtimeHours)
        .fold<double>(0, (m, v) => v > m ? v : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downtime (last 30 days)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Factory-level daily total — no per-machine breakdown exists in the schema.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (worst.downtimeHours > 0)
              InfoBanner(
                message:
                    'Worst day: ${worst.logDate.year}-'
                    '${worst.logDate.month.toString().padLeft(2, '0')}-'
                    '${worst.logDate.day.toString().padLeft(2, '0')} — '
                    '${worst.downtimeHours.toStringAsFixed(1)}h '
                    '(${totalDowntime.toStringAsFixed(1)}h total)',
                status: AppStatus.warning,
              )
            else
              const Text('No downtime logged in this window.'),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final row in rows)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: maxDowntime > 0
                              ? (row.downtimeHours / maxDowntime * 72).clamp(
                                  2.0,
                                  72.0,
                                )
                              : 2.0,
                          decoration: BoxDecoration(
                            color: row == worst && worst.downtimeHours > 0
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
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

  Widget _buildChartCard(List<_TrendPoint> points) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _legendDot(
                  'Actual output',
                  Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                _legendDot('Ceiling', Theme.of(context).colorScheme.onSurface),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
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
                        reservedSize: 28,
                        interval: (points.length / 6).ceilToDouble().clamp(
                          1,
                          double.infinity,
                        ),
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              points[index].label,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < points.length; i++)
                          if (points[i].actual != null)
                            FlSpot(i.toDouble(), points[i].actual!),
                      ],
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < points.length; i++)
                          if (points[i].ceiling != null)
                            FlSpot(i.toDouble(), points[i].ceiling!),
                      ],
                      isCurved: true,
                      color: Theme.of(context).colorScheme.onSurface,
                      barWidth: 2,
                      dashArray: [6, 4],
                      dotData: const FlDotData(show: false),
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
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
