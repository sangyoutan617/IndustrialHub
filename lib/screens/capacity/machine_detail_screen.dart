import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/machine.dart';
import '../../models/machine_downtime_log.dart';
import '../../services/capacity_service.dart';
import '../../services/machine_downtime_service.dart';
import '../../services/machine_service.dart';
import '../../services/product_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

class MachineDetailScreen extends StatefulWidget {
  final int factoryId;
  final int machineId;

  const MachineDetailScreen({
    super.key,
    required this.factoryId,
    required this.machineId,
  });

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

enum _LoadState { loading, error, notFound, ready }

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  final _machineService = MachineService();
  final _productService = ProductService();
  final _downtimeService = MachineDowntimeService();

  _LoadState _state = _LoadState.loading;
  Machine? _machine;
  String? _productName;
  List<MachineDowntimeLog> _log = [];
  bool _acting = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final machines = await _machineService.getMachines(widget.factoryId);
      Machine? machine;
      for (final m in machines) {
        if (m.machineId == widget.machineId) {
          machine = m;
          break;
        }
      }
      if (!mounted || token != _loadToken) return;
      if (machine == null) {
        setState(() => _state = _LoadState.notFound);
        return;
      }

      String? productName;
      List<MachineDowntimeLog> log = const [];
      try {
        final products = await _productService.getProducts(widget.factoryId);
        productName = products
            .firstWhere(
              (p) => p.productId == machine!.productId,
              orElse: () => products.first,
            )
            .productName;
      } catch (_) {}
      try {
        log = await _downtimeService.getLog(widget.machineId);
      } catch (_) {}

