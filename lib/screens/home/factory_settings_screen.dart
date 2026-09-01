import 'package:flutter/material.dart';
import '../../core/malaysian_states.dart';
import '../../models/factory.dart';
import '../../models/msic_code.dart';
import '../../services/capacity_service.dart';
import '../../services/factory_service.dart';
import '../../widgets/msic_field.dart';
import '../../widgets/responsive_form_fields.dart';

class FactorySettingsScreen extends StatefulWidget {
  final Factory factory;

  const FactorySettingsScreen({super.key, required this.factory});

  @override
  State<FactorySettingsScreen> createState() => _FactorySettingsScreenState();
}

class _FactorySettingsScreenState extends State<FactorySettingsScreen> {
  final _factoryService = FactoryService();
  final _capacityService = CapacityService();
  final _formKey = GlobalKey<FormState>();

  late final _locationController = TextEditingController(
    text: widget.factory.location,
  );
  late String? _selectedState = malaysianStates.contains(widget.factory.state)
      ? widget.factory.state
      : null;
  late String? _selectedMsic = widget.factory.msicCode;

  List<MsicCode> _msicCodes = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadMsic();
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadMsic() async {
    try {
      final codes = await _capacityService.getMsicCodes();
      if (!mounted) return;
      setState(() {
        _msicCodes = codes;
        if (_selectedMsic != null &&
            !codes.any((c) => c.msicCode == _selectedMsic)) {
          _selectedMsic = null;
        }
      });
    } catch (_) {
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final updated = await _factoryService.updateFactoryDetails(
        widget.factory.factoryId,
        location: _locationController.text.trim(),
        state: _selectedState,
        msicCode: _selectedMsic,
      );
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save factory details. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Factory settings')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ResponsiveFormFields(
                children: [
                  FormBreak(
                    Text(
                      widget.factory.factoryName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _locationController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Location / city (e.g. Shah Alam)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedState,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State'),
                    items: [
                      for (final state in malaysianStates)
                        DropdownMenuItem(value: state, child: Text(state)),
                    ],
                    onChanged: (v) => setState(() => _selectedState = v),
                  ),
                  const SizedBox(height: 16),
                  MsicField(
                    codes: _msicCodes,
                    selectedCode: _selectedMsic,
                    onChanged: (v) => setState(() => _selectedMsic = v),
                  ),
                  const SizedBox(height: 28),
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
