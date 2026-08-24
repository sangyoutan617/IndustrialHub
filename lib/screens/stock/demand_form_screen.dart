import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/demand_forecast.dart';
import '../../services/demand_service.dart';

class DemandFormScreen extends StatefulWidget {
  final int factoryId;
  final DemandForecast? forecast;

  const DemandFormScreen({super.key, required this.factoryId, this.forecast});

  @override
  State<DemandFormScreen> createState() => _DemandFormScreenState();
}

class _DemandFormScreenState extends State<DemandFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = DemandService();

  late final _nameController = TextEditingController(
    text: widget.forecast?.productName,
  );
  late final _requiredController = TextEditingController(
    text: widget.forecast?.requiredPerDay.toString(),
  );
  DateTime? _periodStart;
  DateTime? _periodEnd;
  bool _isSaving = false;
  bool _isSuggesting = false;
  String? _suggestError;

  bool get _isEditing => widget.forecast != null;

  @override
  void initState() {
    super.initState();
    _periodStart = widget.forecast?.periodStart;
    _periodEnd = widget.forecast?.periodEnd;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _requiredController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _periodStart : _periodEnd) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _periodStart = picked;
      } else {
        _periodEnd = picked;
      }
    });
  }

  Future<void> _suggestFromHistory() async {
    final productName = _nameController.text.trim();
    if (productName.isEmpty) {
      setState(() => _suggestError = 'Enter a product name first.');
      return;
    }
    setState(() {
      _isSuggesting = true;
      _suggestError = null;
    });
    try {
      final suggestion = await _service.suggestRequiredPerDay(
        factoryId: widget.factoryId,
        productName: productName,
      );
      if (suggestion == null) {
        setState(
          () => _suggestError =
              'No shipment history found for "$productName" in the last 30 days.',
        );
      } else {
        _requiredController.text = suggestion.round().toString();
      }
    } catch (_) {
      setState(() => _suggestError = 'Could not load shipment history.');
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final forecast = DemandForecast(
        demandId: widget.forecast?.demandId ?? 0,
        factoryId: widget.factoryId,
        productName: _nameController.text.trim(),
        requiredPerDay: int.parse(_requiredController.text),
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );
      if (_isEditing) {
        await _service.updateForecast(widget.forecast!.demandId, forecast);
      } else {
        await _service.createForecast(forecast);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save demand forecast. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit demand' : 'Add demand')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.l),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  helperText:
                      'Match the product name used in Finished Stock to link them',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _requiredController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Required units per day',
                  helperText:
                      'A number you set, or derive one from shipment history below',
                ),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null || parsed < 0) {
                    return 'Enter a non-negative whole number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.s),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _isSuggesting ? null : _suggestFromHistory,
                  icon: _isSuggesting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_graph, size: 18),
                  label: const Text('Suggest from shipment history'),
                ),
              ),
              if (_suggestError != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _suggestError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.l),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Period start (optional)'),
                subtitle: Text(_formatDate(_periodStart)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pickDate(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Period end (optional)'),
                subtitle: Text(_formatDate(_periodEnd)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pickDate(isStart: false),
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
