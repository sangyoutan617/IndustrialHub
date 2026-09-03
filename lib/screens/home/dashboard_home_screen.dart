import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../models/factory.dart';
import '../../models/msic_code.dart';
import '../../models/product.dart';
import '../../models/productivity_benchmark.dart';
import '../../services/bottleneck_service.dart';
import '../../services/capacity_service.dart';
import '../../services/data_event_service.dart';
import '../../services/product_service.dart';
import '../../widgets/ai_insight_card.dart';
import '../capacity/benchmark_screen.dart';
import '../capacity/machine_list_screen.dart';
import '../capacity/manpower_list_screen.dart';
import '../stock/stock_dashboard_screen.dart';
import '../supply/material_list_screen.dart';
import '../supply/order_form_screen.dart';
import '../supply/supplier_list_screen.dart';

class _Palette {
  final Color bg;
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color alert;
  final Color ok;
  final Color neutral;

  const _Palette({
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.alert,
    required this.ok,
    required this.neutral,
  });

  factory _Palette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _Palette(
      bg: Theme.of(context).scaffoldBackgroundColor,
      card: isDark ? scheme.surfaceContainerHigh : Colors.white,
      cardBorder: scheme.outlineVariant,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      alert: scheme.error,
      ok: scheme.primary,
      neutral: scheme.onSurface,
    );
  }
}

class _HomeData {
  final BottleneckResult bottleneck;
  final double? outputPerWorker;
  final MsicCode? msic;
  final ProductivityBenchmark? productivity;

  final List<Product> products;
  final Product selectedProduct;
  final bool isAll;

  final List<ProductBottleneck> allBottlenecks;

  const _HomeData({
    required this.bottleneck,
    required this.outputPerWorker,
    required this.msic,
    required this.productivity,
    required this.products,
    required this.selectedProduct,
    required this.isAll,
    required this.allBottlenecks,
  });
}

class _AllSummary {
  final List<ProductBottleneck> withDemand;
  final double totalAchievable;
  final double totalDemand;
  final int meetingCount;
  final int noDataCount;
  final int noDemandCount;

  const _AllSummary({
    required this.withDemand,
    required this.totalAchievable,
    required this.totalDemand,
    required this.meetingCount,
    required this.noDataCount,
    required this.noDemandCount,
  });

  int get demandProductCount => withDemand.length;

  double get percentOfDemand =>
      totalDemand > 0 ? (totalAchievable / totalDemand) * 100 : 100;

  factory _AllSummary.from(List<ProductBottleneck> all) {
    final withDemand = [
      for (final p in all)
        if (p.bottleneck.hasData && p.bottleneck.requiredPerDay > 0) p,
    ];
    var totalAchievable = 0.0;
    var totalDemand = 0.0;
    var meeting = 0;
    for (final p in withDemand) {
      totalAchievable += p.bottleneck.achievable;
      totalDemand += p.bottleneck.requiredPerDay;
      if (p.bottleneck.canMeetDemand) meeting++;
    }
    return _AllSummary(
      withDemand: withDemand,
      totalAchievable: totalAchievable,
      totalDemand: totalDemand,
      meetingCount: meeting,
      noDataCount: all.where((p) => !p.bottleneck.hasData).length,
      noDemandCount: all
          .where(
            (p) => p.bottleneck.hasData && p.bottleneck.requiredPerDay <= 0,
          )
          .length,
    );
  }
}

class _SmartAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget Function() builder;

  const _SmartAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.builder,
  });
}

