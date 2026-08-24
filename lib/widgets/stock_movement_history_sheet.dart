import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/finished_stock.dart';
import '../models/stock_movement.dart';
import '../screens/stock/stock_movement_form_screen.dart';
import '../services/stock_service.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'loading_indicator.dart';
import 'status.dart';

/// Opens [StockMovementHistorySheet] as a scroll-controlled modal bottom
/// sheet — the standard way every screen shows one product's movement log.
Future<void> showStockMovementHistorySheet(
  BuildContext context, {
  required FinishedStock stock,
  required StockService service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        StockMovementHistorySheet(stock: stock, service: service),
  );
}

/// One product's movement history (production-in / shipment-out /
/// adjustment) plus a button to record a new one. Shared by the Finished
/// Stock list and the Stock product detail page so both use the exact same
/// sheet instead of two copies drifting apart.
class StockMovementHistorySheet extends StatefulWidget {
  final FinishedStock stock;
  final StockService service;

  const StockMovementHistorySheet({
    super.key,
    required this.stock,
    required this.service,
  });

  @override
  State<StockMovementHistorySheet> createState() =>
      _StockMovementHistorySheetState();
}

class _StockMovementHistorySheetState
    extends State<StockMovementHistorySheet> {
  late Future<List<StockMovement>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.getMovements(widget.stock.stockId);
  }

  Future<void> _recordMovement() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockMovementFormScreen(
          stockId: widget.stock.stockId,
          productName: widget.stock.productName,
        ),
      ),
    );
    if (saved == true) {
      setState(
        () => _future = widget.service.getMovements(widget.stock.stockId),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Movement recorded')));
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.stock.productName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _recordMovement,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record movement'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<StockMovement>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingIndicator();
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message: 'Could not load movement history.',
                      onRetry: () => setState(
                        () => _future = widget.service.getMovements(
                          widget.stock.stockId,
                        ),
                      ),
                    );
                  }
                  final movements = snapshot.data!;
                  if (movements.isEmpty) {
                    return const EmptyState(
                      icon: Icons.swap_vert,
                      title: 'No movements recorded yet',
                      subtitle:
                          'Record a production-in or shipment-out to see it here.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(
                        () => _future = widget.service.getMovements(
                          widget.stock.stockId,
                        ),
                      );
                      await _future;
                    },
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: movements.length,
                      itemBuilder: (context, index) {
                        final m = movements[index];
                        final delta = _stockDelta(m);
                        final sign = delta > 0 ? '+' : '';
                        final deltaStatus = delta > 0
                            ? AppStatus.success
                            : AppStatus.danger;
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case StockMovementType.productionIn:
        return 'Production in';
      case StockMovementType.shipmentOut:
        return 'Shipment out';
      default:
        return 'Adjustment';
    }
  }

  int _stockDelta(StockMovement m) {
    switch (m.movementType) {
      case StockMovementType.productionIn:
        return m.quantity.abs();
      case StockMovementType.shipmentOut:
        return -m.quantity.abs();
      default:
        return m.quantity;
    }
  }
}
