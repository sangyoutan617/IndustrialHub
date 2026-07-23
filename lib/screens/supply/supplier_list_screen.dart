import 'package:flutter/material.dart';
import '../../models/supplier.dart';
import '../../services/material_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'supplier_form_screen.dart';

String _leadTimeLine(Supplier supplier, SupplierLeadTimeStats? stats) {
  if (stats == null) return '${supplier.leadTimeDays}d promised lead time';
  final onTime = stats.onTimePercent != null
      ? ' · ${stats.onTimePercent!.toStringAsFixed(0)}% on-time'
      : '';
  return 'Promised ${supplier.leadTimeDays}d · '
      'Actual avg ${stats.actualAverageDays.toStringAsFixed(1)}d$onTime';
}

class SupplierListScreen extends StatefulWidget {
  final int factoryId;

  const SupplierListScreen({super.key, required this.factoryId});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

enum _LoadState { loading, error, ready }

class _SupplierListScreenState extends State<SupplierListScreen> {
  final _materialService = MaterialService();
  final _supplierService = SupplierService();

  _LoadState _state = _LoadState.loading;
  List<Supplier> _suppliers = [];
  Map<int, String> _materialNames = {};
  Map<int, SupplierLeadTimeStats> _leadTimeStats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
      final materialIds = materials.map((m) => m.materialId).toList();
      final suppliers = await _supplierService.getSuppliersForMaterials(
        materialIds,
      );
      final leadTimeStats = await _supplierService.getActualLeadTimeStats(
        suppliers.map((s) => s.supplierId).toList(),
      );
      setState(() {
        _suppliers = suppliers;
        _materialNames = {
          for (final m in materials) m.materialId: m.materialName,
        };
        _leadTimeStats = leadTimeStats;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openForm({Supplier? supplier}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SupplierFormScreen(factoryId: widget.factoryId, supplier: supplier),
      ),
    );
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
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete supplier. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
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
            itemCount: _suppliers.length,
            itemBuilder: (context, index) {
              final supplier = _suppliers[index];
              final materialName =
                  _materialNames[supplier.materialId] ?? 'Unknown material';
              final stats = _leadTimeStats[supplier.supplierId];
              return Card(
                child: ListTile(
                  title: Text(supplier.supplierName),
                  subtitle: Text(
                    'Supplies $materialName · ${_leadTimeLine(supplier, stats)} · '
                    '${supplier.reliabilityRating.toStringAsFixed(1)}★'
                    '${supplier.location != null ? ' · ${supplier.location}' : ''}',
                  ),
                  onTap: () => _openForm(supplier: supplier),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(supplier),
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}
