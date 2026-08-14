import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/demand_forecast.dart';
import '../../models/finished_stock.dart';
import '../../services/demand_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'demand_form_screen.dart';
import 'stock_list_screen.dart';

const int _lowCoverDaysThreshold = 7;
const int _overstockDaysThreshold = 60;

class _ProductCover {
  final FinishedStock stock;
  final int? requiredPerDay;
  final double? daysOfCover;
  final DateTime? stockOutDate;

  _ProductCover({
    required this.stock,
    this.requiredPerDay,
    this.daysOfCover,
    this.stockOutDate,
  });

  String get status {
    if (requiredPerDay == null || requiredPerDay == 0) return 'No demand set';
    if (daysOfCover! < _lowCoverDaysThreshold) {
      return 'Low stock — reorder soon';
    }
    if (daysOfCover! > _overstockDaysThreshold) return 'Overstocked';
    return 'Healthy';
  }

  Color statusColor(ColorScheme scheme) {
    if (requiredPerDay == null || requiredPerDay == 0) return scheme.outline;
    if (daysOfCover! < _lowCoverDaysThreshold) return scheme.error;
    if (daysOfCover! > _overstockDaysThreshold) return scheme.tertiary;
    return scheme.primary;
  }
}

class StockDashboardScreen extends StatefulWidget {
  final int factoryId;

  const StockDashboardScreen({super.key, required this.factoryId});

  @override
  State<StockDashboardScreen> createState() => _StockDashboardScreenState();
}

enum _LoadState { loading, error, ready }

class _StockDashboardScreenState extends State<StockDashboardScreen> {
  final _stockService = StockService();
  final _demandService = DemandService();

  _LoadState _state = _LoadState.loading;
  List<_ProductCover> _covers = [];
  List<DemandForecast> _forecasts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StockDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryId != widget.factoryId) _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final stockList = await _stockService.getStockList(widget.factoryId);
      final forecasts = await _demandService.getForecasts(widget.factoryId);

      final requiredByName = <String, int>{};
      for (final forecast in forecasts) {
        final key = forecast.productName.trim().toLowerCase();
        requiredByName[key] =
            (requiredByName[key] ?? 0) + forecast.requiredPerDay;
      }

      final covers = stockList.map((stock) {
        final required = requiredByName[stock.productName.trim().toLowerCase()];
        final daysOfCover = (required != null && required > 0)
            ? stock.currentQuantity / required
            : null;
        final stockOutDate = daysOfCover != null
            ? DateTime.now().add(Duration(days: daysOfCover.floor()))
            : null;
        return _ProductCover(
          stock: stock,
          requiredPerDay: required,
          daysOfCover: daysOfCover,
          stockOutDate: stockOutDate,
        );
      }).toList();

      setState(() {
        _covers = covers;
        _forecasts = forecasts;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openDemandForm({DemandForecast? forecast}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            DemandFormScreen(factoryId: widget.factoryId, forecast: forecast),
      ),
    );
    if (saved == true) {
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forecast == null
                ? 'Demand forecast added'
                : 'Demand forecast updated',
          ),
        ),
      );
    }
  }

  Future<void> _deleteDemand(DemandForecast forecast) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove demand forecast?',
      message:
          'This removes the forecast for "${forecast.productName}" permanently.',
    );
    if (!confirmed) return;
    try {
      await _demandService.deleteForecast(forecast.demandId);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Demand forecast removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete forecast. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openStockList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockListScreen(factoryId: widget.factoryId),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
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
    final scheme = Theme.of(context).colorScheme;
    final lowStockCount = _covers
        .where(
          (c) =>
              c.requiredPerDay != null &&
              c.requiredPerDay! > 0 &&
              c.daysOfCover! < _lowCoverDaysThreshold,
        )
        .length;
    final overstockCount = _covers
        .where(
          (c) =>
              c.requiredPerDay != null &&
              c.requiredPerDay! > 0 &&
              c.daysOfCover! > _overstockDaysThreshold,
        )
        .length;

    final withCover = _covers.where((c) => c.daysOfCover != null).toList();
    final mostUrgent = withCover.isEmpty
        ? null
        : (withCover.toList()
                ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!)))
              .first;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Days of cover',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mostUrgent != null
                        ? '${mostUrgent.daysOfCover!.toStringAsFixed(1)} days'
                        : '—',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  if (mostUrgent?.stockOutDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Stock-out predicted: ${_formatDate(mostUrgent!.stockOutDate!)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  'Products',
                  _covers.length.toString(),
                  scheme.primary,
                ),
              ),
              Expanded(
                child: _summaryStat(
                  'Low stock',
                  lowStockCount.toString(),
                  scheme.error,
                ),
              ),
              Expanded(
                child: _summaryStat(
                  'Overstocked',
                  overstockCount.toString(),
                  AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_covers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                message: 'No products yet. Add one from Finished Stock above.',
              ),
            )
          else ...[
            Text(
              'Days of cover',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final cover in _covers) _buildCoverCard(cover, scheme),
            const SizedBox(height: 8),
            _dashedButton(
              icon: Icons.add,
              label: 'Log stock movement',
              onTap: _openStockList,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Demand forecast',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton.icon(
                onPressed: () => _openDemandForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add demand'),
              ),
            ],
          ),
          if (_forecasts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: EmptyState(
                icon: Icons.trending_up,
                message: 'No demand forecasts set yet.',
              ),
            )
          else
            for (final forecast in _forecasts)
              Card(
                child: ListTile(
                  title: Text(forecast.productName),
                  subtitle: Text(
                    '${forecast.requiredPerDay} units/day required',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openDemandForm(forecast: forecast),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteDemand(forecast),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildCoverCard(_ProductCover cover, ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cover.stock.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cover.statusColor(scheme).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cover.status,
                    style: TextStyle(
                      color: cover.statusColor(scheme),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${cover.stock.currentQuantity} units in stock'),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: cover.requiredPerDay != null && cover.requiredPerDay! > 0
                    ? (cover.stock.currentQuantity /
                              (cover.requiredPerDay! * _overstockDaysThreshold))
                          .clamp(0.0, 1.0)
                    : 0,
                minHeight: 6,
                backgroundColor: AppColors.primaryLight,
                valueColor: AlwaysStoppedAnimation(cover.statusColor(scheme)),
              ),
            ),
            const SizedBox(height: 6),
            if (cover.daysOfCover != null) ...[
              Text(
                'Demand ${cover.requiredPerDay}/day · '
                '${cover.daysOfCover!.toStringAsFixed(1)} days of cover',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              if (cover.stockOutDate != null)
                Text(
                  'Predicted stock-out: ${_formatDate(cover.stockOutDate!)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ] else
              Text(
                'No demand set',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dashedButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.primaryDark),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
