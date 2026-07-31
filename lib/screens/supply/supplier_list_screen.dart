import 'package:flutter/material.dart';
import '../../models/purchase_order.dart';
import '../../models/raw_material.dart';
import '../../models/supplier.dart';
import '../../services/mrp_service.dart';
import '../../services/supplier_service.dart';
import '../../services/supply_exceptions.dart';
import '../../services/supply_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'supplier_comparison_screen.dart';
import 'supplier_form_screen.dart';

const _openStatuses = [
  PurchaseOrderStatus.pending,
  PurchaseOrderStatus.processing,
  PurchaseOrderStatus.shipped,
];

class SupplierListScreen extends StatefulWidget {
  final int factoryId;

  const SupplierListScreen({super.key, required this.factoryId});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

enum _LoadState { loading, error, ready }

class _SupplierListScreenState extends State<SupplierListScreen> {
  final _supplyService = SupplyService();
  final _supplierService = SupplierService();

  _LoadState _state = _LoadState.loading;
  List<Supplier> _suppliers = [];
  List<RawMaterial> _materials = [];
  List<PurchaseOrder> _orders = [];
  Map<int, String> _materialNames = {};
  bool _sortByReliability = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final overview = await _supplyService.load(widget.factoryId);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _suppliers = overview.suppliers;
        _materials = overview.materials;
        _orders = overview.orders;
        _materialNames = overview.materialNames;
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load suppliers: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  List<Supplier> get _sortedSuppliers {
    final list = List<Supplier>.from(_suppliers);
    if (_sortByReliability) {
      list.sort((a, b) => b.reliabilityRating.compareTo(a.reliabilityRating));
    } else {
      list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
    }
    return list;
  }

  int _openOrderCount(int supplierId) => _orders
      .where(
        (o) => o.supplierId == supplierId && _openStatuses.contains(o.status),
      )
      .length;

  Future<void> _openForm({Supplier? supplier}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SupplierFormScreen(factoryId: widget.factoryId, supplier: supplier),
      ),
    );
    if (!mounted) return;
    if (saved == true) _load();
  }

  Future<void> _delete(Supplier supplier) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove supplier?',
      message: 'This removes "${supplier.supplierName}" permanently.',
    );
    if (!confirmed) return;
    try {
      await _supplierService.deleteSupplier(supplier.supplierId);
      if (!mounted) return;
      _load();
    } on SupplyInUseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      debugPrint('supply: failed to delete supplier: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete supplier. Please try again.'),
        ),
      );
    }
  }

  Future<void> _quickRate(Supplier supplier) async {
    var rating = supplier.reliabilityRating;
    final saved = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rate ${supplier.supplierName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${rating.toStringAsFixed(1)} ★'),
              Slider(
                value: rating,
                min: 0,
                max: 5,
                divisions: 10,
                label: rating.toStringAsFixed(1),
                onChanged: (v) => setDialogState(() => rating = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, rating),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    try {
      await _supplierService.updateRating(supplier.supplierId, saved);
      if (!mounted) return;
      _load();
    } catch (e) {
      debugPrint('supply: failed to update rating: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update rating. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openComparison() async {
    final materialsWithSuppliers = _materials
        .where(
          (m) => _suppliers.any((s) => s.materialId == m.materialId),
        )
        .toList();
    if (materialsWithSuppliers.isEmpty) return;
    final materialId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Compare suppliers for'),
        children: [
          for (final material in materialsWithSuppliers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, material.materialId),
              child: Text(material.materialName),
            ),
        ],
      ),
    );
    if (materialId == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierComparisonScreen(
          factoryId: widget.factoryId,
          materialId: materialId,
          materialName: _materialNames[materialId] ?? 'Material',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Compare suppliers',
            onPressed: _state == _LoadState.ready ? _openComparison : null,
          ),
          IconButton(
            icon: Icon(
              _sortByReliability ? Icons.star : Icons.sort_by_alpha,
            ),
            tooltip: _sortByReliability ? 'Sorted by reliability' : 'Sort by name',
            onPressed: () =>
                setState(() => _sortByReliability = !_sortByReliability),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        if (_suppliers.isEmpty) {
          return EmptyState(
            icon: Icons.local_shipping_outlined,
            message: 'No suppliers yet. Add one to enable reorder alerts.',
            actionLabel: 'Add supplier',
            onAction: () => _openForm(),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _sortedSuppliers.length,
            itemBuilder: (context, index) {
              final supplier = _sortedSuppliers[index];
              final materialName =
                  _materialNames[supplier.materialId] ?? 'Unknown material';
              final effectiveLead = MrpService.effectiveLeadDays(supplier);
              final openCount = _openOrderCount(supplier.supplierId);
              return Card(
                child: ListTile(
                  title: Text(supplier.supplierName),
                  subtitle: Text(
                    'Supplies $materialName · quoted ${supplier.leadTimeDays}d '
                    '→ effective ${effectiveLead}d lead · '
                    '$openCount open PO${openCount == 1 ? '' : 's'}'
                    '${supplier.location != null ? ' · ${supplier.location}' : ''}',
                  ),
                  leading: _StarRow(rating: supplier.reliabilityRating),
                  onTap: () => _openForm(supplier: supplier),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rate') _quickRate(supplier);
                      if (value == 'delete') _delete(supplier);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rate', child: Text('Rate')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}

class _StarRow extends StatelessWidget {
  final double rating;

  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              rating >= i
                  ? Icons.star
                  : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
              size: 14,
              color: Colors.amber.shade700,
            ),
        ],
      ),
    );
  }
}
