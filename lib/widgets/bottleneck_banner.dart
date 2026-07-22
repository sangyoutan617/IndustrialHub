import 'package:flutter/material.dart';
import '../core/theme.dart';
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
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Could not load factory health.'),
                    ),
                    TextButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          );
        }

        final result = snapshot.data!;
        if (!result.hasData) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'No production data yet. Add machines, manpower, materials and demand to see the factory health verdict.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final ok = result.canMeetDemand;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        color: AppColors.primaryDark,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Factory health',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Achievable output / day',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryDark.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${result.achievable.toStringAsFixed(0)} units',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ok
                              ? 'Demand: ${result.requiredPerDay.toStringAsFixed(0)} · meeting demand'
                              : 'Demand: ${result.requiredPerDay.toStringAsFixed(0)} · short by ${result.shortfall!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryDark.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Bottleneck',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _resourceLabel(result.limiter ?? result.bottleneckResource),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          'Machine cap.',
                          result.machineCapacity.toStringAsFixed(0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          'Material cap.',
                          result.materialCeiling?.toStringAsFixed(0) ?? '—',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _resourceLabel(String resource) {
    switch (resource) {
      case 'MACHINE':
        return 'Machine';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return resource;
    }
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
