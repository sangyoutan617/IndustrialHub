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
  List<Product> _allProducts = [];
  bool _showArchived = false;

  List<Product> get _visibleProducts =>
      _allProducts.where((p) => p.isArchived == _showArchived).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _service.getProducts(
        widget.factoryId,
        includeArchived: true,
      );
      if (!mounted) return;
      setState(() {
        _allProducts = products;
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

  Future<bool> _archive(Product product) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive product?',
      message:
          '"${product.productName}" will be hidden from daily lists, but '
          'its history is kept. You can unarchive it later.',
      confirmLabel: 'Archive',
      isDestructive: false,
    );
    if (!confirmed) return false;
    setState(
      () => _allProducts = _allProducts
          .map((p) => p.productId == product.productId ? _withArchived(p, true) : p)
          .toList(),
    );
    _service
        .archiveProduct(product.productId, factoryId: widget.factoryId)
        .then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Product archived')));
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(
            () => _allProducts = _allProducts
                .map(
                  (p) => p.productId == product.productId
                      ? _withArchived(p, false)
                      : p,
                )
                .toList(),
          );
          final message = e is SupplyInUseException
              ? e.message
              : 'Could not archive product. Please try again.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        });
    return true;
  }

  void _unarchive(Product product) {
    setState(
      () => _allProducts = _allProducts
          .map((p) => p.productId == product.productId ? _withArchived(p, false) : p)
          .toList(),
    );
    _service
        .reactivateProduct(product.productId, factoryId: widget.factoryId)
        .then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Product restored')));
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(
            () => _allProducts = _allProducts
                .map(
                  (p) => p.productId == product.productId
                      ? _withArchived(p, true)
                      : p,
                )
                .toList(),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not restore product. Please try again.'),
            ),
          );
        });
  }

  Product _withArchived(Product p, bool archived) => Product(
    productId: p.productId,
    factoryId: p.factoryId,
    productName: p.productName,
    unit: p.unit,
    isGeneral: p.isGeneral,
    status: archived ? 'archived' : 'active',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived products' : 'Products'),
        actions: [
          IconButton(
            icon: Icon(
              _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            tooltip: _showArchived ? 'Show active products' : 'Show archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton(
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
        final products = _visibleProducts;
        if (products.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const SizedBox(height: 80),
                _showArchived
                    ? const EmptyState(
                        icon: Icons.archive_outlined,
                        title: 'No archived products',
                        subtitle: 'Products you archive will show up here.',
                      )
                    : EmptyState(
                        icon: Icons.category_outlined,
                        title: 'No products yet',
                        subtitle:
                            'Add a product to assign machines, manpower, and '
                            'raw materials to it.',
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
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final tile = Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: product.isGeneral
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(product.unit),
                  onTap: _showArchived
                      ? null
                      : () => _openDetail(product),
                  trailing: _showArchived
                      ? IconButton(
                          icon: const Icon(Icons.unarchive_outlined),
                          tooltip: 'Restore',
                          onPressed: () => _unarchive(product),
                        )
                      : IconButton(
                          icon: const Icon(Icons.archive_outlined),
                          tooltip: 'Archive',
                          onPressed: () => _archive(product),
                        ),
                ),
              );
              if (_showArchived) return tile;
              return Dismissible(
                key: ValueKey(product.productId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _archive(product),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.archive_outlined,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                child: tile,
              );
            },
          ),
        );
    }
  }
}
