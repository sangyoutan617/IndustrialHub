import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/supply_exceptions.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status.dart';
import 'product_form_screen.dart';

/// One product's detail view — basic info plus edit/delete for now. A
/// "Material requirements" (bill-of-materials) section is added here once
/// product_materials management ships.
class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _service = ProductService();
  late final Product _product = widget.product;
  bool _busy = false;

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          factoryId: _product.factoryId,
          product: _product,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    // The form only returns true/updates server-side; re-fetch isn't wired
    // to a getById endpoint yet, so pop back to the list and let it reload —
    // simplest correct behaviour until this screen needs to stay open after
    // an edit (e.g. once the BOM section below makes staying worthwhile).
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove product?',
      message:
          'This removes "${_product.productName}" permanently. This cannot '
          'be undone.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _service.deleteProduct(
        _product.productId,
        factoryId: _product.factoryId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SupplyInUseException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete product. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_product.productName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit product',
            onPressed: _busy ? null : _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove product',
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _product.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_product.isGeneral)
                const StatusChip(label: 'General', status: AppStatus.neutral),
            ],
          ),
          if (_product.isGeneral) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Auto-created catch-all — every machine, shift, and material '
              'rate that predated real products was assigned here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.l),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.l,
                vertical: AppSpacing.s,
              ),
              child: Column(
                children: [
                  MetricRow(label: 'Unit', value: _product.unit),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
