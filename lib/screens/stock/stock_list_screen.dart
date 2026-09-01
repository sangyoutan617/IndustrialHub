import 'package:flutter/material.dart';
import '../../widgets/responsive_grid_list.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/finished_stock.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/stock_movement_history_sheet.dart';

class StockListScreen extends StatefulWidget {
  final int factoryId;

  const StockListScreen({super.key, required this.factoryId});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

enum _LoadState { loading, error, ready }

class _StockListScreenState extends State<StockListScreen> {
  final _service = StockService();
  final _productService = ProductService();
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
      if (!mounted) return;
      setState(() {
        _stock = stock;
        _state = _LoadState.ready;
      });
    } catch (e, st) {
      debugPrint('StockListScreen _load error: $e\n$st');
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _createStock() async {
    setState(() => _isCreating = true);
    List<Product> allProducts;
    try {
      allProducts = await _productService.getProducts(widget.factoryId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load products. Please try again.'),
        ),
      );
      return;
    }
    final trackedProductIds = _stock.map((s) => s.productId).toSet();
    final available = allProducts
        .where((p) => !trackedProductIds.contains(p.productId))
        .toList();
    if (!mounted) return;
    setState(() => _isCreating = false);
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allProducts.isEmpty
                ? 'No products yet — add a product on the Capacity tab first.'
                : 'Every product already has finished-stock tracking.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_NewProductResult>(
      context: context,
      builder: (_) => _NewProductDialog(products: available),
    );
    if (result == null) return;

    setState(() => _isCreating = true);
    try {
      await _service.createStock(
        widget.factoryId,
        result.product,
        result.quantity,
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

  Future<bool> _delete(FinishedStock stock) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove product?',
      message:
          'This removes "${stock.productName}" and its entire movement history permanently. '
          'This cannot be undone.',
    );
    if (!confirmed) return false;
    try {
      await _service.deleteStock(stock.stockId);
      _load();
      if (!mounted) return true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product removed')));
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete product. Please try again.'),
        ),
      );
      return false;
    }
  }

  Future<void> _openMovements(FinishedStock stock) async {
    await showStockMovementHistorySheet(
      context,
      stock: stock,
      service: _service,
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
          child: ResponsiveGridList(
            padding: const EdgeInsets.all(8),
            itemCount: _stock.length,
            itemBuilder: (context, index) {
              final stock = _stock[index];
              return Dismissible(
                key: ValueKey(stock.stockId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _delete(stock),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                child: Card(
                  child: ListTile(
                    title: Text(
                      stock.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatUnits(stock.currentQuantity)} in stock',
                    ),
                    onTap: () => _openMovements(stock),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(stock),
                    ),
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}

class _NewProductResult {
  final Product product;
  final int quantity;

  const _NewProductResult({required this.product, required this.quantity});
}

class _NewProductDialog extends StatefulWidget {
  final List<Product> products;

  const _NewProductDialog({required this.products});

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _quantityController = TextEditingController(text: '0');
  final _formKey = GlobalKey<FormState>();
  late int? _selectedProductId = widget.products.first.productId;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) return;
    final product = widget.products.firstWhere(
      (p) => p.productId == _selectedProductId,
    );
    Navigator.pop(
      context,
      _NewProductResult(
        product: product,
        quantity: int.parse(_quantityController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New product'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedProductId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: [
                for (final product in widget.products)
                  DropdownMenuItem(
                    value: product.productId,
                    child: Text(
                      product.isGeneral
                          ? '${product.productName} (auto-created)'
                          : product.productName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedProductId = value),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Starting quantity'),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
