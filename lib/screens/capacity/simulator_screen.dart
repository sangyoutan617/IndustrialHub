import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/formatters.dart';
import '../../models/machine.dart';
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

  List<Machine> _machines = [];
  List<Product> _products = [];
  int? _selectedProductId;

  /// Rates the sliders extrapolate from. Weighted so the untouched baseline
  /// reproduces the same ceiling the Capacity dashboard shows.
  SimulatorBaseline? _baseline;

  // Simulation state — always whole numbers per user requirement.
  int _workers = 0;
  int _shiftHours = 0;
  int _activeMachines = 0;
  int _uptimePercent = 100;

  // Controllers are late final so their text (and therefore any partially
  // typed value) survives orientation changes without re-fetching data.
  late final TextEditingController _workersCtrl;
  late final TextEditingController _shiftHoursCtrl;
  late final TextEditingController _activeMachinesCtrl;
  late final TextEditingController _uptimePercentCtrl;

  String? _lastBottleneck;
  bool _justFlipped = false;

  @override
  void initState() {
    super.initState();
    _workersCtrl = TextEditingController();
    _shiftHoursCtrl = TextEditingController();
    _activeMachinesCtrl = TextEditingController();
    _uptimePercentCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _workersCtrl.dispose();
    _shiftHoursCtrl.dispose();
    _activeMachinesCtrl.dispose();
    _uptimePercentCtrl.dispose();
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
        _machines = snapshot.machines;
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
    _workers = baseline?.workers ?? 0;
    _shiftHours = baseline?.shiftHours ?? 0;
    _uptimePercent = baseline?.uptimePercent ?? 100;
    _activeMachines = baseline?.activeMachines ?? 0;
    _lastBottleneck = null;
    _justFlipped = false;

    // Sync text controllers to the newly computed values.
    _workersCtrl.text = '$_workers';
    _shiftHoursCtrl.text = '$_shiftHours';
    _activeMachinesCtrl.text = '$_activeMachines';
    _uptimePercentCtrl.text = '$_uptimePercent';
  }

  double get _machineCapacity {
    final baseline = _baseline;
    if (baseline == null) return 0;
    return _activeMachines * baseline.machineNameplate * (_uptimePercent / 100);
  }

  double get _manpowerCapacity {
    final baseline = _baseline;
    if (baseline == null) return 0;
    return _workers * _shiftHours * baseline.outputPerWorkerHour;
  }

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
        final productPicker = DropdownButtonFormField<int>(
          initialValue: _selectedProductId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Product'),
          items: [
            for (final product in _products)
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
          onChanged: _setProduct,
        );
        final resultCard = _buildResultCard();
        final manpowerSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manpower', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildIntField(
              label: 'Workers',
              controller: _workersCtrl,
              hint: 'e.g. 20',
              max: 9999,
              onValid: (v) => _onFieldChanged(() => _workers = v),
            ),
            const SizedBox(height: 12),
            _buildIntField(
              label: 'Shift hours',
              controller: _shiftHoursCtrl,
              hint: '0 – 24',
              max: 24,
              onValid: (v) => _onFieldChanged(() => _shiftHours = v),
            ),
          ],
        );
        final machinesSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Machines', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildIntField(
              label: 'Active machines',
              controller: _activeMachinesCtrl,
              hint: _machines.isEmpty ? 'e.g. 5' : '0 – ${_machines.length}',
              max: _machines.isEmpty ? 9999 : _machines.length,
              onValid: (v) => _onFieldChanged(() => _activeMachines = v),
            ),
            const SizedBox(height: 12),
            _buildIntField(
              label: 'Uptime %',
              controller: _uptimePercentCtrl,
              hint: '0 – 100',
              max: 100,
              onValid: (v) => _onFieldChanged(() => _uptimePercent = v),
            ),
          ],
        );

        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              productPicker,
              const SizedBox(height: 16),
              resultCard,
              const SizedBox(height: 24),
              manpowerSection,
              const SizedBox(height: 16),
              machinesSection,
            ],
          ),
        );
    }
  }

  /// A labelled [TextFormField] that accepts only whole (non-negative integer)
  /// numbers. Live-updates the simulation on every valid keystroke.
  ///
  /// Validation rules:
  /// - Digits only (no decimal point, no sign) — enforced by [FilteringTextInputFormatter].
  /// - Value must be between 0 and [max] inclusive.
  /// - Empty field and out-of-range values show an inline error but do NOT
  ///   update the simulation (last valid value is retained).
  Widget _buildIntField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required int max,
    required ValueChanged<int> onValid,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      // Reject any non-digit character at the input layer — no decimal point,
      // no minus sign, no spaces.
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      onChanged: (text) {
        // Do not update while the field is being cleared or partially typed.
        if (text.isEmpty) return;
        final parsed = int.tryParse(text);
        if (parsed == null || parsed < 0 || parsed > max) return;
        onValid(parsed);
      },
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Enter a whole number';
        final parsed = int.tryParse(value);
        if (parsed == null) return 'Whole numbers only (no decimals)';
        if (parsed < 0) return 'Must be 0 or more';
        if (parsed > max) return 'Maximum is $max';
        return null;
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
              Chip(label: Text('Manpower: ${formatNumber(_manpowerCapacity)}')),
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
          if (bottleneck == 'MACHINE') ...[
            const SizedBox(height: 8),
            const Text(
              'Adding workers no longer helps — machines are now the limit.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}
