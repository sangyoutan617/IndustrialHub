import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'status.dart';

/// A single KPI number in a compact card: icon badge, muted label, a large
/// prominent value, an optional unit caption, and an optional status pill.
/// Used across dashboards (capacity ceiling, stock days-of-cover, supply
/// risk counts) so every "big number" in the app looks the same.
class KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final AppStatus? status;
  final String? statusLabel;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.status,
    this.statusLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  if (status != null && statusLabel != null)
                    StatusChip(label: statusLabel!, status: status!, dense: true),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              // Wrapped in FittedBox so a large aggregate value (e.g. summed
              // across many factories) shrinks to fit a narrow card instead
              // of overflowing — most values fit as-is and this is a no-op
              // for them.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        unit!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A left-label / right-value row for compact comparisons (capacity
/// machine-vs-labour, supplier comparison stats, order details). Optional
/// trailing [status] pill for rows that also carry a risk/health verdict.
class MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final AppStatus? status;
  final String? statusLabel;

  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.status,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          if (status != null && statusLabel != null) ...[
            const SizedBox(width: AppSpacing.s),
            StatusChip(label: statusLabel!, status: status!, dense: true),
          ],
        ],
      ),
    );
  }
}

/// A section title with optional trailing action — the standard heading
/// used above every list/grid section on a screen ("Machines", "Alerts",
/// "Demand forecast", …).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, AppSpacing.l, 4, AppSpacing.s),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
