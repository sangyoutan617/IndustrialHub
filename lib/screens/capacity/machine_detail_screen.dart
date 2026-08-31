import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/machine.dart';
import '../../models/machine_downtime_log.dart';
import '../../services/capacity_service.dart';
import '../../services/machine_downtime_service.dart';
import '../../services/machine_service.dart';
import '../../services/product_service.dart';
import '../../widgets/error_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

/// One machine's own page: its capacity contribution, current status, and
/// the Active → Downtime → Repair → Active workflow — the guided path for
/// logging a breakdown through to repair. Reached by tapping a machine on
/// [MachineListScreen]; editing the raw fields still happens on
/// [MachineFormScreen] via the app bar action.
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
      } catch (_) {
        // Nice-to-have — don't block the page on it.
      }
      try {
        log = await _downtimeService.getLog(widget.machineId);
      } catch (_) {
        // Same — the page is still useful without history.
      }

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
    final hoursController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log downtime'),
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
            child: const Text('Log'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acting = true);
    try {
      await _downtimeService.logDowntime(
        machineId: machine.machineId,
        factoryId: widget.factoryId,
        hours: double.parse(hoursController.text.trim()),
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
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
        const SnackBar(content: Text('Could not log downtime. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    final Widget button;
    if (machine.isDowntime) {
      button = FilledButton.icon(
        onPressed: _acting ? null : _startRepair,
        icon: const Icon(Icons.build_outlined, size: 18),
        label: const Text('Start repair'),
      );
    } else if (machine.isRepair) {
      button = FilledButton.icon(
        onPressed: _acting ? null : _markRepaired,
        icon: const Icon(Icons.check_circle_outline, size: 18),
        label: const Text('Mark repaired'),
      );
    } else {
      button = OutlinedButton.icon(
        onPressed: _acting ? null : _logDowntime,
        icon: const Icon(Icons.report_problem_outlined, size: 18),
        label: const Text('Log downtime'),
      );
    }
    return Align(alignment: Alignment.centerLeft, child: button);
  }

  Widget _logTile(MachineDowntimeLog entry, ThemeData theme) {
    return ListTile(
      dense: true,
      title: Text(
        entry.reason?.isNotEmpty == true ? entry.reason! : 'Downtime',
      ),
      subtitle: Text(
        '${formatDate(entry.logDate)} · ${formatNumber(entry.downtimeHours)}h',
      ),
      trailing: StatusChip(
        label: entry.resolved ? 'Repaired' : 'Open',
        status: entry.resolved ? AppStatus.success : AppStatus.danger,
        dense: true,
      ),
    );
  }

  (AppStatus, String) _statusStyle(String status) {
    return switch (status) {
      MachineStatus.active => (AppStatus.success, 'Active'),
      MachineStatus.underMaintenance => (AppStatus.warning, 'Under Maintenance'),
      MachineStatus.downtime => (AppStatus.danger, 'Downtime'),
      MachineStatus.repair => (AppStatus.warning, 'Repair'),
      _ => (AppStatus.neutral, status),
    };
  }
}
