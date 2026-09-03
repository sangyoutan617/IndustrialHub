import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/bom_entry.dart';
import '../../models/daily_production.dart';
import '../../models/factory.dart';
import '../../models/machine.dart';
import '../../models/manpower.dart';
import '../../models/product.dart';
import '../../models/raw_material.dart';
import '../../models/stock_movement.dart';
import '../../services/bom_service.dart';
import '../../services/daily_production_service.dart';
import '../../services/machine_service.dart';
import '../../services/manpower_service.dart';
import '../../services/material_movement_service.dart';
import '../../services/material_service.dart';
import '../../services/product_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

enum _Granularity { day, rollingWeek, month }

enum _LoadState { loading, error, noProducts, ready }

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

class _DowntimeBar {
  final String label;
  final double hours;

  const _DowntimeBar(this.label, this.hours);
}

class _ProductionTrendScreenState extends State<ProductionTrendScreen> {
  final _service = DailyProductionService();
  final _materialService = MaterialService();
  final _movementService = MaterialMovementService();
  final _productService = ProductService();
  final _bomService = BomService();
  final _stockService = StockService();
  final _machineService = MachineService();
  final _manpowerService = ManpowerService();

  static const _allProductsId = -1;

  _LoadState _state = _LoadState.loading;
  _Granularity _granularity = _Granularity.day;
  List<DailyProduction> _raw = [];
  List<Product> _products = [];
  Map<int, double> _maxDowntimeByProduct = {};
  int? _selectedProductId;
  bool _isLogging = false;

