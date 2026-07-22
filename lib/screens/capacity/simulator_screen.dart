import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/machine.dart';
import '../../models/manpower.dart';
import '../../services/capacity_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

class SimulatorScreen extends StatefulWidget {
  final int factoryId;

  const SimulatorScreen({super.key, required this.factoryId});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

enum _LoadState { loading, error, ready }

class _SimulatorScreenState extends State<SimulatorScreen> {
  final _capacityService = CapacityService();
  _LoadState _state = _LoadState.loading;

  List<Machine> _machines = [];
  List<Manpower> _shifts = [];

  double _avgRatedOutputPerHour = 0;
  double _avgOperatingHoursPerDay = 0;
  double _avgOutputPerWorkerHour = 0;

  late double _workers;
  late double _shiftHours;
  late double _activeMachines;
  late double _uptimePercent;

  String? _lastBottleneck;
  bool _justFlipped = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final snapshot = await _capacityService.getSnapshot(widget.factoryId);
      setState(() {
        _machines = snapshot.machines;
        _shifts = snapshot.shifts;
        _avgRatedOutputPerHour = _average(
          _machines.map((m) => m.ratedOutputPerHour),
        );
        _avgOperatingHoursPerDay = _average(
          _machines.map((m) => m.operatingHoursPerDay),
        );
        _avgOutputPerWorkerHour = _average(
          _shifts.map((s) => s.outputPerWorkerHour),
        );
        _resetToActual();
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  double _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  void _resetToActual() {
    _workers = _shifts.fold<int>(0, (sum, s) => sum + s.workerCount).toDouble();
    _shiftHours = _average(_shifts.map((s) => s.shiftHours));
    _activeMachines = _machines.where((m) => m.isActive).length.toDouble();
    _uptimePercent = _average(_machines.map((m) => m.uptimePercent));
    if (_uptimePercent == 0 && _machines.isEmpty) _uptimePercent = 100;
    _lastBottleneck = null;
    _justFlipped = false;
  }

  double get _machineCapacity =>
      _activeMachines *
      _avgRatedOutputPerHour *
      _avgOperatingHoursPerDay *
      (_uptimePercent / 100);

  double get _manpowerCapacity =>
      _workers * _shiftHours * _avgOutputPerWorkerHour;

  double get _effectiveCapacity => _machineCapacity < _manpowerCapacity
      ? _machineCapacity
      : _manpowerCapacity;

  String get _bottleneck => CapacityService.bottleneckResourceFor(
    _machineCapacity,
    _manpowerCapacity,
  );

  void _onSliderChanged(VoidCallback update) {
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
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildResultCard(),
              const SizedBox(height: 24),
              Text('Manpower', style: Theme.of(context).textTheme.titleMedium),
              _buildSlider(
                label: 'Workers',
                value: _workers,
                min: 0,
                max: (_workers < 100 ? 100 : _workers * 2),
                display: _workers.toStringAsFixed(0),
                onChanged: (v) => _onSliderChanged(() => _workers = v),
              ),
              _buildSlider(
                label: 'Shift hours',
                value: _shiftHours,
                min: 0,
                max: 24,
                display: '${_shiftHours.toStringAsFixed(1)} h',
                onChanged: (v) => _onSliderChanged(() => _shiftHours = v),
              ),
              const SizedBox(height: 16),
              Text('Machines', style: Theme.of(context).textTheme.titleMedium),
              _buildSlider(
                label: 'Active machines',
                value: _activeMachines,
                min: 0,
                max: (_machines.isEmpty ? 10 : _machines.length.toDouble()),
                display: _activeMachines.toStringAsFixed(0),
                onChanged: (v) => _onSliderChanged(() => _activeMachines = v),
              ),
              _buildSlider(
                label: 'Uptime %',
                value: _uptimePercent,
                min: 0,
                max: 100,
                display: '${_uptimePercent.toStringAsFixed(0)}%',
                onChanged: (v) => _onSliderChanged(() => _uptimePercent = v),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(display, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max <= min ? min + 1 : max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    final scheme = Theme.of(context).colorScheme;
    final bottleneck = _bottleneck;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: _justFlipped
            ? AppColors.primaryAccent
            : scheme.primaryContainer,
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
            '${_effectiveCapacity.toStringAsFixed(0)} units/day',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(
                label: Text('Machine: ${_machineCapacity.toStringAsFixed(0)}'),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  'Manpower: ${_manpowerCapacity.toStringAsFixed(0)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bottleneck: $bottleneck${_justFlipped ? '  (just changed!)' : ''}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: scheme.onPrimaryContainer,
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
