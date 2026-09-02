import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/demand_forecast.dart';
import '../../models/product.dart';
import '../../services/demand_service.dart';
import '../../services/product_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_form_fields.dart';

class DemandFormScreen extends StatefulWidget {
  final int factoryId;
  final DemandForecast? forecast;

  const DemandFormScreen({super.key, required this.factoryId, this.forecast});

  @override
  State<DemandFormScreen> createState() => _DemandFormScreenState();
}

enum _LoadState { loading, error, ready }

class _DemandFormScreenState extends State<DemandFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = DemandService();
  final _productService = ProductService();

  late final _requiredController = TextEditingController(
    text: widget.forecast?.requiredPerDay.toString(),
  );

  _LoadState _state = _LoadState.loading;
  List<Product> _products = [];
  Set<int> _productIdsWithForecast = {};
  int? _selectedProductId;

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
    _selectedProductId = widget.forecast?.productId;
    _load();
  }

  List<Product> get _availableProducts {
    if (_isEditing) return _products;
    return _products
        .where((p) => !_productIdsWithForecast.contains(p.productId))
        .toList();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _productService.getProducts(widget.factoryId);
      final forecasts = await _service.getForecasts(widget.factoryId);
      if (!mounted) return;
      setState(() {
        _products = products;
        _productIdsWithForecast = forecasts
            .where((f) => f.demandId != widget.forecast?.demandId)
            .map((f) => f.productId)
            .toSet();
        final available = _isEditing
            ? products
            : products
                  .where(
                    (p) => !_productIdsWithForecast.contains(p.productId),
                  )
                  .toList();
        _selectedProductId ??= available.isEmpty
            ? null
            : available.firstWhere(
                (p) => !p.isGeneral,
                orElse: () => available.first,
              ).productId;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  void dispose() {
    _requiredController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final firstDate = isStart ? DateTime(2020) : (_periodStart ?? DateTime(2020));
    final lastDate = isStart ? (_periodEnd ?? DateTime(2100)) : DateTime(2100);
    var initial = (isStart ? _periodStart : _periodEnd) ?? DateTime.now();
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
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
    final productId = _selectedProductId;
    if (productId == null) return;
    setState(() {
      _isSuggesting = true;
      _suggestError = null;
    });
    try {
      final suggestion = await _service.suggestRequiredPerDay(
        factoryId: widget.factoryId,
        productId: productId,
      );
      if (suggestion == null) {
        final productName = _products
            .firstWhere((p) => p.productId == productId)
            .productName;
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
    final productId = _selectedProductId;
    if (productId == null) return;
    final start = _periodStart;
    final end = _periodEnd;
    if (start != null && end != null && end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Period end can\'t be before period start.'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final productName = _products
          .firstWhere((p) => p.productId == productId)
          .productName;
      final forecast = DemandForecast(
        demandId: widget.forecast?.demandId ?? 0,
        factoryId: widget.factoryId,
        productId: productId,
        productName: productName,
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
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        if (_products.isEmpty) {
          return const EmptyState(
            icon: Icons.category_outlined,
            message:
                'No products yet — add a product first, a demand forecast '
                'must target one.',
          );
        }
        if (_availableProducts.isEmpty) {
          return const EmptyState(
            icon: Icons.category_outlined,
            message:
                'Every product already has a demand forecast — edit the '
                'existing one instead of adding a new one.',
          );
        }
        return _buildForm();
    }
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          ResponsiveFormFields(
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selectedProductId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  for (final product in _availableProducts)
                    DropdownMenuItem(
                      value: product.productId,
                      child: Text(
                        product.isGeneral
                            ? '${product.productName} (auto-created)'
                            : product.productName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _isEditing
                    ? null
                    : (value) => setState(() => _selectedProductId = value),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.l),
              TextFormField(
                controller: _requiredController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: const InputDecoration(
                  labelText: 'Required units per day',
                  helperText:
                      'A number you set, or derive one from shipment history below',
                ),
                validator: (v) {
                  final parsed = int.tryParse(v ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Daily demand must be greater than 0';
                  }
                  if (parsed > 99999999) {
                    return 'Required units cannot exceed 99,999,999';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.s),
              FormBreak(
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: (_isSuggesting || _selectedProductId == null)
                        ? null
                        : _suggestFromHistory,
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
              ),
              if (_suggestError != null)
                FormBreak(
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      _suggestError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    );
  }
}
