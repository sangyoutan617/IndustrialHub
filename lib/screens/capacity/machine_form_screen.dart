import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/machine.dart';
import '../../models/product.dart';
import '../../services/machine_service.dart';
import '../../services/product_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';

const _maxUnitCount = 100;
const _maxRatedOutput = 100000.0;

final _hoursInputFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.isEmpty) return newValue;
  final pattern = RegExp(r'^\d{0,2}(\.\d{0,2})?$');
  return pattern.hasMatch(newValue.text) ? newValue : oldValue;
});

class MachineFormScreen extends StatefulWidget {
  final int factoryId;
  final Machine? machine;

  const MachineFormScreen({super.key, required this.factoryId, this.machine});

  @override
  State<MachineFormScreen> createState() => _MachineFormScreenState();
}

enum _LoadState { loading, error, ready }

class _MachineFormScreenState extends State<MachineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = MachineService();
  final _productService = ProductService();

  late final _nameController = TextEditingController(
    text: widget.machine?.machineName,
  );
  late final _ratedController = TextEditingController(
    text: widget.machine?.ratedOutputPerHour.toString(),
  );
  late final _hoursController = TextEditingController(
    text: widget.machine?.operatingHoursPerDay.toString(),
  );
  late final _unitCountController = TextEditingController(
    text: (widget.machine?.unitCount ?? 1).toString(),
  );
  late final _stageController = TextEditingController(
    text: widget.machine?.stageLabel,
  );
  late String _status = widget.machine?.status ?? MachineStatus.active;
  int? _selectedProductId;
  bool _isSaving = false;

  _LoadState _state = _LoadState.loading;
  List<Product> _products = [];

  bool get _isEditing => widget.machine != null;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.machine?.productId;
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
            : products
                  .firstWhere((p) => !p.isGeneral, orElse: () => products.first)
                  .productId;
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
    _ratedController.dispose();
    _hoursController.dispose();
    _unitCountController.dispose();
    _stageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) return;
    setState(() => _isSaving = true);
    try {
      final machine = Machine(
        machineId: widget.machine?.machineId ?? 0,
        factoryId: widget.factoryId,
        productId: _selectedProductId!,
        machineName: _nameController.text.trim(),
        ratedOutputPerHour: double.parse(_ratedController.text),
        operatingHoursPerDay: double.parse(_hoursController.text),
        unitCount: int.parse(_unitCountController.text.trim()),
        stage: _stageController.text.trim().isEmpty
            ? null
            : _stageController.text.trim(),
        status: _status,
        isSimulated: false,
      );
      if (_isEditing) {
        await _service.updateMachine(widget.machine!.machineId, machine);
      } else {
        await _service.createMachine(machine);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save machine. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String? _requiredNumber(String? value, {double min = 0, double? max}) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < min) return 'Must be at least ${_trim(min)}';
    if (max != null && parsed > max) return 'Must be at most ${_trim(max)}';
    return null;
  }

  String? _requiredInt(String? value, {int min = 1, int? max}) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < min) return 'Must be at least $min';
    if (max != null && parsed > max) return 'Must be at most $max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit machine' : 'Add machine')),
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
                'No products yet — add a product first, a machine must be '
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
                decoration: const InputDecoration(labelText: 'Machine name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.l),
              AppDropdownField<int>(
                idPrefix: 'product',
                label: 'Product',
                helperText:
                    'This machine\'s full capacity counts toward this '
                    'product only',
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
              const FormBreak(SectionHeader(title: 'Machine details')),
              TextFormField(
                controller: _ratedController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rated output (units/hour)',
                ),
                validator: (v) =>
                    _requiredNumber(v, min: 0, max: _maxRatedOutput),
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _hoursController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_hoursInputFormatter],
                decoration: const InputDecoration(
                  labelText: 'Operating hours per day',
                ),
                validator: (v) => _requiredNumber(v, min: 0, max: 24),
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _unitCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: 'Number of machines in this group',
                  helperText:
                      'Use one row for a group of identical machines — '
                      'capacity counts all of them. Leave as 1 for a single '
                      'machine.',
                  helperMaxLines: 3,
                ),
                validator: (v) => _requiredInt(v, min: 1, max: _maxUnitCount),
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _stageController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Stage / process step (optional)',
                  helperText:
                      'Machines at the same stage run in parallel and add '
                      'up. Different stages form a flow — the slowest one '
                      'caps the line. Leave blank if this is the only '
                      'machine at its step.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              AppDropdownField<String>(
                idPrefix: 'status',
                label: 'Status',
                required: false,
                helperText:
                    'Downtime and Repair are normally set from the '
                    'machine\'s own page — pick them here only to '
                    'correct a stuck status',
                helperMaxLines: 3,
                value: _status,
                entries: [
                  for (final value in MachineStatus.all)
                    DropdownMenuEntry(value: value, label: value),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? MachineStatus.active),
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
