import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/stock_movement.dart';
import '../../services/stock_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/responsive_form_fields.dart';

class StockMovementFormScreen extends StatefulWidget {
  final int stockId;
  final String productName;
  final int currentQuantity;

  const StockMovementFormScreen({
    super.key,
    required this.stockId,
    required this.productName,
    required this.currentQuantity,
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
  final DateTime _movementDate = DateTime.now();
  bool _isSaving = false;
  bool _isAdjustmentNegative = false;

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

  bool get _isToday {
    final now = DateTime.now();
    return _movementDate.year == now.year &&
        _movementDate.month == now.month &&
        _movementDate.day == now.day;
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
        return 'Select + to add stock, - to deduct stock';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final qty = int.parse(_quantityController.text);
      final finalQty =
          (_movementType == StockMovementType.adjustment &&
              _isAdjustmentNegative)
          ? -qty
          : qty;
      await _service.recordMovementQueued(
        stockId: widget.stockId,
        movementType: _movementType,
        quantity: finalQty,
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
      appBar: AppBar(title: const Text('Record movement')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.l),
            children: [
              ResponsiveFormFields(
                children: [
                  AppDropdownField<String>(
                    idPrefix: 'movement-type',
                    label: 'Movement type',
                    required: false,
                    value: _movementType,
                    entries: [
                      for (final type in StockMovementType.all)
                        DropdownMenuEntry(value: type, label: _typeLabels[type]!),
                    ],
                    onChanged: (value) =>
                        setState(() => _movementType = value ?? _movementType),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  if (_movementType == StockMovementType.adjustment) ...[
                    FormBreak(
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('+ Add'),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('- Deduct'),
                          ),
                        ],
                        selected: {_isAdjustmentNegative},
                        onSelectionChanged: (selection) => setState(
                          () => _isAdjustmentNegative = selection.first,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),
                  ],
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      helperText: _quantityHint,
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      final parsed = int.tryParse(v ?? '');
                      if (parsed == null) return 'Enter a whole number';
                      if (parsed == 0) return 'Must not be zero';
                      if (parsed > 99999999) {
                        return 'Quantity exceeds maximum limit of 99,999,999';
                      }
                      if ((_movementType == StockMovementType.shipmentOut ||
                              _movementType == StockMovementType.damaged) &&
                          parsed > widget.currentQuantity) {
                        return 'Shipment quantity cannot exceed current '
                            'available stock (${widget.currentQuantity})';
                      }
                      if (_movementType == StockMovementType.adjustment &&
                          _isAdjustmentNegative &&
                          parsed > widget.currentQuantity) {
                        return 'Deduction cannot exceed current stock '
                            '(${widget.currentQuantity})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.l),
                  FormBreak(InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      helperText: 'Movements are always recorded for today',
                      helperMaxLines: 2,
                    ),
                    child: Text(
                      '${_movementDate.year}-${_movementDate.month.toString().padLeft(2, '0')}-${_movementDate.day.toString().padLeft(2, '0')}',
                    ),
                  )),
                  const SizedBox(height: AppSpacing.l),
                  TextFormField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: _isToday ? 'Note (optional)' : 'Note',
                      helperText: _isToday
                          ? null
                          : 'Required when recording for a different date',
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      if (!_isToday && (v == null || v.trim().isEmpty)) {
                        return 'Note is required when recording movement '
                            'for a different date';
                      }
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
        ),
      ),
    );
  }
}
