import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/bom_entry.dart';
import '../../models/product.dart';
import '../../models/raw_material.dart';
import '../../services/bom_service.dart';
import '../../services/material_service.dart';
import '../../services/product_service.dart';
import '../../services/supply_exceptions.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import 'product_form_screen.dart';

/// One product's detail view: basic info, edit/delete, and its bill of
/// materials — how much of each raw material one unit of this product
/// consumes. Lives here (not on the material's own screen) because a
/// product's recipe is one coherent thing a manager edits together;
/// material_detail_screen.dart only shows the reverse, read-only lookup.
class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

enum _LoadState { loading, error, ready }

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _productService = ProductService();
  final _bomService = BomService();
  final _materialService = MaterialService();
  late final Product _product = widget.product;
  bool _busy = false;

  _LoadState _state = _LoadState.loading;
  List<BomEntry> _bom = [];
  List<RawMaterial> _materials = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final results = await Future.wait<dynamic>([
        _bomService.getBom(_product.productId),
        _materialService.getMaterials(_product.factoryId),
      ]);
      if (!mounted) return;
      setState(() {
        _bom = results[0] as List<BomEntry>;
        _materials = results[1] as List<RawMaterial>;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Map<int, RawMaterial> get _materialsById => {
    for (final m in _materials) m.materialId: m,
  };

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
    // The form only returns true/updates server-side; pop back to the list
    // and let it reload — simplest correct behaviour given this screen has
    // no getById to re-fetch its own now-stale widget.product from.
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
      await _productService.deleteProduct(
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

  Future<void> _addOrEditRequirement({BomEntry? existing}) async {
    final available = existing != null
        ? _materials
        : _materials
              .where((m) => !_bom.any((b) => b.materialId == m.materialId))
              .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every material already has a rate set for this product.'),
        ),
      );
      return;
    }
    final result = await showDialog<BomEntry>(
      context: context,
      builder: (_) => _BomEntryDialog(
        materials: available,
        initialMaterialId: existing?.materialId,
        initialQuantity: existing?.quantityPerUnit,
      ),
    );
    if (result == null) return;
    try {
      await _bomService.upsertEntry(result, factoryId: _product.factoryId);
      if (!mounted) return;
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save material requirement. Please try again.'),
        ),
      );
    }
  }

  Future<void> _removeRequirement(BomEntry entry) async {
    final materialName =
        _materialsById[entry.materialId]?.materialName ?? 'this material';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove requirement?',
      message: 'This stops "$materialName" from being deducted when '
          '${_product.productName} is produced.',
    );
    if (!confirmed) return;
    try {
      await _bomService.deleteEntry(
        productId: entry.productId,
        materialId: entry.materialId,
        factoryId: _product.factoryId,
      );
      if (!mounted) return;
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove requirement. Please try again.'),
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
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
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
          const SizedBox(height: AppSpacing.l),
          SectionHeader(
            title: 'Material requirements',
            trailing: TextButton.icon(
              onPressed: () => _addOrEditRequirement(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
          if (_materials.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: EmptyState(
                icon: Icons.inventory_outlined,
                message: 'This factory has no raw materials yet.',
              ),
            )
          else if (_bom.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: EmptyState(
                icon: Icons.list_alt_outlined,
                message:
                    'No material requirements set — this product currently '
                    'consumes nothing when produced.',
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final entry in _bom) _bomTile(entry),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bomTile(BomEntry entry) {
    final material = _materialsById[entry.materialId];
    return ListTile(
      title: Text(
        material?.materialName ?? 'Unknown material',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${formatNumber(entry.quantityPerUnit)} ${material?.unit ?? ''} per unit',
      ),
      onTap: () => _addOrEditRequirement(existing: entry),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _removeRequirement(entry),
      ),
    );
  }
}

/// Add/edit one bill-of-materials line. Controllers live in this dialog's
/// own State (created and disposed here) — the same pattern used
/// throughout the app for every other input dialog, avoiding the
/// rotation-during-dialog crash class an ad-hoc controller lifecycle can hit.
class _BomEntryDialog extends StatefulWidget {
  final List<RawMaterial> materials;
  final int? initialMaterialId;
  final double? initialQuantity;

  const _BomEntryDialog({
    required this.materials,
    this.initialMaterialId,
    this.initialQuantity,
  });

  @override
  State<_BomEntryDialog> createState() => _BomEntryDialogState();
}

class _BomEntryDialogState extends State<_BomEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _quantityController = TextEditingController(
    text: widget.initialQuantity?.toString(),
  );
  late int? _selectedMaterialId = widget.initialMaterialId ??
      (widget.materials.isEmpty ? null : widget.materials.first.materialId);

  bool get _isEditing => widget.initialMaterialId != null;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMaterialId == null) return;
    Navigator.pop(
      context,
      BomEntry(
        productId: 0, // filled in by the caller, which knows the product
        materialId: _selectedMaterialId!,
        quantityPerUnit: double.parse(_quantityController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final material = widget.materials.firstWhere(
      (m) => m.materialId == _selectedMaterialId,
      orElse: () => widget.materials.first,
    );
    return AlertDialog(
      title: Text(_isEditing ? 'Edit requirement' : 'Add requirement'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedMaterialId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Material'),
              items: [
                for (final m in widget.materials)
                  DropdownMenuItem(
                    value: m.materialId,
                    child: Text(m.materialName, overflow: TextOverflow.ellipsis),
                  ),
              ],
              // Locked once editing an existing line — changing the
              // material would silently orphan the old rate instead of
              // editing it; removing and re-adding is the explicit way.
              onChanged: _isEditing
                  ? null
                  : (value) => setState(() => _selectedMaterialId = value),
            ),
            const SizedBox(height: AppSpacing.m),
            TextFormField(
              controller: _quantityController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantity per unit (${material.unit})',
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed < 0) {
                  return 'Enter a non-negative number';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
