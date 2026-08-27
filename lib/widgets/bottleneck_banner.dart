import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../services/bottleneck_service.dart';
import 'status.dart';

class BottleneckBanner extends StatefulWidget {
  final int factoryId;

  /// Outer margin around the card. Defaults to a 16px margin on every side,
  /// matching this widget's original standalone usage — pass
  /// [EdgeInsets.zero] when embedding it as the first item of a list that
  /// already applies its own padding, to avoid doubling up.
  final EdgeInsetsGeometry padding;

  const BottleneckBanner({
    super.key,
    required this.factoryId,
    this.padding = const EdgeInsets.all(16),
  });

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
          return Padding(
            padding: widget.padding,
            child: const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: widget.padding,
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
            padding: widget.padding,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
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
            ),
          );
        }

        final ok = result.canMeetDemand;
        final scheme = Theme.of(context).colorScheme;

        return Padding(
          padding: widget.padding,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Factory health',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusChip(
                        label: ok ? 'Meeting demand' : 'Bottleneck',
                        status: ok ? AppStatus.success : AppStatus.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.l),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Achievable output / day',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatUnits(result.achievable),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ok
                              ? 'Demand: ${formatNumber(result.requiredPerDay)} · meeting demand'
                              : 'Demand: ${formatNumber(result.requiredPerDay)} · short by ${formatNumber(result.shortfall!)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.75,
                            ),
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
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _resourceLabel(
                          result.limiter ?? result.bottleneckResource,
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          scheme,
                          'Machine cap.',
                          formatNumber(result.machineCapacity),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          scheme,
                          'Material cap.',
                          result.materialCeiling != null
                              ? formatNumber(result.materialCeiling!)
                              : '—',
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

  Widget _metricCard(ColorScheme scheme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          // FittedBox so a long space-formatted number (e.g. "40 000")
          // shrinks to fit this cell instead of pinching against its
          // neighbour when the banner sits in a half-width landscape
          // column — same treatment KpiCard already uses for its own
          // big-number display.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
