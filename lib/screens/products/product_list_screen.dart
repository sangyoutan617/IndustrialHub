import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/supply_exceptions.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_grid_list.dart';
import '../../widgets/status.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatefulWidget {
  final int factoryId;

  const ProductListScreen({super.key, required this.factoryId});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

enum _LoadState { loading, error, ready }

class _ProductListScreenState extends State<ProductListScreen> {
  final _service = ProductService();
  _LoadState _state = _LoadState.loading;
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _service.getProducts(widget.factoryId);
      if (!mounted) return;
      setState(() {
        _products = products;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(factoryId: widget.factoryId),
      ),
    );
    if (!mounted || saved != true) return;
    _load();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Product added')));
  }

  Future<void> _openDetail(Product product) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
    if (!mounted || changed != true) return;
    _load();
  }

  Future<bool> _delete(Product product) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove product?',
      message:
          'This removes "${product.productName}" permanently. This cannot '
          'be undone.',
    );
    if (!confirmed) return false;
    try {
      await _service.deleteProduct(
        product.productId,
        factoryId: widget.factoryId,
      );
      if (!mounted) return true;
      _load();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product removed')));
      return true;
    } on SupplyInUseException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
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
          message: 'Could not load products. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_products.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.category_outlined,
                  title: 'No products yet',
                  subtitle:
                      'Add a product to assign machines, manpower, and raw '
                      'materials to it.',
                  actionLabel: 'Add product',
                  onAction: _openForm,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ResponsiveGridList(
            padding: const EdgeInsets.all(8),
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final product = _products[index];
              return Dismissible(
                key: ValueKey(product.productId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _delete(product),
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
                    leading: CircleAvatar(
                      backgroundColor: product.isGeneral
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        product.isGeneral
                            ? Icons.inventory_2_outlined
                            : Icons.category_outlined,
                      ),
                    ),
                    title: Text(product.productName),
                    subtitle: product.isGeneral
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const StatusChip(
                                  label: 'General',
                                  status: AppStatus.neutral,
                                  dense: true,
                                ),
                                const SizedBox(width: AppSpacing.s),
                                Expanded(
                                  child: Text(
                                    'Auto-created catch-all',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(product.unit),
                    onTap: () => _openDetail(product),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(product),
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
