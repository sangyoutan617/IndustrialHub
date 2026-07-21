import 'package:flutter/material.dart';
import '../../models/manpower.dart';
import '../../services/capacity_service.dart';
import '../../services/manpower_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
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
  _LoadState _state = _LoadState.loading;
  List<Manpower> _shifts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final shifts = await _service.getShifts(widget.factoryId);
      setState(() {
        _shifts = shifts;
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
    if (saved == true) _load();
  }

  Future<void> _delete(Manpower shift) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove shift?',
      message:
          'This removes "${shift.shiftName}" permanently. This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      await _service.deleteShift(shift.manpowerId);
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete shift. Please try again.'),
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
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        if (_shifts.isEmpty) {
          return EmptyState(
            icon: Icons.groups_outlined,
            message:
                'No shifts yet. Add one to start tracking labour capacity.',
            actionLabel: 'Add shift',
            onAction: () => _openForm(),
          );
        }
        final totalCapacity = CapacityService.computeManpowerCapacity(_shifts);
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.groups),
                      const SizedBox(width: 12),
                      Text(
                        'Total labour capacity: ${totalCapacity.toStringAsFixed(1)} units/day',
                      ),
                    ],
                  ),
                ),
              ),
              for (final shift in _shifts)
                Card(
                  child: ListTile(
                    title: Text(shift.shiftName),
                    subtitle: Text(
                      '${shift.workerCount} workers × ${shift.shiftHours}h × '
                      '${shift.outputPerWorkerHour}/worker-hour',
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
                ),
            ],
          ),
        );
    }
  }
}
