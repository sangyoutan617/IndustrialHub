import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters.dart';
import '../../models/raw_material.dart';
import '../../services/material_service.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/responsive_form_fields.dart';

const _maxUnitCost = 99999999.99;
const _maxUnitLength = 20;
const _maxSafetyStockDays = 30;

final _eightDigitDecimalFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.isEmpty) return newValue;
  final pattern = RegExp(r'^\d{0,8}(\.\d{0,2})?$');
  return pattern.hasMatch(newValue.text) ? newValue : oldValue;
});

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
  late final _unitCostController = TextEditingController(
    text: widget.material?.unitCost?.toString() ?? '',
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
    _unitCostController.dispose();
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
        safetyStockDays: int.parse(_safetyStockController.text),
        unitCost: double.parse(_unitCostController.text),
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

  String? _requiredNumber(String? value, {double min = 0, double? max}) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null) return 'Enter a valid number';
    if (parsed < min) return 'Must be at least $min';
    if (max != null && parsed > max) {
      return 'Must not exceed ${formatNumber(max)}';
    }
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
              ResponsiveFormFields(
                children: [
                  const FormBreak(
                    SectionHeader(
                      title: 'Material details',
                      padding: EdgeInsets.only(bottom: 4),
                    ),
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
                    inputFormatters: [_eightDigitDecimalFormatter],
                    decoration: const InputDecoration(labelText: 'Current stock'),
                    validator: (v) => _requiredNumber(v, min: 0, max: _maxUnitCost),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _unitController,
                    maxLength: _maxUnitLength,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      helperText: 'e.g. kg, litres, rolls',
                    ),
                    validator: (v) {
                      if (v != null && RegExp(r'[0-9]').hasMatch(v)) {
                        return 'Unit must contain letters only';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _unitCostController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_eightDigitDecimalFormatter],
                    decoration: InputDecoration(
                      labelText: 'Unit cost (RM)',
                      helperText: 'Cost per ${_unitController.text.trim().isEmpty ? 'unit' : _unitController.text.trim()} — used for inventory value',
                    ),
                    validator: (v) => _requiredNumber(v, min: 0, max: _maxUnitCost),
                  ),
                  const FormBreak(
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'How much of this material a product consumes is now '
                        'set per-product — open a product and add this '
                        'material to its recipe.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
                  const FormBreak(
                    SectionHeader(
                      title: 'Reorder settings',
                      padding: EdgeInsets.only(top: 20, bottom: 4),
                    ),
                  ),
                  TextFormField(
                    controller: _safetyStockController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Safety stock (days)',
                      helperText:
                          'Extra buffer kept on top of supplier lead time when '
                          'deciding the latest safe reorder date '
                          '(max $_maxSafetyStockDays days)',
                      helperMaxLines: 3,
                    ),
                    validator: (v) {
                      final parsed = int.tryParse(v ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Enter a non-negative whole number';
                      }
                      if (parsed > _maxSafetyStockDays) {
                        return 'Safety stock cannot exceed $_maxSafetyStockDays days';
                      }
                      return null;
                    },
                  ),
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
        ),
      ),
    );
  }
}
