import 'package:flutter/material.dart';
import '../services/bottleneck_service.dart';

class BottleneckBanner extends StatefulWidget {
  final int factoryId;

  const BottleneckBanner({super.key, required this.factoryId});

  @override
  State<BottleneckBanner> createState() => _BottleneckBannerState();
}

class _BottleneckBannerState extends State<BottleneckBanner> {
  final _service = BottleneckService();
  late Future<BottleneckResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.computeForFactory(widget.factoryId);
  }

  @override
  void didUpdateWidget(covariant BottleneckBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryId != widget.factoryId) {
      setState(() => _future = _service.computeForFactory(widget.factoryId));
    }
  }

  void _retry() {
    setState(() => _future = _service.computeForFactory(widget.factoryId));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BottleneckResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            margin: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(child: Text('Could not load factory health.')),
                  TextButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final result = snapshot.data!;
        if (!result.hasData) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No production data yet. Add machines, manpower, materials and demand to see the factory health verdict.',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final scheme = Theme.of(context).colorScheme;
        final ok = result.canMeetDemand;

        return Card(
          margin: const EdgeInsets.all(16),
          color: ok ? scheme.primaryContainer : scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ok ? 'Can meet demand' : 'Cannot meet demand',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Achievable: ${result.achievable.toStringAsFixed(0)} units/day',
                ),
                Text(
                  'Required: ${result.requiredPerDay.toStringAsFixed(0)} units/day',
                ),
                if (!ok && result.limiter != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Limiting factor: ${result.limiter} (short by ${result.shortfall!.toStringAsFixed(0)} units/day)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
