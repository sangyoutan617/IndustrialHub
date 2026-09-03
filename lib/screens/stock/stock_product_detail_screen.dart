import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../services/stock_service.dart';
import '../../widgets/error_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import '../../widgets/stock_movement_history_sheet.dart';
import 'stock_cover_loader.dart';
import 'stock_movement_form_screen.dart';

class StockProductDetailScreen extends StatefulWidget {
  final int factoryId;
  final int stockId;

  const StockProductDetailScreen({
    super.key,
    required this.factoryId,
    required this.stockId,
  });

  @override
  State<StockProductDetailScreen> createState() =>
      _StockProductDetailScreenState();
}

enum _LoadState { loading, error, notFound, ready }

class _StockProductDetailScreenState extends State<StockProductDetailScreen> {
  final _service = StockService();
  _LoadState _state = _LoadState.loading;
  ProductCover? _cover;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final overview = await loadStockOverview(widget.factoryId);
      if (!mounted) return;
      ProductCover? cover;
      for (final c in overview.covers) {
        if (c.stock.stockId == widget.stockId) {
          cover = c;
          break;
        }
      }
      setState(() {
        _cover = cover;
        _state = cover != null ? _LoadState.ready : _LoadState.notFound;
      });
    } catch (e) {
      debugPrint('stock: failed to load product detail: $e');
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _recordMovement() async {
    final stock = _cover!.stock;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockMovementFormScreen(
          stockId: stock.stockId,
          productName: stock.productName,
          currentQuantity: stock.currentQuantity,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    _load();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Movement recorded')));
  }

  Future<void> _viewMovements() async {
    await showStockMovementHistorySheet(
      context,
      stock: _cover!.stock,
      service: _service,
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_cover?.stock.productName ?? 'Product'),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load this product. Please try again.',
          onRetry: _load,
        );
      case _LoadState.notFound:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('This product no longer exists.')),
        );
      case _LoadState.ready:
        return _buildReady(_cover!);
    }
  }

  Widget _buildReady(ProductCover cover) {
    final theme = Theme.of(context);
    final stock = cover.stock;

    final metricsPanel = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.l,
          vertical: AppSpacing.s,
        ),
        child: Column(
          children: [
            MetricRow(
              label: 'Current stock',
              value: formatUnits(stock.currentQuantity),
            ),
            MetricRow(
              label: 'Demand',
              value: cover.requiredPerDay != null
                  ? '${formatNumber(cover.requiredPerDay!)}/day'
                  : 'Not set',
            ),
            MetricRow(
              label: 'Days of cover',
              value: cover.daysOfCover != null
                  ? formatDaysOfCover(cover.daysOfCover!)
                  : '—',
              status: cover.needsAttention ? AppStatus.danger : null,
              statusLabel: cover.needsAttention
                  ? (cover.daysOfCover != null &&
                            isCoverCritical(cover.daysOfCover!)
                        ? 'Critical'
                        : 'Low')
                  : null,
            ),
            MetricRow(
              label: 'Predicted stock-out',
              value: cover.stockOutDate != null
                  ? formatDate(cover.stockOutDate!)
                  : 'Not projected',
            ),
          ],
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stock.productName,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              StatusChip(label: cover.status, status: cover.appStatus),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          metricsPanel,
          const SizedBox(height: AppSpacing.l),
          const SectionHeader(title: 'Actions'),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _recordMovement,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Record stock movement'),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _viewMovements,
              icon: const Icon(Icons.history, size: 18),
              label: const Text('View movement history'),
            ),
          ),
        ],
      ),
    );
  }
}
