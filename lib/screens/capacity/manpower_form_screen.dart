import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/manpower.dart';
import '../../models/product.dart';
import '../../services/manpower_service.dart';
import '../../services/product_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';

final _hoursInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.isEmpty) return newValue;
  final pattern = RegExp(r'^\d{0,2}(\.\d{0,2})?$');
  return pattern.hasMatch(newValue.text) ? newValue : oldValue;
});

final _outputInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.isEmpty) return newValue;
  final pattern = RegExp(r'^\d{0,6}(\.\d{0,2})?$');
  return pattern.hasMatch(newValue.text) ? newValue : oldValue;
});

class ManpowerFormScreen extends StatefulWidget {
  final int factoryId;
  final Manpower? shift;

  const ManpowerFormScreen({super.key, required this.factoryId, this.shift});

  @override
  State<ManpowerFormScreen> createState() => _ManpowerFormScreenState();
}

enum _LoadState { loading, error, ready }

class _ManpowerFormScreenState extends State<ManpowerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ManpowerService();
  final _productService = ProductService();

  late final _nameController = TextEditingController(
    text: widget.shift?.shiftName,
  );
  late final _workersController = TextEditingController(
    text: widget.shift?.workerCount.toString(),
  );
  late final _hoursController = TextEditingController(
    text: widget.shift?.shiftHours.toString(),
  );
  late final _outputController = TextEditingController(
    text: widget.shift?.outputPerWorkerHour.toString(),
  );
  int? _selectedProductId;
  bool _isSaving = false;

  _LoadState _state = _LoadState.loading;
  List<Product> _products = [];

  bool get _isEditing => widget.shift != null;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.shift?.productId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _productService.getProducts(widget.factoryId);
      if (!mounted) return;
      setState(() {
        _products = products;
        _selectedProductId ??= products.isEmpty
            ? null
            : products.firstWhere(
                (p) => !p.isGeneral,
                orElse: () => products.first,
              ).productId;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _workersController.dispose();
    _hoursController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) return;
    setState(() => _isSaving = true);
    try {
      final shift = Manpower(
        manpowerId: widget.shift?.manpowerId ?? 0,
        factoryId: widget.factoryId,
        productId: _selectedProductId!,
        shiftName: _nameController.text.trim(),
        workerCount: int.parse(_workersController.text),
        shiftHours: double.parse(_hoursController.text),
        outputPerWorkerHour: double.parse(_outputController.text),
        isSimulated: false,
      );
      if (_isEditing) {
        await _service.updateShift(widget.shift!.manpowerId, shift);
      } else {
        await _service.createShift(shift);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save station. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit station' : 'Add station')),
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
        if (_products.isEmpty) {
          return const EmptyState(
            icon: Icons.category_outlined,
            message:
                'No products yet — add a product first, a station must be '
                'assigned to one.',
          );
        }
        return _buildForm();
    }
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ResponsiveFormFields(
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Station name',
                  helperText: 'e.g. Filling, Wrapping, Packing',
                  helperMaxLines: 2,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.l),
              AppDropdownField<int>(
                idPrefix: 'product',
                label: 'Product',
                helperText:
                    'This station is one step in this product\'s labour '
                    'flow — the slowest station caps the line',
                helperMaxLines: 3,
                value: _selectedProductId,
                entries: [
                  for (final product in _products)
                    DropdownMenuEntry(
                      value: product.productId,
                      label: product.isGeneral
                          ? '${product.productName} (auto-created)'
                          : product.productName,
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedProductId = value),
              ),
              const FormBreak(SectionHeader(title: 'Station details')),
              TextFormField(
                controller: _workersController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(labelText: 'Worker count'),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null) return 'Enter a valid whole number';
                  if (parsed < 0) return 'Must be at least 0';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _hoursController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_hoursInputFormatter],
                decoration: const InputDecoration(labelText: 'Hours per day'),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null) return 'Enter a valid number';
                  if (parsed < 0 || parsed > 24) {
                    return 'Must be between 0 and 24';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _outputController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_outputInputFormatter],
                decoration: const InputDecoration(
                  labelText: 'Output per worker-hour',
                ),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null) return 'Enter a valid number';
                  if (parsed < 0) return 'Must be at least 0';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
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
