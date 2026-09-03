import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/factory.dart';
import '../../models/product.dart';
import '../../services/bottleneck_service.dart';
import '../../services/capacity_service.dart';
import '../../services/data_event_service.dart';
import '../../services/product_service.dart';
import '../../widgets/ai_insight_card.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import '../products/product_list_screen.dart';
import 'benchmark_screen.dart';
import 'machine_list_screen.dart';
import 'manpower_list_screen.dart';
import 'production_trend_screen.dart';
import 'simulator_screen.dart';

class CapacityDashboardScreen extends StatefulWidget {
  final Factory factory;

  const CapacityDashboardScreen({super.key, required this.factory});

  @override
  State<CapacityDashboardScreen> createState() =>
      _CapacityDashboardScreenState();
}

enum _LoadState { loading, error, noProducts, ready }

class _CapacityDashboardScreenState extends State<CapacityDashboardScreen> {
  final _capacityService = CapacityService();
  final _productService = ProductService();
  final _bottleneckService = BottleneckService();
  _LoadState _state = _LoadState.loading;
  CapacitySnapshot? _snapshot;
  List<Product> _products = [];
  List<ProductBottleneck> _allBottlenecks = [];
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _load();
    DataEventService.instance.changeEvent.addListener(_onDataEvent);
  }

  @override
  void didUpdateWidget(covariant CapacityDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factory.factoryId != widget.factory.factoryId) {
      _selectedProductId = null;
      _load();
    }
  }

  @override
  void dispose() {
    DataEventService.instance.changeEvent.removeListener(_onDataEvent);
    super.dispose();
  }

  void _onDataEvent() {
    final event = DataEventService.instance.changeEvent.value;
    if (mounted && event != null && event.factoryId == widget.factory.factoryId) {
      _load();
    }
  }

  Product _defaultProduct(List<Product> products) =>
      products.firstWhere((p) => !p.isGeneral, orElse: () => products.first);

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _productService.getProducts(
        widget.factory.factoryId,
      );
      if (products.isEmpty) {
        setState(() {
          _products = products;
          _state = _LoadState.noProducts;
        });
        return;
      }
      final selected = _selectedProductId != null
          ? products.firstWhere(
              (p) => p.productId == _selectedProductId,
              orElse: () => _defaultProduct(products),
            )
          : _defaultProduct(products);

      final snapshot = await _capacityService.getSnapshot(
        widget.factory.factoryId,
        productId: selected.productId,
      );
      final bottlenecks = await Future.wait(
        products.map(
          (p) => _bottleneckService.computeForProduct(
            widget.factory.factoryId,
            p.productId,
          ),
        ),
      );
      final allBottlenecks = [
        for (var i = 0; i < products.length; i++)
          ProductBottleneck(product: products[i], bottleneck: bottlenecks[i]),
      ];
      setState(() {
        _products = products;
        _selectedProductId = selected.productId;
        _snapshot = snapshot;
        _allBottlenecks = allBottlenecks;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  void _setProduct(int? productId) {
    if (productId == null || productId == _selectedProductId) return;
    setState(() => _selectedProductId = productId);
    _load();
  }

  Future<void> _navigateAndRefresh(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load capacity data. Please try again.',
          onRetry: _load,
        );
      case _LoadState.noProducts:
        return const EmptyState(
          icon: Icons.category_outlined,
          message:
              'No products yet — add a product first, capacity is tracked '
              'per product.',
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Product get _selectedProduct =>
      _products.firstWhere((p) => p.productId == _selectedProductId);

  Widget _productPicker() {
    return AppDropdownField<int>(
      idPrefix: 'product',
      label: 'Product',
      required: false,
      value: _selectedProductId,
      entries: [
        for (final product in _products)
          DropdownMenuEntry(
            value: product.productId,
            label: product.isGeneral
                ? '${product.productName} (auto-created)'
                : product.productName,
          ),
      ],
      onChanged: _setProduct,
    );
  }

  Widget _buildReady() {
    final snapshot = _snapshot!;
    final isMachineLimiting =
        snapshot.machineCapacity <= 0 && snapshot.manpowerCapacity <= 0
        ? null
        : snapshot.machineCapacity <= snapshot.manpowerCapacity;

    final aiInsight = AiInsightCard(
      cacheKey: 'capacity.${widget.factory.factoryId}.$_selectedProductId',
      buildPrompt: () => _buildBottleneckPrompt(snapshot),
      system: _bottleneckSystem,
    );

    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          return _buildLandscape(
            snapshot: snapshot,
            isMachineLimiting: isMachineLimiting,
            aiInsight: aiInsight,
          );
        }
        return _buildPortrait(
          snapshot: snapshot,
          isMachineLimiting: isMachineLimiting,
          aiInsight: aiInsight,
        );
      },
    );
  }

  Widget _buildPortrait({
    required CapacitySnapshot snapshot,
    required bool? isMachineLimiting,
    required Widget aiInsight,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _productPicker(),
          const SizedBox(height: 16),
          _buildCeilingCard(snapshot, isMachineLimiting),
          const SizedBox(height: 16),
          aiInsight,
          const SizedBox(height: 16),
          ..._buildActionItems(snapshot),
        ],
      ),
    );
  }

  Widget _buildLandscape({
    required CapacitySnapshot snapshot,
    required bool? isMachineLimiting,
    required Widget aiInsight,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          _productPicker(),
          const SizedBox(height: 16),
          _buildCeilingCard(snapshot, isMachineLimiting),
          const SizedBox(height: 16),
          aiInsight,
          const SizedBox(height: 16),
          ..._buildActionItems(snapshot),
        ],
      ),
    );
  }

  Widget _buildCeilingCard(CapacitySnapshot snapshot, bool? isMachineLimiting) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.speed,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text(
                  AppLocalizations.of(context).capacityDailyCeiling,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              formatUnits(snapshot.effectiveCapacity),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _capacityBar(
                    label: 'Machine',
                    value: snapshot.machineCapacity,
                    maxValue: [
                      snapshot.machineCapacity,
                      snapshot.manpowerCapacity,
                      1.0,
                    ].reduce((a, b) => a > b ? a : b),
                    isLimiter: isMachineLimiting == true,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _capacityBar(
                    label: 'Labour',
                    value: snapshot.manpowerCapacity,
                    maxValue: [
                      snapshot.machineCapacity,
                      snapshot.manpowerCapacity,
                      1.0,
                    ].reduce((a, b) => a > b ? a : b),
                    isLimiter: isMachineLimiting == false,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionItems(CapacitySnapshot snapshot) {
    return [
      Card(
        child: ListTile(
          leading: Icon(
            Icons.category_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Products'),
          subtitle: const Text(
            'What this factory makes — assign machines, manpower, and '
            'material requirements to each',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _navigateAndRefresh(
            ProductListScreen(factoryId: widget.factory.factoryId),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _navigateAndRefresh(
                MachineListScreen(factoryId: widget.factory.factoryId),
              ),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Machines'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _navigateAndRefresh(
                ManpowerListScreen(factoryId: widget.factory.factoryId),
              ),
              icon: const Icon(Icons.people_outline),
              label: const Text('Manpower'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _navigateAndRefresh(
          SimulatorScreen(factoryId: widget.factory.factoryId),
        ),
        icon: const Icon(Icons.tune),
        label: const Text('Open what-if simulator'),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: Icon(Icons.public, color: Theme.of(context).colorScheme.primary),
          title: const Text('Benchmark vs Malaysia'),
          subtitle: const Text('Compare against DOSM national data'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              _navigateAndRefresh(BenchmarkScreen(factory: widget.factory)),
        ),
      ),
      Card(
        child: ListTile(
          leading: Icon(Icons.show_chart, color: Theme.of(context).colorScheme.primary),
          title: const Text('Production trend'),
          subtitle: const Text('Daily output vs ceiling over time'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              _navigateAndRefresh(ProductionTrendScreen(factory: widget.factory)),
        ),
      ),
    ];
  }

  static const _bottleneckSystem =
      'You are a factory capacity assistant. You are given figures that '
      'have already been computed — never invent or recalculate numbers. '
      'In 2-3 short, plain-language sentences for a factory manager, say '
      'how many of this factory\'s products are meeting demand and name '
      'the one most short, then give one concrete, actionable next step '
      'based only on the numbers provided. No markdown, no headings, '
      'under 80 words.';

  String _resourceLabel(String resource) {
    switch (resource) {
      case 'MACHINE':
        return 'Machine';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return resource;
    }
  }

  String _buildBottleneckPrompt(CapacitySnapshot snapshot) {
    final withData = _allBottlenecks.where((p) => p.bottleneck.hasData).toList();
    final noDataCount = _allBottlenecks.length - withData.length;
    final short = withData.where((p) => !p.bottleneck.canMeetDemand).toList()
      ..sort(
        (a, b) => (b.bottleneck.shortfall ?? 0).compareTo(
          a.bottleneck.shortfall ?? 0,
        ),
      );

    final buffer = StringBuffer()
      ..writeln('Products tracked: ${_allBottlenecks.length}')
      ..writeln(
        'Meeting demand: ${withData.length - short.length} of ${withData.length}',
      );
    if (noDataCount > 0) {
      buffer.writeln('Products with no capacity data yet: $noDataCount');
    }
    for (final pb in withData) {
      final r = pb.bottleneck;
      final line = StringBuffer(
        '- ${pb.product.productName}: ${formatUnits(r.achievable)}/day achievable',
      );
      if (r.requiredPerDay > 0) {
        line.write(' vs ${formatUnits(r.requiredPerDay)}/day required');
      }
      line.write(
        r.canMeetDemand
            ? ' (meeting demand)'
            : ' (short by ${formatUnits(r.shortfall ?? 0)}/day, '
                  '${_resourceLabel(r.limiter ?? r.bottleneckResource)} limited)',
      );
      buffer.writeln(line.toString());
    }

    final gap = CapacityService.computeHiringGap(snapshot);
    buffer.writeln(
      'Currently viewing: ${_selectedProduct.productName} — '
      '${gap.currentWorkers} total workers',
    );
    if (gap.additionalWorkersNeeded != null) {
      buffer.writeln(
        'Hiring ${gap.additionalWorkersNeeded} more worker(s) at the '
        'current average output rate would remove this product\'s labour '
        'bottleneck.',
      );
    } else if (gap.bottleneck == 'MANPOWER') {
      buffer.writeln(
        'Labour is this product\'s bottleneck, but there is not enough '
        'shift data to size a hiring recommendation.',
      );
    }
    return buffer.toString();
  }

  Widget _capacityBar({
    required String label,
    required double value,
    required double maxValue,
    required bool isLimiter,
    required Color color,
  }) {
    const maxHeight = 90.0;
    final height = maxValue > 0
        ? (value / maxValue * maxHeight).clamp(6.0, maxHeight)
        : 6.0;
    return Column(
      children: [
        if (isLimiter)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: StatusChip(
              label: 'Limiter',
              status: AppStatus.warning,
              dense: true,
            ),
          ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatNumber(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
