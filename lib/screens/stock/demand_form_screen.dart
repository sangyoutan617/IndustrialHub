import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/demand_forecast.dart';
import '../../services/demand_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/responsive_form_fields.dart';
import 'stock_cover_loader.dart';

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
  final _stockService = StockService();

  late final _nameController = TextEditingController(
    text: widget.forecast?.productName,
  );
  late final _requiredController = TextEditingController(
    text: widget.forecast?.requiredPerDay.toString(),
  );
  final _nameFocus = FocusNode();

  /// Existing finished-stock product names. Demand is joined to stock by
  /// name with no foreign key, so offering the real names is what stops a
  /// forecast being saved against a product that doesn't exist.
  List<String> _productNames = [];
  bool _productNamesLoaded = false;

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
    _nameController.addListener(_onNameChanged);
    _loadProductNames();
  }

  Future<void> _loadProductNames() async {
    try {
      final stock = await _stockService.getStockList(widget.factoryId);
      if (!mounted) return;
      setState(() {
        _productNames = stock.map((s) => s.productName).toList();
        _productNamesLoaded = true;
      });
    } catch (_) {
      // A failed lookup only costs the picker and the warning below — the
      // form still saves, exactly as it did before there was a picker.
      if (mounted) setState(() => _productNamesLoaded = true);
    }
  }

  void _onNameChanged() {
    if (_productNamesLoaded) setState(() {});
  }

  /// Whether what's typed currently lands on a real product, using the same
  /// normalisation [loadStockOverview] joins on.
  bool get _nameMatchesProduct {
    final typed = normaliseProductName(_nameController.text);
    if (typed.isEmpty) return true;
    return _productNames.map(normaliseProductName).contains(typed);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _requiredController.dispose();
    _nameFocus.dispose();
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

  /// The product name field, backed by the real finished-stock names.
  ///
  /// [RawAutocomplete] rather than [Autocomplete] because the surrounding
  /// form already owns [_nameController] — the save path and the
  /// suggest-from-history button both read it — and only RawAutocomplete
  /// accepts an external controller.
  Widget _buildProductNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<String>(
          textEditingController: _nameController,
          focusNode: _nameFocus,
          optionsBuilder: (value) {
            final typed = normaliseProductName(value.text);
            if (typed.isEmpty) return _productNames;
            return _productNames.where(
              (name) => normaliseProductName(name).contains(typed),
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              onFieldSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                labelText: 'Product name',
                helperText: _productNames.isEmpty
                    ? 'Match the product name used in Finished Stock to link them'
                    : 'Pick an existing product so the forecast links to it',
                suffixIcon: _productNames.isEmpty
                    ? null
                    : const Icon(Icons.arrow_drop_down),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final items = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(items[index]),
                      onTap: () => onSelected(items[index]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (_productNamesLoaded && !_nameMatchesProduct)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: _buildUnmatchedNameWarning(),
          ),
      ],
    );
  }

  /// Shown while the typed name lands on no product. This forecast would
  /// still save — demand is allowed to run ahead of a product being created
  /// — but it would count toward nothing until the names agree, which is
  /// exactly the silent failure worth naming out loud.
  Widget _buildUnmatchedNameWarning() {
    final suggestion = closestProductName(_nameController.text, _productNames);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _productNames.isEmpty
                    ? 'No finished-stock products exist yet, so this forecast '
                          'will not count toward days of cover.'
                    : 'No product with this name — this forecast will not '
                          'count toward days of cover.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              ),
              if (suggestion != null)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    _nameController.text = suggestion;
                    _nameController.selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                  },
                  child: Text('Use "$suggestion"'),
                ),
            ],
          ),
        ),
      ],
    );
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
              ResponsiveFormFields(
                children: [
                  _buildProductNameField(),
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
                  FormBreak(
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _isSuggesting ? null : _suggestFromHistory,
                        icon: _isSuggesting
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_graph, size: 18),
                        label: const Text('Suggest from shipment history'),
                      ),
                    ),
                  ),
                  if (_suggestError != null)
                    FormBreak(
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          _suggestError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.l),
                  FormBreak(
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Period start (optional)'),
                      subtitle: Text(_formatDate(_periodStart)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  FormBreak(
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Period end (optional)'),
                      subtitle: Text(_formatDate(_periodEnd)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDate(isStart: false),
                    ),
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
