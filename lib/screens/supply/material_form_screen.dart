import 'package:flutter/material.dart';
import '../../models/raw_material.dart';
import '../../services/material_service.dart';
import '../../widgets/kpi_card.dart';

class MaterialFormScreen extends StatefulWidget {
  final int factoryId;
  final RawMaterial? material;

  const MaterialFormScreen({super.key, required this.factoryId, this.material});

  @override
  State<MaterialFormScreen> createState() => _MaterialFormScreenState();
}

class _MaterialFormScreenState extends State<MaterialFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = MaterialService();

  late final _nameController = TextEditingController(
    text: widget.material?.materialName,
  );
  late final _stockController = TextEditingController(
    text: widget.material?.currentStock.toString(),
  );
  late final _unitController = TextEditingController(
    text: widget.material?.unit ?? 'kg',
  );
  late final _consumptionController = TextEditingController(
    text: widget.material?.consumptionPerUnit.toString(),
  );
  late final _reorderController = TextEditingController(
    text: (widget.material?.reorderLevel ?? 0).toString(),
  );
  late final _safetyStockController = TextEditingController(
    text: (widget.material?.safetyStockDays ?? 3).toString(),
  );
  bool _isSaving = false;

  bool get _isEditing => widget.material != null;

  @override
  void dispose() {
    _nameController.dispose();
    _stockController.dispose();
    _unitController.dispose();
    _consumptionController.dispose();
    _reorderController.dispose();
    _safetyStockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final material = RawMaterial(
        materialId: widget.material?.materialId ?? 0,
        factoryId: widget.factoryId,
        materialName: _nameController.text.trim(),
        currentStock: double.parse(_stockController.text),
        unit: _unitController.text.trim().isEmpty
            ? 'kg'
            : _unitController.text.trim(),
        consumptionPerUnit: double.parse(_consumptionController.text),
        reorderLevel: double.parse(_reorderController.text),
        safetyStockDays: int.parse(_safetyStockController.text),
      );
      if (_isEditing) {
        await _service.updateMaterial(widget.material!.materialId, material);
      } else {
        await _service.createMaterial(material);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save material. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _requiredNumber(String? value, {double min = 0}) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null) return 'Enter a valid number';
    if (parsed < min) return 'Must be at least $min';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit material' : 'Add material'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionHeader(
                title: 'Material details',
                padding: EdgeInsets.only(bottom: 4),
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Material name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stockController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Current stock'),
                validator: (v) => _requiredNumber(v, min: 0),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  helperText: 'e.g. kg, litres, rolls',
                ),
              ),
              const SectionHeader(
                title: 'Consumption & reorder settings',
                padding: EdgeInsets.only(top: 20, bottom: 4),
              ),
              TextFormField(
                controller: _consumptionController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Consumption per product unit',
                  helperText:
                      'How much of this material one produced unit uses',
                ),
                validator: (v) => _requiredNumber(v, min: 0),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reorderController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Reorder level'),
                validator: (v) => _requiredNumber(v, min: 0),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _safetyStockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Safety stock (days)',
                  helperText:
                      'Extra buffer kept on top of supplier lead time when '
                      'deciding the latest safe reorder date',
                ),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative whole number';
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
        ),
      ),
    );
  }
}
