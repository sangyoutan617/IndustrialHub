import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/raw_material.dart';
import '../../models/supplier.dart';
import '../../services/material_service.dart';
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

  late final _nameController = TextEditingController(
    text: widget.supplier?.supplierName,
  );
  late final _locationController = TextEditingController(
    text: widget.supplier?.location,
  );
  late final _leadTimeController = TextEditingController(
    text: (widget.supplier?.leadTimeDays ?? 7).toString(),
  );
  late final _ratingController = TextEditingController(
    text: (widget.supplier?.reliabilityRating ?? 0).toString(),
  );

  _LoadState _state = _LoadState.loading;
  List<RawMaterial> _materials = [];
  int? _selectedMaterialId;
  bool _isSaving = false;
  SupplierLeadTimeStats? _leadTimeStats;

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
      SupplierLeadTimeStats? leadTimeStats;
      if (widget.supplier != null) {
        final stats = await _supplierService.getActualLeadTimeStats([
          widget.supplier!.supplierId,
        ]);
        leadTimeStats = stats[widget.supplier!.supplierId];
      }
      setState(() {
        _materials = materials;
        _selectedMaterialId ??= materials.isNotEmpty
            ? materials.first.materialId
            : null;
        _leadTimeStats = leadTimeStats;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _leadTimeController.dispose();
    _ratingController.dispose();
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
        reliabilityRating: double.parse(_ratingController.text),
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
    } catch (_) {
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

  Widget _buildLeadTimeCard() {
    final stats = _leadTimeStats;
    final promised = widget.supplier!.leadTimeDays;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lead time',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              stats == null
                  ? 'Promised $promised days · no delivered orders yet to compare'
                  : 'Promised $promised days · Actual average '
                        '${stats.actualAverageDays.toStringAsFixed(1)} days '
                        '(${stats.deliveredCount} delivered order${stats.deliveredCount == 1 ? '' : 's'})',
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (stats?.onTimePercent != null) ...[
              const SizedBox(height: 4),
              Text('On-time: ${stats!.onTimePercent!.toStringAsFixed(0)}%'),
            ],
          ],
        ),
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
        if (_materials.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_outlined,
            message:
                'Add a raw material first — a supplier must be linked to one.',
          );
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isEditing) _buildLeadTimeCard(),
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
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative whole number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ratingController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Reliability rating (0-5)',
                ),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null || parsed < 0 || parsed > 5) {
                    return 'Enter a number between 0 and 5';
                  }
                  return null;
                },
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
