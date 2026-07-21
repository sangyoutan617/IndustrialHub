import 'package:flutter/material.dart';
import '../../models/machine.dart';
import '../../services/machine_service.dart';

class MachineFormScreen extends StatefulWidget {
  final int factoryId;
  final Machine? machine;

  const MachineFormScreen({super.key, required this.factoryId, this.machine});

  @override
  State<MachineFormScreen> createState() => _MachineFormScreenState();
}

class _MachineFormScreenState extends State<MachineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = MachineService();

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
  bool _isSaving = false;

  bool get _isEditing => widget.machine != null;

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
    setState(() => _isSaving = true);
    try {
      final machine = Machine(
        machineId: widget.machine?.machineId ?? 0,
        factoryId: widget.factoryId,
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
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Machine name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _uptimeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Uptime %'),
                validator: (v) => _requiredNumber(v, min: 0, max: 100),
              ),
              const SizedBox(height: 16),
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