  bool get _isViewingAll => _selectedProductId == _allProductsId;

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
      final products = await _productService.getProducts(
        widget.factory.factoryId,
      );
      if (!mounted) return;
      if (products.isEmpty) {
        setState(() {
          _products = products;
          _state = _LoadState.noProducts;
        });
        return;
      }
      final productId =
          _selectedProductId ??
          products
              .firstWhere((p) => !p.isGeneral, orElse: () => products.first)
              .productId;
      final rows = productId == _allProductsId
          ? await _service.getTrendAllProducts(
              widget.factory.factoryId,
              days: _fetchDays,
            )
          : await _service.getTrend(
              widget.factory.factoryId,
              productId: productId,
              days: _fetchDays,
            );
      final machines = await _machineService.getMachines(
        widget.factory.factoryId,
      );
      final shifts = await _manpowerService.getShifts(widget.factory.factoryId);
      if (!mounted) return;
      setState(() {
        _products = products;
        _selectedProductId = productId;
        _raw = rows;
        _maxDowntimeByProduct = {
          for (final p in products)
            p.productId: ?_maxDowntimeFor(p.productId, machines, shifts),
        };
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  double? _maxDowntimeFor(
    int productId,
    List<Machine> machines,
    List<Manpower> shifts,
  ) {
    final machineHours = machines
        .where((m) => m.productId == productId)
        .fold<double>(0, (s, m) => s + m.operatingHoursPerDay * m.unitCount);
    final workerHours = shifts
        .where((s) => s.productId == productId)
        .fold<double>(0, (s, m) => s + m.workerCount * m.shiftHours);
    final positives = [
      machineHours,
      workerHours,
    ].where((v) => v > 0).toList();
    if (positives.isEmpty) return null;
    return positives.reduce((a, b) => a < b ? a : b);
  }

  String get _granularityLabel => switch (_granularity) {
    _Granularity.day => 'Day',
    _Granularity.rollingWeek => '7-day avg',
    _Granularity.month => 'Month',
  };

  void _setGranularity(_Granularity granularity) {
    if (granularity == _granularity) return;
    setState(() => _granularity = granularity);
    _load();
  }

  void _setProduct(int? productId) {
    if (productId == null || productId == _selectedProductId) return;
    setState(() => _selectedProductId = productId);
    _load();
  }

  Future<void> _openLogDialog() async {
    final result = await showDialog<_LogProductionResult>(
      context: context,
      builder: (_) => _LogProductionDialog(
        products: _products,
        initialProductId: _isViewingAll ? null : _selectedProductId,
        maxDowntimeByProduct: _maxDowntimeByProduct,
      ),
    );
    if (result == null) return;

    setState(() => _isLogging = true);
    try {
      final previous = await _service.getForDate(
        factoryId: widget.factory.factoryId,
        productId: result.productId,
        logDate: result.logDate,
      );
      final previousOutput = previous?.actualOutput ?? 0;

      await _service.logProduction(
        factoryId: widget.factory.factoryId,
        productId: result.productId,
        logDate: result.logDate,
        actualOutput: result.actualOutput,
        downtimeHours: result.downtimeHours,
      );
      final delta = result.actualOutput - previousOutput;
      if (delta != 0) {
        await _consumeMaterials(result.productId, delta, result.logDate);
        await _updateFinishedStock(result.productId, delta, result.logDate);
      }
      setState(() => _selectedProductId = result.productId);
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

  Future<void> _consumeMaterials(
    int productId,
    int unitsDelta,
    DateTime date,
  ) async {
    try {
      final results = await Future.wait<dynamic>([
        _materialService.getMaterials(widget.factory.factoryId),
        _bomService.getBom(productId),
      ]);
      final materials = results[0] as List<RawMaterial>;
      final bom = results[1] as List<BomEntry>;
      final skipped = await _movementService.recordProductionConsumption(
        factoryId: widget.factory.factoryId,
        materials: materials,
        bom: bom,
        unitsDelta: unitsDelta,
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

  Future<void> _updateFinishedStock(
    int productId,
    int unitsDelta,
    DateTime date,
  ) async {
    try {
      final product = _products.firstWhere((p) => p.productId == productId);
      final stock = await _stockService.getOrCreateStockForProduct(
        widget.factory.factoryId,
        product,
      );
      if (unitsDelta > 0) {
        await _stockService.recordMovement(
          stockId: stock.stockId,
          movementType: StockMovementType.productionIn,
          quantity: unitsDelta,
          movementDate: date,
          note: 'Logged production',
          factoryId: widget.factory.factoryId,
        );
      } else {
        await _stockService.recordMovement(
          stockId: stock.stockId,
          movementType: StockMovementType.adjustment,
          quantity: unitsDelta,
          movementDate: date,
          note: 'Production correction',
          factoryId: widget.factory.factoryId,
        );
      }
    } catch (e) {
      if (mounted && e.toString().contains('below zero')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Output lowered, but finished stock is already too low to '
              'match — adjust stock manually.',
            ),
          ),
        );
      }
      debugPrint('capacity: finished-stock update failed: $e');
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

  static const _monthNames = [
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

  List<_DowntimeBar> get _downtimeBars {
    switch (_granularity) {
      case _Granularity.day:
        return [
          for (final r in _raw)
            _DowntimeBar(
              '${r.logDate.month}/${r.logDate.day}',
              r.downtimeHours,
            ),
        ];
      case _Granularity.rollingWeek:
        final byWeek = <DateTime, double>{};
        for (final r in _raw) {
          final d = _dateOnly(r.logDate);
          final monday = d.subtract(Duration(days: d.weekday - 1));
          byWeek[monday] = (byWeek[monday] ?? 0) + r.downtimeHours;
        }
        final keys = byWeek.keys.toList()..sort();
        return [
          for (final k in keys) _DowntimeBar('${k.month}/${k.day}', byWeek[k]!),
        ];
      case _Granularity.month:
        final byMonth = <String, double>{};
        for (final r in _raw) {
          final key =
              '${r.logDate.year}-${r.logDate.month.toString().padLeft(2, '0')}';
          byMonth[key] = (byMonth[key] ?? 0) + r.downtimeHours;
        }
        final keys = byMonth.keys.toList()..sort();
        return [
          for (final k in keys)
            _DowntimeBar(
              _monthNames[int.parse(k.split('-')[1]) - 1],
              byMonth[k]!,
            ),
        ];
    }
  }

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
      floatingActionButton: _state == _LoadState.noProducts
          ? null
          : FloatingActionButton.extended(
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
      case _LoadState.noProducts:
        return const EmptyState(
          icon: Icons.category_outlined,
          message:
              'No products yet — add a product first, production is logged '
              'against one.',
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final points = _points;
    final downtimeBars = _downtimeBars;
    final hasDowntime = downtimeBars.any((b) => b.hours > 0);

    final headerSection = Column(
      children: [
        AppDropdownField<int>(
          idPrefix: 'product',
          label: 'Product',
          required: false,
          value: _selectedProductId,
          entries: [
            const DropdownMenuEntry(
              value: _allProductsId,
              label: 'All products (combined)',
            ),
            for (final product in _products)
              DropdownMenuEntry(
                value: product.productId,
                label: product.isGeneral
                    ? '${product.productName} (auto-created)'
                    : product.productName,
              ),
          ],
          onChanged: _setProduct,
        ),
        const SizedBox(height: 16),
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
            onSelectionChanged: (selection) => _setGranularity(selection.first),
          ),
        ),
        if (_summaryLine != null) ...[
          const SizedBox(height: 16),
          InfoBanner(message: _summaryLine!, status: AppStatus.warning),
        ],
      ],
    );

    final chartSection = points.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(
              icon: Icons.show_chart,
              message:
                  'No production logged yet. Use "Log production" to start tracking output against your daily ceiling.',
            ),
          )
        : _buildChartCard(points);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          headerSection,
          const SizedBox(height: 16),
          chartSection,
          if (hasDowntime) ...[
            const SizedBox(height: 16),
            _buildDowntimeCard(downtimeBars),
          ],
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  void _showDowntimeBarDetail(_DowntimeBar bar) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bar.hours > 0
              ? '${bar.label} — ${bar.hours.toStringAsFixed(1)}h downtime'
              : '${bar.label} — no downtime',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildDowntimeCard(List<_DowntimeBar> bars) {
    final maxHours = bars
        .map((b) => b.hours)
        .fold<double>(0, (m, v) => v > m ? v : m);
    final total = bars.fold<double>(0, (sum, b) => sum + b.hours);
    final peak = bars.reduce((a, b) => a.hours >= b.hours ? a : b);
    final labelEvery = (bars.length / 10).ceil().clamp(1, 999);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downtime · $_granularityLabel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _granularity == _Granularity.day
                  ? 'Machine-hours lost per day, as keyed in when logging production.'
                  : 'Total machine-hours lost per ${_granularity == _Granularity.month ? 'month' : 'week'}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            InfoBanner(
              message:
                  'Peak: ${peak.label} — ${peak.hours.toStringAsFixed(1)}h  ·  '
                  '${total.toStringAsFixed(1)}h total',
              status: AppStatus.warning,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < bars.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showDowntimeBarDetail(bars[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: maxHours > 0
                                    ? (bars[i].hours / maxHours * 92).clamp(
                                        bars[i].hours > 0 ? 3.0 : 0.0,
                                        92.0,
                                      )
                                    : 0.0,
                                decoration: BoxDecoration(
                                  color: bars[i] == peak && peak.hours > 0
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 44,
                                child:
                                    (bars[i].hours > 0 || i % labelEvery == 0)
                                    ? Transform.rotate(
                                        angle: -0.9,
                                        alignment: Alignment.topRight,
                                        child: Text(
                                          bars[i].label,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.visible,
                                          style: const TextStyle(fontSize: 7),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
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
              height: 260,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideVertically: true,
                      fitInsideHorizontally: true,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final i = spot.x.toInt();
                          final label = i >= 0 && i < points.length
                              ? points[i].label
                              : '';
                          final name = spot.barIndex == 0
                              ? 'Actual'
                              : 'Ceiling';
                          return LineTooltipItem(
                            '$label  ·  $name ${spot.y.toStringAsFixed(0)}',
                            const TextStyle(color: Colors.white, fontSize: 11),
                          );
                        }).toList();
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
                      sideTitles: SideTitles(
                        showTitles: false,
                        reservedSize: 0,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 ||
                              index >= points.length ||
                              (value - index).abs() > 0.01) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Transform.rotate(
                              angle: -1.0,
                              alignment: Alignment.topCenter,
                              child: Text(
                                points[index].label,
                                style: const TextStyle(fontSize: 8),
                              ),
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
                      isCurved: false,
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
                      isCurved: false,
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

class _LogProductionResult {
  final int productId;
  final DateTime logDate;
  final int actualOutput;
  final double downtimeHours;

  const _LogProductionResult({
    required this.productId,
    required this.logDate,
    required this.actualOutput,
    required this.downtimeHours,
  });
}

class _LogProductionDialog extends StatefulWidget {
  final List<Product> products;
  final int? initialProductId;
  final Map<int, double> maxDowntimeByProduct;

  const _LogProductionDialog({
    required this.products,
    required this.maxDowntimeByProduct,
    this.initialProductId,
  });

  @override
  State<_LogProductionDialog> createState() => _LogProductionDialogState();
}

class _LogProductionDialogState extends State<_LogProductionDialog> {
  final _outputController = TextEditingController();
  final _downtimeController = TextEditingController(text: '0');
  final _formKey = GlobalKey<FormState>();
  DateTime _logDate = DateTime.now();
  late int? _selectedProductId =
      widget.initialProductId ??
      (widget.products.isEmpty ? null : widget.products.first.productId);

  @override
  void dispose() {
    _outputController.dispose();
    _downtimeController.dispose();
    super.dispose();
  }

  double? get _downtimeCap => _selectedProductId == null
      ? null
      : widget.maxDowntimeByProduct[_selectedProductId];

  String _formatHours(double h) =>
      h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _logDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _logDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) return;
    Navigator.pop(
      context,
      _LogProductionResult(
        productId: _selectedProductId!,
        logDate: _logDate,
        actualOutput: int.parse(_outputController.text.trim()),
        downtimeHours: double.tryParse(_downtimeController.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log production'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppDropdownField<int>(
                idPrefix: 'log-product',
                label: 'Product',
                value: _selectedProductId,
                entries: [
                  for (final product in widget.products)
                    DropdownMenuEntry(
                      value: product.productId,
                      label: product.isGeneral
                          ? '${product.productName} (auto-created)'
                          : product.productName,
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedProductId = value),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  '${_logDate.year}-${_logDate.month.toString().padLeft(2, '0')}-${_logDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _outputController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Actual output'),
                validator: (v) {
                  final parsed = int.tryParse((v ?? '').trim());
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative whole number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _downtimeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Total downtime hours',
                  helperText: _downtimeCap != null
                      ? 'At most ${_formatHours(_downtimeCap!)} h (machine/worker hours available that day)'
                      : null,
                ),
                validator: (v) {
                  final trimmed = (v ?? '').trim();
                  if (trimmed.isEmpty) return null;
                  final parsed = double.tryParse(trimmed);
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative number';
                  }
                  final cap = _downtimeCap;
                  if (cap != null && parsed > cap) {
                    return 'At most ${_formatHours(cap)} h for this product';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