      if (!mounted || token != _loadToken) return;
      setState(() {
        _machine = machine;
        _productName = productName;
        _log = log;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _logDowntime() async {
    final machine = _machine!;
    final result = await _downtimeDialog(
      title: 'Log downtime',
      confirmLabel: 'Log',
      unitCount: machine.unitCount,
    );
    if (result == null) return;

    setState(() => _acting = true);
    try {
      await _downtimeService.logDowntime(
        machineId: machine.machineId,
        factoryId: widget.factoryId,
        hours: result.hours,
        machinesDown: result.machinesDown,
        unitCount: machine.unitCount,
        reason: result.reason,
        date: DateTime.now(),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downtime logged')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not log downtime. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _editDowntime(MachineDowntimeLog entry) async {
    final machine = _machine!;
    final result = await _downtimeDialog(
      title: 'Edit downtime',
      confirmLabel: 'Save',
      unitCount: machine.unitCount,
      initialHours: entry.downtimeHours,
      initialMachinesDown: entry.machinesDown,
      initialReason: entry.reason,
    );
    if (result == null) return;

    setState(() => _acting = true);
    try {
      await _downtimeService.updateDowntimeLog(
        logId: entry.logId,
        factoryId: widget.factoryId,
        hours: result.hours,
        machinesDown: result.machinesDown,
        reason: result.reason,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downtime updated')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update this entry. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<({double hours, int machinesDown, String? reason})?> _downtimeDialog({
    required String title,
    required String confirmLabel,
    required int unitCount,
    double? initialHours,
    int? initialMachinesDown,
    String? initialReason,
  }) async {
    final hoursController = TextEditingController(
      text: initialHours == null ? '' : formatNumber(initialHours),
    );
    final machinesDownController = TextEditingController(
      text: (initialMachinesDown ?? 1).toString(),
    );
    final reasonController = TextEditingController(text: initialReason ?? '');
    final formKey = GlobalKey<FormState>();
    final isGroup = unitCount > 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: hoursController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Hours down'),
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a positive number of hours';
                    }
                    return null;
                  },
                ),
                if (isGroup) ...[
                  const SizedBox(height: AppSpacing.m),
                  TextFormField(
                    controller: machinesDownController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Machines down',
                      helperText: 'Out of $unitCount in this group',
                    ),
                    validator: (v) {
                      final parsed = int.tryParse((v ?? '').trim());
                      if (parsed == null || parsed < 1) {
                        return 'Enter a whole number of 1 or more';
                      }
                      if (parsed > unitCount) {
                        return 'This group only has $unitCount machines';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.m),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;

    final reason = reasonController.text.trim();
    return (
      hours: double.parse(hoursController.text.trim()),
      machinesDown: isGroup ? int.parse(machinesDownController.text.trim()) : 1,
      reason: reason.isEmpty ? null : reason,
    );
  }

  Future<void> _startRepair() => _runAction(
    () => _downtimeService.startRepair(_machine!.machineId, widget.factoryId),
    'Repair started',
    'Could not update this machine. Please try again.',
  );

  Future<void> _markRepaired() => _runAction(
    () => _downtimeService.markRepaired(_machine!.machineId, widget.factoryId),
    'Machine back to Active',
    'Could not update this machine. Please try again.',
  );

  Future<void> _markMaintained() => _runAction(
    () => _downtimeService.setStatus(
      _machine!.machineId,
      widget.factoryId,
      MachineStatus.active,
    ),
    'Machine back to Active',
    'Could not update this machine. Please try again.',
  );

  Future<void> _selectStatus() async {
    final machine = _machine!;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.build_circle_outlined),
              title: const Text('Under Maintenance'),
              onTap: () =>
                  Navigator.pop(context, MachineStatus.underMaintenance),
            ),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: const Text('Downtime'),
              onTap: () => Navigator.pop(context, MachineStatus.downtime),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    if (machine.isGroup) {
      if (!mounted) return;
      final label = selected == MachineStatus.downtime
          ? 'Downtime'
          : 'Under Maintenance';
      final confirmed = await showConfirmDialog(
        context,
        title: 'Take all ${machine.unitCount} units offline?',
        message:
            '"${machine.machineName}" is a group of ${machine.unitCount} '
            'machines sharing one status. Marking it $label takes the whole '
            'group offline — its capacity drops to zero, not a share of it '
            '— until it\'s marked repaired or maintained again.',
        confirmLabel: 'Mark $label',
        isDestructive: false,
      );
      if (!confirmed) return;
    }

    await _runAction(
      () => _downtimeService.setStatus(
        machine.machineId,
        widget.factoryId,
        selected,
      ),
      'Status updated',
      'Could not update this machine. Please try again.',
    );
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
    String failureMessage,
  ) async {
    setState(() => _acting = true);
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Machine')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load this machine. Please try again.',
          onRetry: _load,
        );
      case _LoadState.notFound:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('This machine no longer exists.')),
        );
      case _LoadState.ready:
        return _buildReady(_machine!);
    }
  }

  Widget _buildReady(Machine machine) {
    final theme = Theme.of(context);
    final contribution = machine.isActive
        ? CapacityService.computeMachineCapacity([machine])
        : 0.0;
    final (statusStatus, statusLabel) = _statusStyle(machine.status);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  machine.machineName,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              StatusChip(label: statusLabel, status: statusStatus),
            ],
          ),
          if (_productName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _productName!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.l),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.l,
                vertical: AppSpacing.s,
              ),
              child: Column(
                children: [
                  MetricRow(
                    label: 'Rated output',
                    value: '${formatNumber(machine.ratedOutputPerHour)}/hour',
                  ),
                  MetricRow(
                    label: 'Operating hours',
                    value: '${formatNumber(machine.operatingHoursPerDay)}/day',
                  ),
                  if (machine.isGroup)
                    MetricRow(
                      label: 'Machines in group',
                      value: '${machine.unitCount}',
                    ),
                  if (machine.stageLabel != null)
                    MetricRow(label: 'Stage', value: machine.stageLabel!),
                  MetricRow(
                    label: 'Capacity contribution',
                    value: machine.isActive
                        ? '${formatUnits(contribution)}/day'
                        : 'Excluded (${machine.status})',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          _actionSection(machine),
          if (_openPartialUnitsDown(machine) > 0) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              '${_openPartialUnitsDown(machine)} of ${machine.unitCount} '
              'units currently down — the group still counts toward capacity.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SectionHeader(title: 'Downtime log'),
          if (_log.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Text(
                'No downtime logged for this machine yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [for (final entry in _log) _logTile(entry, theme)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionSection(Machine machine) {
    if (machine.isActive) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _acting ? null : _selectStatus,
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Select status'),
        ),
      );
    }

    final Widget primary;
    if (machine.isUnderMaintenance) {
      primary = FilledButton.icon(
        onPressed: _acting ? null : _markMaintained,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Mark maintained'),
      );
    } else if (machine.isDowntime) {
      primary = FilledButton.icon(
        onPressed: _acting ? null : _startRepair,
        icon: const Icon(Icons.build_outlined, size: 18),
        label: const Text('Start repair'),
      );
    } else {
      primary = FilledButton.icon(
        onPressed: _acting ? null : _markRepaired,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Mark repaired'),
      );
    }

    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        primary,
        OutlinedButton.icon(
          onPressed: _acting ? null : _logDowntime,
          icon: const Icon(Icons.report_problem_outlined, size: 18),
          label: const Text('Log downtime'),
        ),
      ],
    );
  }

  int _openPartialUnitsDown(Machine machine) {
    if (!machine.isGroup || !machine.isActive) return 0;
    return _log
        .where((e) => !e.resolved)
        .fold<int>(0, (sum, e) => sum + e.machinesDown);
  }

  Widget _logTile(MachineDowntimeLog entry, ThemeData theme) {
    final machine = _machine!;
    final unitsSuffix = machine.isGroup || entry.machinesDown > 1
        ? ' · ${entry.machinesDown} '
              '${entry.machinesDown == 1 ? 'unit' : 'units'}'
        : '';
    return ListTile(
      dense: true,
      title: Text(
        entry.reason?.isNotEmpty == true ? entry.reason! : 'Downtime',
      ),
      subtitle: Text(
        '${formatDate(entry.logDate)} · '
        '${formatNumber(entry.downtimeHours)}h$unitsSuffix',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            label: entry.resolved ? 'Repaired' : 'Open',
            status: entry.resolved ? AppStatus.success : AppStatus.danger,
            dense: true,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit entry',
            onPressed: _acting ? null : () => _editDowntime(entry),
          ),
        ],
      ),
    );
  }

  (AppStatus, String) _statusStyle(String status) {
    return switch (status) {
      MachineStatus.active => (AppStatus.success, 'Active'),
      MachineStatus.underMaintenance => (
        AppStatus.warning,
        'Under Maintenance',
      ),
      MachineStatus.downtime => (AppStatus.danger, 'Downtime'),
      MachineStatus.repair => (AppStatus.warning, 'Repair'),
      _ => (AppStatus.neutral, status),
    };
  }
}
