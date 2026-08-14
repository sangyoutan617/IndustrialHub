import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/finished_stock.dart';
import '../../models/stock_movement.dart';
import '../../services/stock_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import 'stock_movement_form_screen.dart';

class StockListScreen extends StatefulWidget {
  final int factoryId;

  const StockListScreen({super.key, required this.factoryId});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

enum _LoadState { loading, error, ready }

class _StockListScreenState extends State<StockListScreen> {
  final _service = StockService();
  _LoadState _state = _LoadState.loading;
  List<FinishedStock> _stock = [];
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final stock = await _service.getStockList(widget.factoryId);
      setState(() {
        _stock = stock;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _createStock() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New product'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Product name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Starting quantity',
                ),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative whole number';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isCreating = true);
    try {
      await _service.createStock(
        widget.factoryId,
        nameController.text.trim(),
        int.parse(quantityController.text),
      );
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product added')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create product. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _delete(FinishedStock stock) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove product?',
      message:
          'This removes "${stock.productName}" and its entire movement history permanently. '
          'This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      await _service.deleteStock(stock.stockId);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete product. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openMovements(FinishedStock stock) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _MovementHistorySheet(stock: stock, service: _service),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finished stock')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _isCreating ? null : _createStock,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load finished stock. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_stock.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products yet',
                  subtitle: 'Add your first product to track finished stock.',
                  actionLabel: 'Add product',
                  onAction: _createStock,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _stock.length,
            itemBuilder: (context, index) {
              final stock = _stock[index];
              return Card(
                child: ListTile(
                  title: Text(stock.productName),
                  subtitle: Text(
                    '${formatUnits(stock.currentQuantity)} in stock',
                  ),
                  onTap: () => _openMovements(stock),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(stock),
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}

class _MovementHistorySheet extends StatefulWidget {
  final FinishedStock stock;
  final StockService service;

  const _MovementHistorySheet({required this.stock, required this.service});

  @override
  State<_MovementHistorySheet> createState() => _MovementHistorySheetState();
}

class _MovementHistorySheetState extends State<_MovementHistorySheet> {
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
                        return ListTile(
                          title: Text(
                            '${_typeLabel(m.movementType)}  $sign$delta',
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
