import 'package:flutter/material.dart';
import '../../models/purchase_order.dart';
import '../../models/raw_material.dart';
import '../../models/supplier.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../services/supply_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';

/// Values used to pre-populate a new order — e.g. from the material
/// dashboard's "Reorder" button, which already knows the best supplier
/// and a suggested quantity.
class OrderFormPrefill {
  final int materialId;
  final int supplierId;
  final double? quantity;

  const OrderFormPrefill({
    required this.materialId,
    required this.supplierId,
    this.quantity,
  });
}

class OrderFormScreen extends StatefulWidget {
  final int factoryId;
  final PurchaseOrder? order;
  final OrderFormPrefill? prefill;

  const OrderFormScreen({
    super.key,
    required this.factoryId,
    this.order,
    this.prefill,
  });

  @override
  State<OrderFormScreen> createState() => _OrderFormScreenState();
}

enum _LoadState { loading, error, ready }

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplyService = SupplyService();
  final _orderService = OrderService();
  final _quantityController = TextEditingController();

  _LoadState _state = _LoadState.loading;
  List<RawMaterial> _materials = [];
  List<Supplier> _suppliers = [];
  double _plannedProductionPerDay = 0;
  int? _selectedMaterialId;
  int? _selectedSupplierId;
  DateTime _orderDate = DateTime.now();
  DateTime? _expectedDelivery;
  bool _isSaving = false;
  int _loadToken = 0;

  bool get _isEditing => widget.order != null;

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
        _materials = overview.materials;
        _suppliers = overview.suppliers;
        _plannedProductionPerDay = overview.plannedProductionPerDay;

        final order = widget.order;
        final prefill = widget.prefill;
        if (order != null) {
          _selectedMaterialId = order.materialId;
          _selectedSupplierId = order.supplierId;
          _orderDate = order.orderDate;
          _expectedDelivery = order.expectedDelivery;
          _quantityController.text = order.quantity.toString();
          // A supplier can be re-pointed to a different material after this
          // PO was raised against it. If that happened, the dropdown below
          // would be handed a value that isn't among its own items (a
          // framework assertion) — clear it so the user re-picks instead.
          final orderSupplier = _suppliers.where(
            (s) => s.supplierId == order.supplierId,
          );
          if (orderSupplier.isEmpty ||
              orderSupplier.first.materialId != order.materialId) {
            _selectedSupplierId = null;
          }
        } else if (prefill != null) {
          _selectedMaterialId = prefill.materialId;
          _selectedSupplierId = prefill.supplierId;
          if (prefill.quantity != null && prefill.quantity! > 0) {
            _quantityController.text = prefill.quantity!.toStringAsFixed(0);
          }
          _applyLeadTimeToExpectedDelivery();
        } else if (_materials.isNotEmpty) {
          _selectedMaterialId = _materials.first.materialId;
          _autoSelectSupplierForMaterial();
        }
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load order form data: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  List<Supplier> get _suppliersForSelectedMaterial =>
      _suppliers.where((s) => s.materialId == _selectedMaterialId).toList();

  Supplier? get _selectedSupplier {
    final matches = _suppliers.where(
      (s) => s.supplierId == _selectedSupplierId,
    );
    return matches.isEmpty ? null : matches.first;
  }

  RawMaterial? get _selectedMaterial {
    final matches = _materials.where(
      (m) => m.materialId == _selectedMaterialId,
    );
    return matches.isEmpty ? null : matches.first;
  }

  void _autoSelectSupplierForMaterial() {
    final options = _suppliersForSelectedMaterial;
    _selectedSupplierId = options.isNotEmpty ? options.first.supplierId : null;
    _applyLeadTimeToExpectedDelivery();
  }

  void _selectMaterial(int? materialId) {
    setState(() {
      _selectedMaterialId = materialId;
      _autoSelectSupplierForMaterial();
    });
  }

  void _selectSupplier(int? supplierId) {
    setState(() {
      _selectedSupplierId = supplierId;
      _applyLeadTimeToExpectedDelivery();
    });
  }

  void _applyLeadTimeToExpectedDelivery() {
    final supplier = _selectedSupplier;
    _expectedDelivery = supplier != null
        ? _orderDate.add(Duration(days: MrpService.effectiveLeadDays(supplier)))
        : null;
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
      // The delivery can't be expected before the order is even placed.
      firstDate: isOrderDate ? DateTime(2020) : _orderDate,
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isOrderDate) {
        _orderDate = picked;
        // Keep the auto-derived expected delivery in sync with the new
        // order date instead of leaving it stale (and possibly now
        // earlier than the order date itself).
        _applyLeadTimeToExpectedDelivery();
      } else {
        _expectedDelivery = picked;
      }
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String? _coverageHelperText() {
    final material = _selectedMaterial;
    final quantity = double.tryParse(_quantityController.text);
    if (material == null || quantity == null || quantity <= 0) return null;
    final burnRate = material.consumptionPerUnit * _plannedProductionPerDay;
    if (burnRate <= 0) return null;
    final days = quantity / burnRate;
    return 'Covers ~${days.toStringAsFixed(0)} days of planned production';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMaterialId == null || _selectedSupplierId == null) return;
    if (_expectedDelivery != null && _expectedDelivery!.isBefore(_orderDate)) {
      _showMessage('Expected delivery can\'t be before the order date.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final order = PurchaseOrder(
        poId: widget.order?.poId ?? 0,
        supplierId: _selectedSupplierId!,
        materialId: _selectedMaterialId!,
        quantity: double.parse(_quantityController.text),
        orderDate: _orderDate,
        expectedDelivery: _expectedDelivery,
        deliveredAt: widget.order?.deliveredAt,
        status: widget.order?.status ?? PurchaseOrderStatus.pending,
        isSimulated: false,
      );
      if (_isEditing) {
        await _orderService.updateOrder(widget.order!.poId, order);
      } else {
        await _orderService.createOrder(order);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('supply: failed to save order: $e');
      _showMessage('Could not save order. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit purchase order' : 'New purchase order'),
      ),
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
        if (_materials.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_outlined,
            message:
                'Add a raw material first — a purchase order must be placed for one.',
          );
        }
        final supplierOptions = _suppliersForSelectedMaterial;
        final coverageText = _coverageHelperText();
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionHeader(
                title: 'What to order',
                padding: EdgeInsets.only(bottom: 4),
              ),
              DropdownButtonFormField<int>(
                initialValue: _selectedMaterialId,
                decoration: const InputDecoration(labelText: 'Material'),
                items: [
                  for (final material in _materials)
                    DropdownMenuItem(
                      value: material.materialId,
                      child: Text(material.materialName),
                    ),
                ],
                onChanged: _isEditing ? null : _selectMaterial,
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              if (supplierOptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'This material has no supplier yet — add one before '
                    'raising a purchase order for it.',
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _selectedSupplierId,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: [
                    for (final supplier in supplierOptions)
                      DropdownMenuItem(
                        value: supplier.supplierId,
                        child: Text(
                          '${supplier.supplierName} '
                          '(${MrpService.effectiveLeadDays(supplier)}d lead)',
                        ),
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
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  helperText: coverageText,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a positive number';
                  }
                  return null;
                },
              ),
              const SectionHeader(
                title: 'Dates',
                padding: EdgeInsets.only(top: 20, bottom: 4),
              ),
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
                onPressed: (_isSaving || supplierOptions.isEmpty)
                    ? null
                    : _save,
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
