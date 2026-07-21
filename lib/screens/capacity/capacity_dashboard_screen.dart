import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/factory.dart';
import '../../services/capacity_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import 'benchmark_screen.dart';
import 'machine_list_screen.dart';
import 'manpower_list_screen.dart';
import 'simulator_screen.dart';

class CapacityDashboardScreen extends StatefulWidget {
  final Factory factory;

  const CapacityDashboardScreen({super.key, required this.factory});

  @override
  State<CapacityDashboardScreen> createState() =>
      _CapacityDashboardScreenState();
}

enum _LoadState { loading, error, ready }

class _CapacityDashboardScreenState extends State<CapacityDashboardScreen> {
  final _capacityService = CapacityService();
  _LoadState _state = _LoadState.loading;
  CapacitySnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CapacityDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factory.factoryId != widget.factory.factoryId) _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final snapshot = await _capacityService.getSnapshot(
        widget.factory.factoryId,
      );
      setState(() {
        _snapshot = snapshot;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _navigateAndRefresh(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final snapshot = _snapshot!;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Effective capacity',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    '${snapshot.effectiveCapacity.toStringAsFixed(0)} units/day',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('Bottleneck: ${snapshot.bottleneckResource}'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Machine vs manpower capacity',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(height: 180, child: _buildBarChart(snapshot)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildNavTile(
            icon: Icons.precision_manufacturing_outlined,
            title: 'Machines',
            subtitle: '${snapshot.machines.length} recorded',
            onTap: () => _navigateAndRefresh(
              MachineListScreen(factoryId: widget.factory.factoryId),
            ),
          ),
          _buildNavTile(
            icon: Icons.groups_outlined,
            title: 'Manpower',
            subtitle: '${snapshot.shifts.length} shifts recorded',
            onTap: () => _navigateAndRefresh(
              ManpowerListScreen(factoryId: widget.factory.factoryId),
            ),
          ),
          _buildNavTile(
            icon: Icons.tune,
            title: 'What-if simulator',
            subtitle: 'Explore hypothetical capacity live',
            onTap: () => _navigateAndRefresh(
              SimulatorScreen(factoryId: widget.factory.factoryId),
            ),
          ),
          _buildNavTile(
            icon: Icons.public,
            title: 'Benchmark vs Malaysia',
            subtitle: 'Compare against DOSM national data',
            onTap: () =>
                _navigateAndRefresh(BenchmarkScreen(factory: widget.factory)),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(CapacitySnapshot snapshot) {
    final maxY =
        [
          snapshot.machineCapacity,
          snapshot.manpowerCapacity,
          1.0,
        ].reduce((a, b) => a > b ? a : b) *
        1.2;
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final label = value == 0
                    ? 'Machine'
                    : (value == 1 ? 'Manpower' : '');
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(label),
                );
              },
            ),
          ),
        ),
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: snapshot.machineCapacity,
                color: Theme.of(context).colorScheme.primary,
                width: 40,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: snapshot.manpowerCapacity,
                color: Theme.of(context).colorScheme.secondary,
                width: 40,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
