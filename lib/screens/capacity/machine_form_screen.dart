import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/machine.dart';
import '../../models/product.dart';
import '../../services/machine_service.dart';
import '../../services/product_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';

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
  late final _uptimeController = TextEditingController(
    text: (widget.machine?.uptimePercent ?? 100).toString(),
  );
  late String _status = widget.machine?.status ?? 'Active';
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
        // Default a new machine to the first non-General product if one
        // exists — a machine dedicated to nothing in particular should
        // still nudge toward a real product over the migration catch-all.
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
    _ratedController.dispose();
    _hoursController.dispose();
    _uptimeController.dispose();
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
        uptimePercent: double.parse(_uptimeController.text),
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

  String? _requiredNumber(String? value, {double min = 0, double? max}) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value);
    if (parsed == null) return 'Enter a valid number';
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
              DropdownButtonFormField<int>(
                initialValue: _selectedProductId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Product',
                  helperText:
                      'This machine\'s full capacity counts toward this '
                      'product only',
                ),
                items: [
                  for (final product in _products)
                    DropdownMenuItem(
                      value: product.productId,
                      child: Text(
                        product.isGeneral
                            ? '${product.productName} (auto-created)'
                            : product.productName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedProductId = value),
                validator: (v) => v == null ? 'Required' : null,
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
                validator: (v) => _requiredNumber(v, min: 0),
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _hoursController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Operating hours per day',
                ),
                validator: (v) => _requiredNumber(v, min: 0, max: 24),
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _uptimeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Uptime %'),
                validator: (v) => _requiredNumber(v, min: 0, max: 100),
              ),
              const SizedBox(height: AppSpacing.l),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'Under Maintenance',
                    child: Text('Under Maintenance'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? 'Active'),
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
