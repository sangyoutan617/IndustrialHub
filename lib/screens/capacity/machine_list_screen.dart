import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/machine.dart';
import '../../models/product.dart';
import '../../services/capacity_service.dart';
import '../../services/machine_service.dart';
import '../../services/product_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_grid_list.dart';
import '../../widgets/status.dart';
import 'machine_form_screen.dart';

class MachineListScreen extends StatefulWidget {
  final int factoryId;

  const MachineListScreen({super.key, required this.factoryId});

  @override
  State<MachineListScreen> createState() => _MachineListScreenState();
}

enum _LoadState { loading, error, ready }

class _MachineListScreenState extends State<MachineListScreen> {
  final _service = MachineService();
  final _productService = ProductService();
  _LoadState _state = _LoadState.loading;
  List<Machine> _machines = [];
  Map<int, String> _productNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final results = await Future.wait<dynamic>([
        _service.getMachines(widget.factoryId),
        _productService.getProducts(widget.factoryId),
      ]);
      final machines = results[0] as List<Machine>;
      final products = results[1] as List<Product>;
      setState(() {
        _machines = machines;
        _productNames = {
          for (final p in products) p.productId: p.productName,
        };
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openForm({Machine? machine}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MachineFormScreen(factoryId: widget.factoryId, machine: machine),
      ),
    );
    if (saved == true) {
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(machine == null ? 'Machine added' : 'Machine updated'),
        ),
      );
    }
  }

  Future<void> _delete(Machine machine) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Decommission machine?',
      message:
          'This removes "${machine.machineName}" permanently. This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      await _service.deleteMachine(machine.machineId);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Machine removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete machine. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Machines')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load machines. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_machines.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.precision_manufacturing_outlined,
                  title: 'No machines yet',
                  subtitle: 'Add your first machine to calculate capacity.',
                  actionLabel: 'Add machine',
                  onAction: () => _openForm(),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ResponsiveGridList(
            padding: const EdgeInsets.all(8),
            itemCount: _machines.length,
            itemBuilder: (context, index) {
              final machine = _machines[index];
              final isActive = machine.isActive;
              final contribution = isActive
                  ? CapacityService.computeMachineCapacity([machine])
                  : 0.0;
              return Card(
                child: ListTile(
                  title: Text(
                    machine.machineName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusChip(
                              label: isActive ? 'Active' : 'Maintenance',
                              status: isActive
                                  ? AppStatus.success
                                  : AppStatus.warning,
                              dense: true,
                            ),
                            const SizedBox(width: AppSpacing.s),
                            Expanded(
                              child: Text(
                                isActive
                                    ? '${formatUnits(contribution)}/day'
                                    : 'Excluded from capacity (${machine.status})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _productNames[machine.productId] ?? 'Unknown product',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isActive
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      isActive ? Icons.check : Icons.build_circle_outlined,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openForm(machine: machine),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(machine),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}
