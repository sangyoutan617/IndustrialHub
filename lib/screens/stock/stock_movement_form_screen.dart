import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/stock_movement.dart';
import '../../services/stock_service.dart';

class StockMovementFormScreen extends StatefulWidget {
  final int stockId;
  final String productName;

  const StockMovementFormScreen({
    super.key,
    required this.stockId,
    required this.productName,
  });

  @override
  State<StockMovementFormScreen> createState() =>
      _StockMovementFormScreenState();
}

class _StockMovementFormScreenState extends State<StockMovementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = StockService();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();

  String _movementType = StockMovementType.productionIn;
  DateTime _movementDate = DateTime.now();
  bool _isSaving = false;

  static const _typeLabels = {
    StockMovementType.productionIn: 'Production in',
    StockMovementType.shipmentOut: 'Shipment out',
    StockMovementType.damaged: 'Damaged',
    StockMovementType.returned: 'Returned',
    StockMovementType.adjustment: 'Adjustment',
  };

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String get _quantityHint {
    switch (_movementType) {
      case StockMovementType.productionIn:
        return 'Adds this many units to stock';
      case StockMovementType.shipmentOut:
        return 'Removes this many units from stock';
      case StockMovementType.damaged:
        return 'Removes this many units from stock (damaged or scrapped)';
      case StockMovementType.returned:
        return 'Adds this many units back to stock (customer or site return)';
      default:
        return 'Positive to add, negative to subtract (e.g. a stock count correction)';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _movementDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _movementDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _service.recordMovement(
        stockId: widget.stockId,
        movementType: _movementType,
        quantity: int.parse(_quantityController.text),
        movementDate: _movementDate,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('below zero')
          ? 'This movement would take stock below zero.'
          : 'Could not record movement. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Record movement — ${widget.productName}')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.l),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _movementType,
                decoration: const InputDecoration(labelText: 'Movement type'),
                items: [
                  for (final type in StockMovementType.all)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabels[type]!),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _movementType = value ?? _movementType),
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  helperText: _quantityHint,
                ),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null) return 'Enter a whole number';
                  if (parsed == 0) return 'Must not be zero';
                  if (_movementType != StockMovementType.adjustment &&
                      parsed < 0) {
                    return 'Enter a positive amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.l),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  '${_movementDate.year}-${_movementDate.month.toString().padLeft(2, '0')}-${_movementDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickDate,
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: AppSpacing.xl),
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
