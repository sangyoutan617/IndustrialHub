import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters.dart';
import '../../models/product.dart';
import '../../services/capacity_service.dart';
import '../../services/product_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';

class SimulatorScreen extends StatefulWidget {
  final int factoryId;

  const SimulatorScreen({super.key, required this.factoryId});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

enum _LoadState { loading, error, noProducts, ready }

class _SimulatorScreenState extends State<SimulatorScreen> {
  final _capacityService = CapacityService();
  final _productService = ProductService();

  _LoadState _state = _LoadState.loading;
  List<Product> _products = [];
  int? _selectedProductId;
  SimulatorBaseline? _baseline;

  int _machines = 0;
  double _machineHours = 0;
  double _machineRate = 0;
  int _workers = 0;
  double _shiftHours = 0;
  double _outputPerWorkerHour = 0;

  final _machinesCtrl = TextEditingController();
  final _machineHoursCtrl = TextEditingController();
  final _machineRateCtrl = TextEditingController();
  final _workersCtrl = TextEditingController();
  final _shiftHoursCtrl = TextEditingController();
  final _outputPerWorkerHourCtrl = TextEditingController();

  String? _lastBottleneck;
  bool _justFlipped = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _machinesCtrl.dispose();
    _machineHoursCtrl.dispose();
    _machineRateCtrl.dispose();
    _workersCtrl.dispose();
    _shiftHoursCtrl.dispose();
    _outputPerWorkerHourCtrl.dispose();
    super.dispose();
  }

  Product _defaultProduct(List<Product> products) =>
      products.firstWhere((p) => !p.isGeneral, orElse: () => products.first);

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final products = await _productService.getProducts(widget.factoryId);
      if (products.isEmpty) {
        setState(() {
          _products = products;
          _state = _LoadState.noProducts;
        });
        return;
      }
      final selected = _selectedProductId != null
          ? products.firstWhere(
              (p) => p.productId == _selectedProductId,
              orElse: () => _defaultProduct(products),
            )
          : _defaultProduct(products);

      final snapshot = await _capacityService.getSnapshot(
        widget.factoryId,
        productId: selected.productId,
      );
      setState(() {
        _products = products;
        _selectedProductId = selected.productId;
        _baseline = SimulatorBaseline.from(snapshot);
        _resetToActual();
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  void _setProduct(int? productId) {
    if (productId == null || productId == _selectedProductId) return;
    setState(() => _selectedProductId = productId);
    _load();
  }

  void _resetToActual() {
    final baseline = _baseline;
    _machines = baseline?.machines ?? 0;
    _machineHours = baseline?.machineHours ?? 0;
    _machineRate = baseline?.machineRate ?? 0;
    _workers = baseline?.workers ?? 0;
    _shiftHours = baseline?.shiftHours ?? 0;
    _outputPerWorkerHour = baseline?.outputPerWorkerHour ?? 0;
    _lastBottleneck = null;
    _justFlipped = false;

    _machinesCtrl.text = '$_machines';
    _machineHoursCtrl.text = _fmt(_machineHours);
    _machineRateCtrl.text = _fmt(_machineRate);
    _workersCtrl.text = '$_workers';
    _shiftHoursCtrl.text = _fmt(_shiftHours);
    _outputPerWorkerHourCtrl.text = _fmt(_outputPerWorkerHour);
  }

  String _fmt(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  double get _machineCapacity => _machines * _machineHours * _machineRate;

  double get _manpowerCapacity =>
      _workers * _shiftHours * _outputPerWorkerHour;

  double get _effectiveCapacity => _machineCapacity < _manpowerCapacity
      ? _machineCapacity
      : _manpowerCapacity;

  String get _bottleneck => CapacityService.bottleneckResourceFor(
    _machineCapacity,
    _manpowerCapacity,
  );

  void _onFieldChanged(VoidCallback update) {
    setState(() {
      update();
      final current = _bottleneck;
      _justFlipped = _lastBottleneck != null && _lastBottleneck != current;
      _lastBottleneck = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What-if simulator'),
        actions: [
          if (_state == _LoadState.ready)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Reset to actual',
              onPressed: () => setState(_resetToActual),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load simulator data. Please try again.',
          onRetry: _load,
        );
      case _LoadState.noProducts:
        return const EmptyState(
          icon: Icons.category_outlined,
          message:
              'No products yet — add a product first, the simulator prices '
              'what-ifs per product.',
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _selectedProductId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product'),
            items: [
              for (final product in _products)
                DropdownMenuItem(
                  value: product.productId,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      product.isGeneral
                          ? '${product.productName} (auto-created)'
                          : product.productName,
                    ),
                  ),
                ),
            ],
            onChanged: _setProduct,
          ),
          const SizedBox(height: 16),
          _buildResultCard(),
          const SizedBox(height: 24),
          Text('Machine stage', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildField(
            label: 'Number of machines',
            controller: _machinesCtrl,
            decimal: false,
            onValid: (v) => _onFieldChanged(() => _machines = v.toInt()),
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Operating hours per day',
            controller: _machineHoursCtrl,
            decimal: true,
            onValid: (v) => _onFieldChanged(() => _machineHours = v),
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Rated output (units/hour)',
            controller: _machineRateCtrl,
            decimal: true,
            onValid: (v) => _onFieldChanged(() => _machineRate = v),
          ),
          const SizedBox(height: 24),
          Text(
            'Labour station',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Workers',
            controller: _workersCtrl,
            decimal: false,
            onValid: (v) => _onFieldChanged(() => _workers = v.toInt()),
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Shift hours',
            controller: _shiftHoursCtrl,
            decimal: true,
            onValid: (v) => _onFieldChanged(() => _shiftHours = v),
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Output per worker-hour',
            controller: _outputPerWorkerHourCtrl,
            decimal: true,
            onValid: (v) => _onFieldChanged(() => _outputPerWorkerHour = v),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required bool decimal,
    required ValueChanged<double> onValid,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: [
        decimal
            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      onChanged: (text) {
        if (text.isEmpty) return;
        final parsed = double.tryParse(text);
        if (parsed == null || parsed < 0) return;
        onValid(parsed);
      },
    );
  }

  Widget _buildResultCard() {
    final scheme = Theme.of(context).colorScheme;
    final bottleneck = _bottleneck;
    final containerColor = _justFlipped
        ? scheme.tertiaryContainer
        : scheme.primaryContainer;
    final onContainerColor = _justFlipped
        ? scheme.onTertiaryContainer
        : scheme.onPrimaryContainer;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simulated ceiling',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            '${formatUnits(_effectiveCapacity)}/day',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(label: Text('Machine: ${formatNumber(_machineCapacity)}')),
              Chip(
                label: Text('Manpower: ${formatNumber(_manpowerCapacity)}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bottleneck: $bottleneck${_justFlipped ? '  (just changed!)' : ''}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: onContainerColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Models one machine stage against one labour station — the lower '
            'of the two is the ceiling.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
