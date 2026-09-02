import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters.dart';
import '../../models/purchase_order.dart';
import '../../models/raw_material.dart';
import '../../models/supplier.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../services/supply_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';

const _maxQuantityOrPrice = 99999999.99;

final _twoDecimalInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.isEmpty) return newValue;
  final pattern = RegExp(r'^\d{0,8}(\.\d{0,2})?$');
  return pattern.hasMatch(newValue.text) ? newValue : oldValue;
});

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
  final _priceController = TextEditingController();

  _LoadState _state = _LoadState.loading;
  List<RawMaterial> _materials = [];
  List<Supplier> _suppliers = [];
  List<MaterialPlan> _plans = [];

  int? _nextPoIdPreview;
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

  Future<int?> _fetchNextPoIdPreview() async {
    try {
      return await _orderService.getNextPoIdPreview();
    } catch (e) {
      debugPrint('supply: failed to preview next PO number: $e');
      return null;
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final overviewFuture = _supplyService.load(widget.factoryId);
      final previewFuture = _isEditing
          ? Future<int?>.value(null)
          : _fetchNextPoIdPreview();
      final overview = await overviewFuture;
      final preview = await previewFuture;
      if (!mounted || token != _loadToken) return;
      setState(() {
        _materials = overview.materials;
        _suppliers = overview.suppliers;
        _plans = overview.plans;
        _nextPoIdPreview = preview;

        final order = widget.order;
        final prefill = widget.prefill;
        if (order != null) {
          _selectedMaterialId = order.materialId;
          _selectedSupplierId = order.supplierId;
          _orderDate = order.orderDate;
          _expectedDelivery = order.expectedDelivery;
          _quantityController.text = order.quantity.toString();
          _priceController.text = order.unitPrice?.toString() ?? '';
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
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickOrderDate() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate.isBefore(startOfToday) ? startOfToday : _orderDate,
      firstDate: startOfToday,
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _orderDate = picked;
      _applyLeadTimeToExpectedDelivery();
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String? _orderTotalHelperText() {
    final quantity = double.tryParse(_quantityController.text);
    final price = double.tryParse(_priceController.text);
    if (quantity == null || price == null || quantity <= 0 || price <= 0) {
      return null;
    }
    return 'Order total: ${formatCurrency(quantity * price)}';
  }

  String? _coverageHelperText() {
    final material = _selectedMaterial;
    final quantity = double.tryParse(_quantityController.text);
    if (material == null || quantity == null || quantity <= 0) return null;
    final matches = _plans.where((p) => p.material.materialId == material.materialId);
    if (matches.isEmpty) return null;
    final burnRate = matches.first.burnRatePerDay;
    if (burnRate <= 0) return null;
    final days = quantity / burnRate;
    return 'Covers ~${days.toStringAsFixed(0)} days of planned production';
  }

  Widget _dropdownMenuField({
    required Key key,
    required String label,
    required int? value,
    required List<DropdownMenuEntry<int>> entries,
    required ValueChanged<int?> onChanged,
    bool enabled = true,
  }) {
    return FormField<int>(
      key: key,
      initialValue: value,
      validator: (v) => v == null ? 'Required' : null,
      builder: (field) => DropdownMenu<int>(
        enabled: enabled,
        initialSelection: value,
        expandedInsets: EdgeInsets.zero,
        label: Text(label),
        errorText: field.errorText,
        dropdownMenuEntries: entries,
        onSelected: (v) {
          field.didChange(v);
          onChanged(v);
        },
      ),
    );
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
        status: widget.order?.status ?? PurchaseOrderStatus.processing,
        isSimulated: false,
        unitPrice: double.parse(_priceController.text),
      );
      PurchaseOrder savedOrder;
      if (_isEditing) {
        savedOrder = await _orderService.updateOrder(
          widget.order!.poId,
          order,
          factoryId: widget.factoryId,
        );
      } else {
        savedOrder = await _orderService.createOrder(
          order,
          factoryId: widget.factoryId,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, savedOrder);
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
        title: Text(
          _isEditing
              ? 'Edit ${formatPoNumber(widget.order!.poId)}'
              : 'New purchase order',
        ),
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
        final theme = Theme.of(context);
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ResponsiveFormFields(
                children: [
                  FormBreak(
                    TextFormField(
                      key: ValueKey(
                        _isEditing
                            ? 'po-number-${widget.order!.poId}'
                            : 'po-number-preview-$_nextPoIdPreview',
                      ),
                      initialValue: _isEditing
                          ? formatPoNumber(widget.order!.poId)
                          : _nextPoIdPreview != null
                          ? formatPoNumber(_nextPoIdPreview!)
                          : 'Auto-generated after creation',
                      enabled: false,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'PO Number',
                        helperText: 'System-generated — cannot be edited',
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const FormBreak(SectionHeader(
                    title: 'What to order',
                    padding: EdgeInsets.only(top: 20, bottom: 4),
                  )),
                  _dropdownMenuField(
                    key: ValueKey('material-$_selectedMaterialId'),
                    label: 'Material',
                    value: _selectedMaterialId,
                    enabled: !_isEditing,
                    entries: [
                      for (final material in _materials)
                        DropdownMenuEntry(
                          value: material.materialId,
                          label: material.materialName,
                        ),
                    ],
                    onChanged: _selectMaterial,
                  ),
                  const SizedBox(height: 16),
                  if (supplierOptions.isEmpty)
                    const FormBreak(Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'This material has no supplier yet — add one before '
                        'raising a purchase order for it.',
                      ),
                    ))
                  else
                    _dropdownMenuField(
                      key: ValueKey('supplier-$_selectedSupplierId'),
                      label: 'Supplier',
                      value: _selectedSupplierId,
                      entries: [
                        for (final supplier in supplierOptions)
                          DropdownMenuEntry(
                            value: supplier.supplierId,
                            label:
                                '${supplier.supplierName} '
                                '(${MrpService.effectiveLeadDays(supplier)}d lead)',
                          ),
                      ],
                      onChanged: _selectSupplier,
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_twoDecimalInputFormatter],
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
                      if (parsed > _maxQuantityOrPrice) {
                        return 'Must not exceed ${formatRate(_maxQuantityOrPrice)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_twoDecimalInputFormatter],
                    decoration: InputDecoration(
                      labelText: 'Unit price (RM)',
                      helperText: _orderTotalHelperText(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final parsed = double.tryParse(v ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Enter a valid price';
                      }
                      if (parsed > _maxQuantityOrPrice) {
                        return 'Must not exceed ${formatRate(_maxQuantityOrPrice)}';
                      }
                      return null;
                    },
                  ),
                  const FormBreak(SectionHeader(
                    title: 'Dates',
                    padding: EdgeInsets.only(top: 20, bottom: 4),
                  )),
                  FormBreak(ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Order date'),
                    subtitle: Text(_formatDate(_orderDate)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: _pickOrderDate,
                  )),
                  FormBreak(ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Expected delivery'),
                    subtitle: Text(_formatDate(_expectedDelivery)),
                    trailing: const Icon(Icons.lock_outline, size: 18),
                  )),
                  const FormBreak(Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      "Follows the selected supplier's effective lead time — "
                      'not editable directly.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )),
                  const SizedBox(height: 24),
                  FormBreak(
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
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}
