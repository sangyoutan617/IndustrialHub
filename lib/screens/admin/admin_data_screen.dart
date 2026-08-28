import 'package:flutter/material.dart';
import '../../services/admin_data_service.dart';
import '../../services/seed_service.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

enum _LoadState { loading, error, ready }

class AdminDataScreen extends StatefulWidget {
  const AdminDataScreen({super.key});

  @override
  State<AdminDataScreen> createState() => _AdminDataScreenState();
}

class _AdminDataScreenState extends State<AdminDataScreen> {
  final _adminDataService = AdminDataService();

  _LoadState _state = _LoadState.loading;
  List<TableSimulatedCount> _counts = [];
  bool _isSeeding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final counts = await _adminDataService.countSimulated();
      setState(() {
        _counts = counts;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _runSeed() async {
    setState(() => _isSeeding = true);
    try {
      final result = await _adminDataService.runSeed();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.outcome == SeedOutcome.created
                ? 'Demo data seeded: ${result.factory.factoryName}'
                : 'Demo data already exists: ${result.factory.factoryName}',
          ),
        ),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not run seed. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data & seed management')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load data counts. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final topCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run seed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Creates the demo factory with sample machines, manpower, materials, '
              'suppliers and orders. Safe to press more than once — it checks whether '
              'the demo factory already exists before creating anything.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isSeeding ? null : _runSeed,
              icon: _isSeeding
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.grass_outlined),
              label: const Text('Run seed'),
            ),
          ],
        ),
      ),
    );

    final countsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Simulated data by table',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Read-only. Deleting or resetting demo data is a server-side operation performed '
          'by an operator via SQL, not exposed here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final count in _counts) _buildCountCard(count),
      ],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [topCard, const SizedBox(height: 16), countsSection],
      ),
    );
  }

  Widget _buildCountCard(TableSimulatedCount count) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${count.total} total row${count.total == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusChip(
              label: '${count.simulated} simulated',
              status: AppStatus.info,
              dense: true,
            ),
            const SizedBox(width: 8),
            StatusChip(
              label: '${count.real} real',
              status: AppStatus.success,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}
