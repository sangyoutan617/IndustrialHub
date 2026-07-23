import 'package:flutter/material.dart';
import '../../models/purchase_order.dart';
import '../../models/supplier.dart';
import '../../services/material_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

class OrderFormScreen extends StatefulWidget {
  final int factoryId;

  /// When set (e.g. raised from a low-stock alert), the supplier dropdown is
  /// narrowed to suppliers of this material and quantity is pre-filled.
  final int? initialMaterialId;
  final double? initialQuantity;

  const OrderFormScreen({
    super.key,
    required this.factoryId,
    this.initialMaterialId,
    this.initialQuantity,
  });

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

enum _LoadState { loading, error, ready }

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _materialService = MaterialService();
  final _supplierService = SupplierService();
  final _orderService = OrderService();
  final _quantityController = TextEditingController();

  _LoadState _state = _LoadState.loading;
  List<Supplier> _suppliers = [];
  int? _selectedSupplierId;
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDelivery;
  bool _isSaving = false;
  bool _noSupplierForMaterial = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantity != null) {
      _quantityController.text = widget.initialQuantity!.toStringAsFixed(0);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
      final materialIds = materials.map((m) => m.materialId).toList();
      final allSuppliers = await _supplierService.getSuppliersForMaterials(
        materialIds,
      );

      var suppliers = allSuppliers;
      var noSupplierForMaterial = false;
      if (widget.initialMaterialId != null) {
        final matching = allSuppliers
            .where((s) => s.materialId == widget.initialMaterialId)
            .toList();
        if (matching.isNotEmpty) {
          suppliers = matching;
        } else {
          noSupplierForMaterial = allSuppliers.isNotEmpty;
        }
      }

      setState(() {
        _suppliers = suppliers;
        _noSupplierForMaterial = noSupplierForMaterial;
        if (suppliers.isNotEmpty) _selectSupplier(suppliers.first.supplierId);
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  void _selectSupplier(int? supplierId) {
    setState(() {
      _selectedSupplierId = supplierId;
      final matches = _suppliers.where((s) => s.supplierId == supplierId);
      final supplier = matches.isEmpty ? null : matches.first;
      _expectedDelivery = supplier != null
          ? _orderDate.add(Duration(days: supplier.leadTimeDays))
          : null;
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isOrderDate}) async {
    final initial =
        (isOrderDate ? _orderDate : _expectedDelivery) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isOrderDate) {
        _orderDate = picked;
      } else {
        _expectedDelivery = picked;
      }
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSupplierId == null) return;
    final supplier = _suppliers.firstWhere(
      (s) => s.supplierId == _selectedSupplierId,
    );
    setState(() => _isSaving = true);
    try {
      await _orderService.createOrder(
        PurchaseOrder(
          poId: 0,
          supplierId: supplier.supplierId,
          materialId: supplier.materialId!,
          quantity: double.parse(_quantityController.text),
          orderDate: _orderDate,
          expectedDelivery: _expectedDelivery,
          status: PurchaseOrderStatus.pending,
          isSimulated: false,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create order. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase order')),
      body: SafeArea(child: _buildBody()),
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
          return const EmptyState(
            icon: Icons.local_shipping_outlined,
            message:
                'Add a supplier first — a purchase order must be placed with one.',
          );
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_noSupplierForMaterial)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'No supplier is assigned to that material yet — showing all suppliers instead.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              DropdownButtonFormField<int>(
                initialValue: _selectedSupplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: [
                  for (final supplier in _suppliers)
                    DropdownMenuItem(
                      value: supplier.supplierId,
                      child: Text(supplier.supplierName),
                    ),
                ],
                onChanged: _selectSupplier,
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantity'),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a positive number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Order date'),
                subtitle: Text(_formatDate(_orderDate)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pickDate(isOrderDate: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expected delivery'),
                subtitle: Text(_formatDate(_expectedDelivery)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pickDate(isOrderDate: false),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        );
    }
  }
}
