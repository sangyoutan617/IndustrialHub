import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/manpower.dart';
import '../../services/manpower_service.dart';
import '../../widgets/kpi_card.dart';

class ManpowerFormScreen extends StatefulWidget {
  final int factoryId;
  final Manpower? shift;

  const ManpowerFormScreen({super.key, required this.factoryId, this.shift});

  @override
  State<ManpowerFormScreen> createState() => _ManpowerFormScreenState();
}

class _ManpowerFormScreenState extends State<ManpowerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ManpowerService();

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
  bool _isSaving = false;

  bool get _isEditing => widget.shift != null;

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
    setState(() => _isSaving = true);
    try {
      final shift = Manpower(
        manpowerId: widget.shift?.manpowerId ?? 0,
        factoryId: widget.factoryId,
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
          content: Text('Could not save shift. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit shift' : 'Add shift')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Shift name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SectionHeader(title: 'Shift details'),
              TextFormField(
                controller: _workersController,
                keyboardType: TextInputType.number,
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
                decoration: const InputDecoration(labelText: 'Shift hours'),
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
