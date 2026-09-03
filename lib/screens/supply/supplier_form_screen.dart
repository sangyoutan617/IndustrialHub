import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters.dart';
import '../../core/supplier_validators.dart';
import '../../core/theme.dart';
import '../../models/raw_material.dart';
import '../../models/supplier.dart';
import '../../services/material_service.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';
import '../../widgets/status.dart';

const _maxUnitPrice = 99999999.99;

final _priceInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.isEmpty) return newValue;
  final pattern = RegExp(r'^\d{0,8}(\.\d{0,2})?$');
  return pattern.hasMatch(newValue.text) ? newValue : oldValue;
});

class SupplierFormScreen extends StatefulWidget {
  final int factoryId;
  final Supplier? supplier;

  const SupplierFormScreen({super.key, required this.factoryId, this.supplier});

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

enum _LoadState { loading, error, ready }

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _materialService = MaterialService();
  final _supplierService = SupplierService();
  final _orderService = OrderService();

  late final _nameController = TextEditingController(
    text: widget.supplier?.supplierName,
  );
  late final _locationController = TextEditingController(
    text: widget.supplier?.location,
  );
  late final _contactPersonController = TextEditingController(
    text: widget.supplier?.contactPerson,
  );
  late final _phoneController = TextEditingController(
    text: widget.supplier?.phone,
  );
  late final _emailController = TextEditingController(
    text: widget.supplier?.email,
  );
  late final _leadTimeController = TextEditingController(
    text: (widget.supplier?.leadTimeDays ?? 7).toString(),
  );
  late final _priceController = TextEditingController(
    text: widget.supplier?.unitPrice?.toString() ?? '',
  );
  late double _rating = widget.supplier?.reliabilityRating ?? 3;

  _LoadState _state = _LoadState.loading;
  List<RawMaterial> _materials = [];
  List<Supplier> _existingSuppliers = [];
  int? _selectedMaterialId;
  double? _suggestedRating;
  bool _isSaving = false;
  int _loadToken = 0;

  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    _selectedMaterialId = widget.supplier?.materialId;
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
      final existingSuppliers = await _supplierService.getSuppliersForMaterials(
        materials.map((m) => m.materialId).toList(),
      );
      double? suggested;
      final supplier = widget.supplier;
      if (supplier != null && supplier.materialId != null) {
        final orders = await _orderService.getOrdersForMaterials([
          supplier.materialId!,
        ]);
        final history = orders
            .where((o) => o.supplierId == supplier.supplierId)
            .toList();
        suggested = MrpService.suggestedRating(MrpService.onTimeRate(history));
      }
      if (!mounted || token != _loadToken) return;
      setState(() {
        _materials = materials;
        _existingSuppliers = existingSuppliers;
        _selectedMaterialId ??= materials.isNotEmpty
            ? materials.first.materialId
            : null;
        _suggestedRating = suggested;
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load supplier form data: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _contactPersonController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _leadTimeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMaterialId == null) return;
    setState(() => _isSaving = true);
    try {
      final supplier = Supplier(
        supplierId: widget.supplier?.supplierId ?? 0,
        supplierName: _nameController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        materialId: _selectedMaterialId,
        leadTimeDays: int.parse(_leadTimeController.text),
        reliabilityRating: _rating,
        isSimulated: false,
        contactPerson: _contactPersonController.text.trim().isEmpty
            ? null
            : _contactPersonController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        unitPrice: _priceController.text.trim().isEmpty
            ? null
            : double.parse(_priceController.text.trim()),
      );
      if (_isEditing) {
        await _supplierService.updateSupplier(
          widget.supplier!.supplierId,
          supplier,
          factoryId: widget.factoryId,
        );
      } else {
        await _supplierService.createSupplier(
          supplier,
          factoryId: widget.factoryId,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('supply: failed to save supplier: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save supplier. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit supplier' : 'Add supplier'),
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
                'Add a raw material first — a supplier must be linked to one.',
          );
        }
        final leadTime = int.tryParse(_leadTimeController.text) ?? 0;
        final effectiveLead = MrpService.effectiveLeadDays(
          Supplier(
            supplierId: 0,
            supplierName: '',
            leadTimeDays: leadTime,
            reliabilityRating: _rating,
            isSimulated: false,
          ),
        );
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ResponsiveFormFields(
                children: [
                  TextFormField(
                    controller: _nameController,
                    maxLength: SupplierValidators.maxNameLength,
                    decoration: const InputDecoration(labelText: 'Supplier name'),
                    validator: (v) => SupplierValidators.validateName(
                      v,
                      existingSuppliers: _existingSuppliers,
                      excludingSupplierId: widget.supplier?.supplierId,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contactPersonController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Contact person (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                    ),
                    validator: SupplierValidators.validatePhone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                    ),
                    validator: SupplierValidators.validateEmail,
                  ),
                  const SizedBox(height: 16),
                  AppDropdownField<int>(
                    idPrefix: 'material',
                    label: 'Supplies which material',
                    value: _selectedMaterialId,
                    entries: [
                      for (final material in _materials)
                        DropdownMenuEntry(
                          value: material.materialId,
                          label: material.materialName,
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedMaterialId = value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _leadTimeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Lead time (days)',
                      helperText: 'How long an order takes to arrive '
                          '(max ${SupplierValidators.maxLeadTimeDays} working days)',
                      helperMaxLines: 2,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: SupplierValidators.validateLeadTime,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_priceInputFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Unit price (RM)',
                      helperText:
                          'Quoted price for this material — prefills new '
                          'purchase orders, still editable there',
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      final trimmed = v?.trim() ?? '';
                      if (trimmed.isEmpty) return 'Required';
                      final parsed = double.tryParse(trimmed);
                      if (parsed == null || parsed < 0) {
                        return 'Enter a valid price';
                      }
                      if (parsed > _maxUnitPrice) {
                        return 'Must not exceed ${formatCurrency(_maxUnitPrice)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  FormBreak(Text(
                    'Reliability rating',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )),
                  FormBreak(Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          icon: Icon(
                            _rating >= i ? Icons.star : Icons.star_border,
                            color: AppColors.warning,
                          ),
                          onPressed: () => setState(() => _rating = i.toDouble()),
                        ),
                      Text('${_rating.toStringAsFixed(1)}★'),
                    ],
                  )),
                  FormBreak(Slider(
                    value: _rating,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    label: _rating.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _rating = v),
                  )),
                  FormBreak(Text(
                    'Quoted $leadTime d → planned $effectiveLead d effective lead at '
                    '${_rating.toStringAsFixed(1)}★',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  if (_suggestedRating != null) ...[
                    const SizedBox(height: 8),
                    FormBreak(InfoBanner(
                      status: AppStatus.info,
                      message:
                          'Based on delivery history: suggested '
                          '${_suggestedRating!.toStringAsFixed(1)}★',
                      actionLabel: 'Apply',
                      onAction: () =>
                          setState(() => _rating = _suggestedRating!),
                    )),
                  ],
                  const SizedBox(height: 24),
                  FormBreak(
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
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}
