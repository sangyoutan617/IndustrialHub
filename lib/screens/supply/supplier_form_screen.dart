import 'package:flutter/material.dart';
import '../../models/raw_material.dart';
import '../../models/supplier.dart';
import '../../services/material_service.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

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
  late final _leadTimeController = TextEditingController(
    text: (widget.supplier?.leadTimeDays ?? 7).toString(),
  );
  late double _rating = widget.supplier?.reliabilityRating ?? 3;

  _LoadState _state = _LoadState.loading;
  List<RawMaterial> _materials = [];
  int? _selectedMaterialId;
  double? _suggestedRating;
  bool _isSaving = false;

  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    _selectedMaterialId = widget.supplier?.materialId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final materials = await _materialService.getMaterials(widget.factoryId);
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
      setState(() {
        _materials = materials;
        _selectedMaterialId ??= materials.isNotEmpty
            ? materials.first.materialId
            : null;
        _suggestedRating = suggested;
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load supplier form data: $e');
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _leadTimeController.dispose();
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
      );
      if (_isEditing) {
        await _supplierService.updateSupplier(
          widget.supplier!.supplierId,
          supplier,
        );
      } else {
        await _supplierService.createSupplier(supplier);
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
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Supplier name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedMaterialId,
                decoration: const InputDecoration(
                  labelText: 'Supplies which material',
                ),
                items: [
                  for (final material in _materials)
                    DropdownMenuItem(
                      value: material.materialId,
                      child: Text(material.materialName),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _selectedMaterialId = value),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _leadTimeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Lead time (days)',
                  helperText: 'How long an order takes to arrive',
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative whole number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Reliability rating',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        _rating >= i ? Icons.star : Icons.star_border,
                        color: Colors.amber.shade700,
                      ),
                      onPressed: () => setState(() => _rating = i.toDouble()),
                    ),
                  Text('${_rating.toStringAsFixed(1)}★'),
                ],
              ),
              Slider(
                value: _rating,
                min: 0,
                max: 5,
                divisions: 10,
                label: _rating.toStringAsFixed(1),
                onChanged: (v) => setState(() => _rating = v),
              ),
              Text(
                'Quoted $leadTime d → planned $effectiveLead d effective lead at '
                '${_rating.toStringAsFixed(1)}★',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_suggestedRating != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Based on delivery history: suggested '
                          '${_suggestedRating!.toStringAsFixed(1)}★',
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _rating = _suggestedRating!),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ),
              ],
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
