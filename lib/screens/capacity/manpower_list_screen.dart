import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/manpower.dart';
import '../../models/product.dart';
import '../../services/capacity_service.dart';
import '../../services/manpower_service.dart';
import '../../services/product_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import 'manpower_form_screen.dart';

class ManpowerListScreen extends StatefulWidget {
  final int factoryId;

  const ManpowerListScreen({super.key, required this.factoryId});

  @override
  State<ManpowerListScreen> createState() => _ManpowerListScreenState();
}

enum _LoadState { loading, error, ready }

class _ManpowerListScreenState extends State<ManpowerListScreen> {
  final _service = ManpowerService();
  final _productService = ProductService();
  _LoadState _state = _LoadState.loading;
  List<Manpower> _shifts = [];
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
        _service.getShifts(widget.factoryId),
        _productService.getProducts(widget.factoryId),
      ]);
      final shifts = results[0] as List<Manpower>;
      final products = results[1] as List<Product>;
      setState(() {
        _shifts = shifts;
        _productNames = {
          for (final p in products) p.productId: p.productName,
        };
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openForm({Manpower? shift}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ManpowerFormScreen(factoryId: widget.factoryId, shift: shift),
      ),
    );
    if (saved == true) {
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shift == null ? 'Station added' : 'Station updated'),
        ),
      );
    }
  }

  Future<void> _delete(Manpower shift) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove station?',
      message:
          'This removes "${shift.shiftName}" permanently. This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      await _service.deleteShift(shift.manpowerId);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Station removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete station. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manpower')),
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
          message: 'Could not load manpower shifts. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_shifts.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No stations yet',
                  subtitle:
                      'Add your first labour station to track capacity.',
                  actionLabel: 'Add station',
                  onAction: () => _openForm(),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              OrientationBuilder(
                builder: (context, orientation) {
                  if (orientation == Orientation.landscape) {
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        childAspectRatio: 3.0,
                      ),
                      itemCount: _shifts.length,
                      itemBuilder: (context, index) => _buildShiftCard(_shifts[index]),
                    );
                  }
                  return Column(
                    children: [for (final shift in _shifts) _buildShiftCard(shift)],
                  );
                },
              ),
            ],
          ),
        );
    }
  }

  Widget _buildShiftCard(Manpower shift) {
    return Card(
      child: ListTile(
        title: Text(
          shift.shiftName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${shift.workerCount} workers × ${shift.shiftHours}h × '
              '${shift.outputPerWorkerHour}/worker-hour  ·  '
              '${formatUnits(CapacityService.stationCapacity(shift))}/day',
            ),
            Text(
              _productNames[shift.productId] ?? 'Unknown product',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _openForm(shift: shift),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(shift),
            ),
          ],
        ),
      ),
    );
  }
}