Widget _pushedWithAppBar(String title, Widget child) {
  return Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

class DashboardHomeScreen extends StatefulWidget {
  final Factory factory;

  const DashboardHomeScreen({super.key, required this.factory});

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen>
    with SingleTickerProviderStateMixin {
  final _bottleneckService = BottleneckService();
  final _capacityService = CapacityService();
  final _productService = ProductService();

  static const _allProductsId = -1;

  _HomeData? _data;
  Object? _loadError;
  late final AnimationController _pulseController;
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    DataEventService.instance.changeEvent.addListener(_onDataEvent);
  }

  @override
  void didUpdateWidget(covariant DashboardHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factory.factoryId != widget.factory.factoryId) {
      _selectedProductId = null;
      setState(() {
        _data = null;
        _loadError = null;
      });
      _refresh();
    }
  }

  void _onDataEvent() {
    final event = DataEventService.instance.changeEvent.value;
    if (mounted && event != null && event.factoryId == widget.factory.factoryId) {
      _refresh();
    }
  }

  @override
  void dispose() {
    DataEventService.instance.changeEvent.removeListener(_onDataEvent);
    _pulseController.dispose();
    super.dispose();
  }

  Product _defaultProduct(List<Product> products) =>
      products.firstWhere((p) => !p.isGeneral, orElse: () => products.first);

  Future<void> _refresh() async {
    try {
      final data = await _fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_data == null) setState(() => _loadError = e);
    }
  }

  Future<_HomeData> _fetch() async {
    final factoryId = widget.factory.factoryId;
    final products = await _productService.getProducts(factoryId);
    if (products.isEmpty) {
      throw StateError('No products configured for this factory.');
    }
    final isAll =
        products.length > 1 &&
        (_selectedProductId == null || _selectedProductId == _allProductsId);
    final selected = !isAll && _selectedProductId != null
        ? products.firstWhere(
            (p) => p.productId == _selectedProductId,
            orElse: () => _defaultProduct(products),
          )
        : _defaultProduct(products);
    if (!isAll) _selectedProductId = selected.productId;

    final bottleneck = await _bottleneckService.computeForProduct(
      factoryId,
      selected.productId,
    );

    final allResults = await Future.wait(
      products.map(
        (p) => _bottleneckService.computeForProduct(factoryId, p.productId),
      ),
    );
    final allBottlenecks = [
      for (var i = 0; i < products.length; i++)
        ProductBottleneck(product: products[i], bottleneck: allResults[i]),
    ];

    double? outputPerWorker;
    if (isAll) {
      final snapshots = await Future.wait(
        products.map(
          (p) =>
              _capacityService.getSnapshot(factoryId, productId: p.productId),
        ),
      );
      final totalWorkers = snapshots.fold<int>(
        0,
        (sum, s) =>
            sum + s.shifts.fold<int>(0, (w, shift) => w + shift.workerCount),
      );
      final totalCapacity = snapshots.fold<double>(
        0,
        (sum, s) => sum + s.effectiveCapacity,
      );
      outputPerWorker = totalWorkers == 0 ? null : totalCapacity / totalWorkers;
    } else {
      final snapshot = await _capacityService.getSnapshot(
        factoryId,
        productId: selected.productId,
      );
      outputPerWorker = _capacityService.outputPerWorker(snapshot);
    }

    MsicCode? msic;
    ProductivityBenchmark? productivity;
    final msicCode = widget.factory.msicCode;
    if (msicCode != null && msicCode.isNotEmpty) {
      msic = await _capacityService.getMsicByCode(msicCode);
      if (msic?.category != null) {
        productivity = await _capacityService.getProductivityBenchmark(
          msic!.category!,
        );
      }
    }

    return _HomeData(
      bottleneck: bottleneck,
      outputPerWorker: outputPerWorker,
      msic: msic,
      productivity: productivity,
      products: products,
      selectedProduct: selected,
      isAll: isAll,
      allBottlenecks: allBottlenecks,
    );
  }

  void _retry() => _refresh();

  void _setProduct(int? productId) {
    if (productId == null || productId == _selectedProductId) return;
    setState(() => _selectedProductId = productId);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pal = _Palette.of(context);
    return Container(
      color: pal.bg,
      child: SafeArea(
        top: false,
        child: _data != null
            ? _buildReady(_data!, pal)
            : _loadError != null
            ? _buildError(pal)
            : Center(child: CircularProgressIndicator(color: pal.neutral)),
      ),
    );
  }

  Widget _buildError(_Palette pal) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: pal.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Could not load the factory dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: pal.textPrimary),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildReady(_HomeData data, _Palette pal) {
    if (data.isAll) return _buildAllReady(data, pal);

    final result = data.bottleneck;
    final aiInsight = result.hasData
        ? AiInsightCard(
            cacheKey:
                'home.${widget.factory.factoryId}.${data.selectedProduct.productId}',
            buildPrompt: () => _buildProductPrompt(data),
            system: _productSystem,
          )
        : null;

    return _buildPortraitReady(result, data, pal, aiInsight);
  }

  Widget _buildAllReady(_HomeData data, _Palette pal) {
    final summary = _AllSummary.from(data.allBottlenecks);
    final hasAnyData = data.allBottlenecks.any((p) => p.bottleneck.hasData);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        RepaintBoundary(
          child: _buildHeader(data.bottleneck, data, pal, allSummary: summary),
        ),
        const SizedBox(height: 16),
        RepaintBoundary(child: _buildAllHeroCard(data, summary, pal)),
        const SizedBox(height: 16),
        if (hasAnyData) ...[
          AiInsightCard(
            cacheKey: 'home.${widget.factory.factoryId}.all',
            buildPrompt: () => _buildProductPrompt(data),
            system: _productSystem,
          ),
          const SizedBox(height: 16),
        ],
        RepaintBoundary(child: _buildOpenDataCard(data, pal)),
      ],
    );
  }

  Widget _buildPortraitReady(
    BottleneckResult result,
    _HomeData data,
    _Palette pal,
    Widget? aiInsight,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        RepaintBoundary(child: _buildHeader(result, data, pal)),
        const SizedBox(height: 16),
        RepaintBoundary(child: _buildHeroCard(result, pal)),
        const SizedBox(height: 16),
        RepaintBoundary(child: _buildCeilingGrid(result, pal)),
        const SizedBox(height: 16),
        if (aiInsight != null) ...[aiInsight, const SizedBox(height: 16)],
        RepaintBoundary(child: _buildOpenDataCard(data, pal)),
        const SizedBox(height: 16),
        RepaintBoundary(child: _buildActionCenter(result, pal)),
      ],
    );
  }

  static const _productSystem =
      'You are a factory operations assistant. You are given figures that '
      'have already been computed — never invent or recalculate numbers. In '
      '2-3 short, plain-language sentences for a factory manager, say how '
      'many of this factory\'s products are meeting demand and which single '
      'resource — raw material, machines, or manpower — is the binding '
      'constraint for the currently viewed product, then give one concrete '
      'next step based only on the numbers provided. No markdown, no '
      'headings, under 80 words.';

  String _buildProductPrompt(_HomeData data) {
    final withData = data.allBottlenecks
        .where((p) => p.bottleneck.hasData)
        .toList();
    final noDataCount = data.allBottlenecks.length - withData.length;
    final short = withData.where((p) => !p.bottleneck.canMeetDemand).toList()
      ..sort(
        (a, b) => (b.bottleneck.shortfall ?? 0).compareTo(
          a.bottleneck.shortfall ?? 0,
        ),
      );

    final buffer = StringBuffer()
      ..writeln('Products tracked: ${data.allBottlenecks.length}')
      ..writeln(
        'Meeting demand: ${withData.length - short.length} of ${withData.length}',
      );
    if (noDataCount > 0) {
      buffer.writeln('Products with no production data yet: $noDataCount');
    }
    for (final pb in withData) {
      final r = pb.bottleneck;
      final line = StringBuffer(
        '- ${pb.product.productName}: ${formatUnits(r.achievable)}/day '
        'achievable vs ${formatUnits(r.requiredPerDay)}/day required',
      );
      line.write(
        r.canMeetDemand
            ? ' (meeting demand)'
            : ' (short by ${formatUnits(r.shortfall ?? 0)}/day, '
                  '${_limiterLabel(r.limiter ?? r.bottleneckResource)} limited)',
      );
      buffer.writeln(line.toString());
    }

    if (data.isAll) {
      buffer.writeln('Currently viewing: all products combined');
    } else {
      final r = data.bottleneck;
      buffer
        ..writeln('Currently viewing: ${data.selectedProduct.productName}')
        ..writeln('Machine capacity: ${formatUnits(r.machineCapacity)}/day')
        ..writeln('Manpower capacity: ${formatUnits(r.manpowerCapacity)}/day')
        ..writeln(
          'Raw-material ceiling: ${r.materialCeiling != null ? '${formatUnits(r.materialCeiling!)}/day' : 'not set'}',
        );
    }
    return buffer.toString();
  }

  Widget _buildHeader(
    BottleneckResult result,
    _HomeData data,
    _Palette pal, {
    _AllSummary? allSummary,
  }) {
    final Color dotColor;
    final String label;
    if (allSummary != null) {
      final n = allSummary.demandProductCount;
      final healthy = n > 0 && allSummary.meetingCount == n;
      dotColor = n == 0 ? pal.textSecondary : (healthy ? pal.ok : pal.alert);
      label = n == 0
          ? 'No demand targets set'
          : '${allSummary.meetingCount} of $n products meeting demand';
    } else {
      final hasData = result.hasData;
      final healthy = hasData && result.canMeetDemand;
      dotColor = !hasData ? pal.textSecondary : (healthy ? pal.ok : pal.alert);
      label = !hasData
          ? 'Awaiting production data'
          : (healthy
                ? 'Operating within capacity'
                : 'Capacity bottleneck detected');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.factory.factoryName,
          style: TextStyle(
            color: pal.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatDate(DateTime.now()),
          style: TextStyle(color: pal.textSecondary, fontSize: 13),
        ),
        if (data.products.length > 1) ...[
          const SizedBox(height: 10),
          _buildProductPicker(data, pal),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pal.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(color: dotColor, controller: _pulseController),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: dotColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductPicker(_HomeData data, _Palette pal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: data.isAll ? _allProductsId : data.selectedProduct.productId,
          isExpanded: true,
          isDense: true,
          dropdownColor: pal.card,
          icon: Icon(Icons.expand_more, color: pal.textSecondary, size: 18),
          style: TextStyle(
            color: pal.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: [
            const DropdownMenuItem(
              value: _allProductsId,
              child: Text('All products'),
            ),
            for (final p in data.products)
              DropdownMenuItem(
                value: p.productId,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    p.isGeneral
                        ? '${p.productName} (auto-created)'
                        : p.productName,
                  ),
                ),
              ),
          ],
          onChanged: _setProduct,
        ),
      ),
    );
  }

  Widget _buildHeroCard(BottleneckResult result, _Palette pal) {
    if (!result.hasData) {
      return _card(
        pal: pal,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No production data yet. Add machines, manpower, materials '
            'and demand to activate the bottleneck engine.',
            style: TextStyle(color: pal.textSecondary, height: 1.4),
          ),
        ),
      );
    }

    final achievable = result.achievable;
    final demand = result.requiredPerDay;
    final ok = result.canMeetDemand;
    final statusColor = ok ? pal.ok : pal.alert;
    final limiterLabel = _limiterLabel(result.limiter);

    final metPortion = demand <= 0
        ? 0.0
        : (achievable < demand ? achievable : demand);
    final shortPortion = demand <= 0
        ? 0.0
        : (demand - achievable > 0 ? demand - achievable : 0.0);
    final ringPct = demand > 0 ? (achievable / demand) * 100 : 100.0;

    return _card(
      pal: pal,
      borderColor: ok ? null : pal.alert.withValues(alpha: 0.5),
      glow: !ok,
      glowColor: pal.alert,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 16, color: pal.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'BOTTLENECK DIAGNOSIS ENGINE',
                  style: TextStyle(
                    color: pal.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 48,
                        startDegreeOffset: -90,
                        pieTouchData: PieTouchData(enabled: false),
                        sections: demand <= 0
                            ? [
                                PieChartSectionData(
                                  value: 1,
                                  color: pal.cardBorder,
                                  showTitle: false,
                                  radius: 16,
                                ),
                              ]
                            : [
                                PieChartSectionData(
                                  value: metPortion,
                                  color: pal.ok,
                                  showTitle: false,
                                  radius: 16,
                                ),
                                if (shortPortion > 0)
                                  PieChartSectionData(
                                    value: shortPortion,
                                    color: pal.alert,
                                    showTitle: false,
                                    radius: 16,
                                  ),
                              ],
                      ),
                    ),
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${ringPct.clamp(0, 999).toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: pal.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'of demand',
                              style: TextStyle(
                                color: pal.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (demand > 0) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(pal.ok, 'Achievable', pal),
                  if (shortPortion > 0) ...[
                    const SizedBox(width: 16),
                    _legendDot(pal.alert, 'Shortfall', pal),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _statBlock(
                    'ACHIEVABLE OUTPUT',
                    formatUnits(achievable),
                    pal.neutral,
                    pal,
                  ),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 34, color: pal.cardBorder),
                const SizedBox(width: 12),
                Expanded(
                  child: _statBlock(
                    'DEMAND TARGET',
                    formatUnits(demand),
                    pal.textPrimary,
                    pal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    ok
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ok
                              ? 'MEETING DEMAND'
                              : 'BOTTLENECK: ${limiterLabel.toUpperCase()}',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (!ok && result.shortfall != null)
                          Text(
                            'Short by ${formatUnits(result.shortfall!)} / day',
                            style: TextStyle(
                              color: statusColor.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!ok) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _resolveNow(result),
                  style: FilledButton.styleFrom(
                    backgroundColor: pal.alert,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Resolve Now'),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _resolveHint(result.limiter),
                  style: TextStyle(color: pal.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAllHeroCard(_HomeData data, _AllSummary summary, _Palette pal) {
    if (summary.demandProductCount == 0) {
      return _card(
        pal: pal,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No demand targets set. Add a demand forecast for your products '
            'to see combined achievable output against demand.',
            style: TextStyle(color: pal.textSecondary, height: 1.4),
          ),
        ),
      );
    }

    final sections = <PieChartSectionData>[];
    for (final p in summary.withDemand) {
      final b = p.bottleneck;
      final met = (b.achievable / b.requiredPerDay).clamp(0.0, 1.0).toDouble();
      if (met > 0.001) {
        sections.add(
          PieChartSectionData(
            value: met,
            color: pal.ok,
            showTitle: false,
            radius: 16,
          ),
        );
      }
      if (1 - met > 0.001) {
        sections.add(
          PieChartSectionData(
            value: 1 - met,
            color: pal.alert,
            showTitle: false,
            radius: 16,
          ),
        );
      }
    }

    final allMet = summary.meetingCount == summary.demandProductCount;

    return _card(
      pal: pal,
      borderColor: allMet ? null : pal.alert.withValues(alpha: 0.5),
      glow: !allMet,
      glowColor: pal.alert,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 16, color: pal.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'BOTTLENECK DIAGNOSIS ENGINE',
                  style: TextStyle(
                    color: pal.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 48,
                        startDegreeOffset: -90,
                        pieTouchData: PieTouchData(enabled: false),
                        sections: sections,
                      ),
                    ),
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${summary.meetingCount}/${summary.demandProductCount}',
                              style: TextStyle(
                                color: pal.textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'meeting demand',
                              style: TextStyle(
                                color: pal.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(pal.ok, 'Achievable', pal),
                const SizedBox(width: 16),
                _legendDot(pal.alert, 'Shortfall', pal),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _statBlock(
                    'TOTAL ACHIEVABLE',
                    formatUnits(summary.totalAchievable),
                    pal.neutral,
                    pal,
                  ),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 34, color: pal.cardBorder),
                const SizedBox(width: 12),
                Expanded(
                  child: _statBlock(
                    'TOTAL DEMAND',
                    formatUnits(summary.totalDemand),
                    pal.textPrimary,
                    pal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final p in summary.withDemand) _allProductRow(p, pal),
            if (summary.noDataCount > 0 || summary.noDemandCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (summary.noDataCount > 0)
                    '${summary.noDataCount} not configured',
                  if (summary.noDemandCount > 0)
                    '${summary.noDemandCount} with no demand target',
                ].join('  ·  '),
                style: TextStyle(color: pal.textSecondary, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _allProductRow(ProductBottleneck p, _Palette pal) {
    final b = p.bottleneck;
    final ok = b.canMeetDemand;
    final color = ok ? pal.ok : pal.alert;
    return InkWell(
      onTap: () => _setProduct(p.product.productId),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.product.isGeneral
                    ? '${p.product.productName} (auto-created)'
                    : p.product.productName,
                style: TextStyle(
                  color: pal.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              ok
                  ? 'Meets demand'
                  : 'Short ${formatUnits(b.shortfall ?? 0)}/day',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: pal.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label, _Palette pal) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: pal.textSecondary, fontSize: 11)),
      ],
    );
  }

  void _resolveNow(BottleneckResult result) {
    final factoryId = widget.factory.factoryId;
    final Widget target = switch (result.limiter) {
      'RAW MATERIAL' => OrderFormScreen(factoryId: factoryId),
      'MACHINE' => MachineListScreen(factoryId: factoryId),
      'MANPOWER' => ManpowerListScreen(factoryId: factoryId),
      _ => MachineListScreen(factoryId: factoryId),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
  }

  String _resolveHint(String? limiter) {
    switch (limiter) {
      case 'RAW MATERIAL':
        return 'Opens Raise Purchase Order';
      case 'MACHINE':
        return 'Opens Machine List';
      case 'MANPOWER':
        return 'Opens Manpower & Shifts';
      default:
        return '';
    }
  }

  String _limiterLabel(String? limiter) {
    switch (limiter) {
      case 'MACHINE':
        return 'Machines';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return 'Unknown';
    }
  }

  Widget _statBlock(
    String label,
    String value,
    Color valueColor,
    _Palette pal,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: pal.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildCeilingGrid(BottleneckResult result, _Palette pal) {
    final isMaterialLimiter = result.limiter == 'RAW MATERIAL';
    final isCapacityLimiter =
        result.limiter == 'MACHINE' || result.limiter == 'MANPOWER';
    final capacityCeiling = result.machineCapacity < result.manpowerCapacity
        ? result.machineCapacity
        : result.manpowerCapacity;
    final capacitySubLabel = result.machineCapacity < result.manpowerCapacity
        ? 'Machines'
        : 'Manpower';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ceilingCard(
              pal: pal,
              icon: Icons.local_shipping,
              label: 'MATERIALS',
              moduleCaption: 'Raw material ceiling',
              numericValue: result.materialCeiling,
              isBottleneck: isMaterialLimiter,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ceilingCard(
              pal: pal,
              icon: Icons.precision_manufacturing,
              label: 'CAPACITY',
              moduleCaption: capacitySubLabel,
              numericValue: capacityCeiling,
              isBottleneck: isCapacityLimiter,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ceilingCard(
              pal: pal,
              icon: Icons.inventory_2,
              label: 'DEMAND',
              moduleCaption: 'Required / day',
              numericValue: result.requiredPerDay,
              isBottleneck: false,
              isDemand: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ceilingCard({
    required _Palette pal,
    required IconData icon,
    required String label,
    required String moduleCaption,
    required double? numericValue,
    required bool isBottleneck,
    bool isDemand = false,
  }) {
    final hasData = numericValue != null;
    final accent = isBottleneck ? pal.alert : (isDemand ? pal.neutral : pal.ok);

    return _card(
      pal: pal,
      borderColor: isBottleneck ? pal.alert.withValues(alpha: 0.6) : null,
      glow: isBottleneck,
      glowColor: pal.alert,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 12, color: accent),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: pal.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              hasData ? formatNumber(numericValue) : '—',
              style: TextStyle(
                color: hasData ? pal.textPrimary : pal.textSecondary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'units / day',
              style: TextStyle(color: pal.textSecondary, fontSize: 9.5),
            ),
            const SizedBox(height: 6),
            Text(
              moduleCaption,
              style: TextStyle(color: pal.textSecondary, fontSize: 10),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isBottleneck
                    ? 'BOTTLENECK'
                    : (isDemand ? 'TARGET' : (hasData ? 'OK' : 'NO DATA')),
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenDataCard(_HomeData data, _Palette pal) {
    final hasMsic =
        widget.factory.msicCode != null && widget.factory.msicCode!.isNotEmpty;

    return _card(
      pal: pal,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, size: 16, color: pal.neutral),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'OPEN DATA · DOSM MALAYSIA',
                    style: TextStyle(
                      color: pal.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!hasMsic)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Assign an industry code to compare against national '
                      'productivity data.',
                      style: TextStyle(
                        color: pal.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _openBenchmark,
                    style: TextButton.styleFrom(foregroundColor: pal.neutral),
                    child: const Text('Set up'),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _statBlock(
                      'YOUR OUTPUT / WORKER',
                      data.outputPerWorker != null
                          ? '${formatUnits(data.outputPerWorker!)}/day'
                          : '-',
                      pal.ok,
                      pal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statBlock(
                      'DOSM VALUE-ADDED / WORKER',
                      data.productivity?.valueAddedPerWorker != null
                          ? 'RM ${formatNumber(data.productivity!.valueAddedPerWorker!)}/yr'
                          : 'No benchmark',
                      pal.neutral,
                      pal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                data.productivity != null
                    ? 'Sector: ${data.productivity!.sector} '
                          '(${data.productivity!.year}) — different units, shown for context.'
                    : 'No DOSM benchmark found for this sector yet.',
                style: TextStyle(color: pal.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _openBenchmark,
                  style: TextButton.styleFrom(
                    foregroundColor: pal.neutral,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('View full benchmark →'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openBenchmark() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BenchmarkScreen(factory: widget.factory),
      ),
    );
  }

  Widget _buildActionCenter(BottleneckResult result, _Palette pal) {
    final actions = _actionsFor(result, pal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'SMART ACTIONS',
            style: TextStyle(
              color: pal.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
        for (final action in actions) ...[
          _actionTile(action, pal),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  List<_SmartAction> _actionsFor(BottleneckResult result, _Palette pal) {
    final factoryId = widget.factory.factoryId;
    if (!result.hasData) {
      return [
        _SmartAction(
          icon: Icons.precision_manufacturing,
          title: 'Add Machines',
          subtitle: 'Set up machine records to start tracking capacity',
          color: pal.neutral,
          builder: () => MachineListScreen(factoryId: factoryId),
        ),
      ];
    }
    switch (result.limiter) {
      case 'RAW MATERIAL':
        return [
          _SmartAction(
            icon: Icons.shopping_cart_checkout,
            title: 'Raise a Purchase Order',
            subtitle: 'Order more raw material before you run out',
            color: pal.alert,
            builder: () => OrderFormScreen(factoryId: factoryId),
          ),
          _SmartAction(
            icon: Icons.local_shipping_outlined,
            title: 'Check Supplier Lead Times',
            subtitle: 'See which supplier can deliver fastest',
            color: pal.neutral,
            builder: () => SupplierListScreen(factoryId: factoryId),
          ),
        ];
      case 'MACHINE':
        return [
          _SmartAction(
            icon: Icons.precision_manufacturing,
            title: 'Review Machine Status',
            subtitle: 'Check status and downtime across machines',
            color: pal.alert,
            builder: () => MachineListScreen(factoryId: factoryId),
          ),
          _SmartAction(
            icon: Icons.inventory_2_outlined,
            title: 'Check Material Cover',
            subtitle: "Confirm materials won't be the next bottleneck",
            color: pal.neutral,
            builder: () => _pushedWithAppBar(
              'Materials',
              MaterialListScreen(factoryId: factoryId),
            ),
          ),
        ];
      case 'MANPOWER':
        return [
          _SmartAction(
            icon: Icons.groups_outlined,
            title: 'Review Manpower & Shifts',
            subtitle: 'Check headcount and shift coverage',
            color: pal.alert,
            builder: () => ManpowerListScreen(factoryId: factoryId),
          ),
          _SmartAction(
            icon: Icons.inventory_2_outlined,
            title: 'Check Material Cover',
            subtitle: "Confirm materials won't be the next bottleneck",
            color: pal.neutral,
            builder: () => _pushedWithAppBar(
              'Materials',
              MaterialListScreen(factoryId: factoryId),
            ),
          ),
        ];
      default:
        return [
          _SmartAction(
            icon: Icons.trending_up,
            title: 'Review Demand Forecast',
            subtitle: 'Stay ahead of the next shift in demand',
            color: pal.ok,
            builder: () => _pushedWithAppBar(
              'Stock overview',
              StockDashboardScreen(factoryId: factoryId),
            ),
          ),
          _SmartAction(
            icon: Icons.local_shipping_outlined,
            title: 'Check Supplier Reliability',
            subtitle: 'Review supplier ratings before demand rises',
            color: pal.neutral,
            builder: () => SupplierListScreen(factoryId: factoryId),
          ),
        ];
    }
  }

  Widget _actionTile(_SmartAction action, _Palette pal) {
    return _card(
      pal: pal,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => action.builder())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(action.icon, color: action.color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        color: pal.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      style: TextStyle(color: pal.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: pal.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required _Palette pal,
    required Widget child,
    Color? borderColor,
    bool glow = false,
    Color? glowColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? pal.cardBorder,
          width: borderColor != null ? 1.4 : 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: (glowColor ?? pal.alert).withValues(alpha: 0.22),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final Color color;
  final AnimationController controller;

  const _PulsingDot({required this.color, required this.controller});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          return Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.5 + 0.5 * t),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35 * t),
                  blurRadius: 6 * t,
                  spreadRadius: t,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
