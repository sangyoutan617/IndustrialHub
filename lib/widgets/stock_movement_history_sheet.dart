import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/finished_stock.dart';
import '../models/stock_movement.dart';
import '../services/stock_service.dart';
import 'empty_state.dart';
import 'status.dart';

Future<void> showStockMovementHistorySheet(
  BuildContext context, {
  required FinishedStock stock,
  required StockService service,
}) async {
  List<StockMovement> movements;
  try {
    movements = await service.getMovements(stock.stockId);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not load movement history.')),
    );
    return;
  }
  if (!context.mounted) return;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StockMovementHistorySheet(
      stock: stock,
      service: service,
      initialMovements: movements,
    ),
  );
}

class StockMovementHistorySheet extends StatefulWidget {
  final FinishedStock stock;
  final StockService service;
  final List<StockMovement> initialMovements;

  const StockMovementHistorySheet({
    super.key,
    required this.stock,
    required this.service,
    required this.initialMovements,
  });

  @override
  State<StockMovementHistorySheet> createState() =>
      _StockMovementHistorySheetState();
}

class _StockMovementHistorySheetState
    extends State<StockMovementHistorySheet> {
  late List<StockMovement> _movements;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _movements = widget.initialMovements;
  }

  Future<void> _refresh() async {
    try {
      final fresh = await widget.service.getMovements(widget.stock.stockId);
      if (mounted) setState(() => _movements = fresh);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not refresh movement history.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                widget.stock.productName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildFilterChips(),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(child: _buildList(scrollController)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ScrollController scrollController) {
    final movements = _movements
        .where((m) => _filter == null || m.movementType == _filter)
        .toList();
    if (movements.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: Icons.swap_vert,
              title: _filter == null
                  ? 'No movements recorded yet'
                  : 'No ${_typeLabel(_filter!).toLowerCase()} movements',
              subtitle: _filter == null
                  ? 'Record a production-in or shipment-out to see it here.'
                  : 'Try a different filter.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: scrollController,
        itemCount: movements.length,
        itemBuilder: (context, index) {
          final m = movements[index];
          final delta = _stockDelta(m);
          final sign = delta > 0 ? '+' : '';
          final deltaStatus = delta > 0 ? AppStatus.success : AppStatus.danger;
          return ListTile(
            title: Row(
              children: [
                StatusChip(
                  label: _typeLabel(m.movementType),
                  status: deltaStatus,
                  dense: true,
                ),
                const SizedBox(width: AppSpacing.s),
                Text(
                  '$sign$delta',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: deltaStatus.color,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${formatDate(m.movementDate)}'
              '${m.note != null ? ' — ${m.note}' : ''}',
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: _filter,
        borderRadius: BorderRadius.circular(AppRadius.md),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          for (final type in StockMovementType.all)
            DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
        ],
        onChanged: (value) => setState(() => _filter = value),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case StockMovementType.productionIn:
        return 'Production in';
      case StockMovementType.shipmentOut:
        return 'Shipment out';
      case StockMovementType.damaged:
        return 'Damaged';
      case StockMovementType.returned:
        return 'Returned';
      default:
        return 'Adjustment';
    }
  }

  int _stockDelta(StockMovement m) {
    switch (m.movementType) {
      case StockMovementType.productionIn:
        return m.quantity.abs();
      case StockMovementType.returned:
        return m.quantity.abs();
      case StockMovementType.shipmentOut:
        return -m.quantity.abs();
      case StockMovementType.damaged:
        return -m.quantity.abs();
      default:
        return m.quantity;
    }
  }
}
