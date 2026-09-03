import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'status.dart';

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

class MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final AppStatus? status;
  final String? statusLabel;

  /// When true, always reserves a fixed-width trailing slot for the status
  /// badge — even on rows with no badge — so the value column lines up
  /// across every row in the same card regardless of which rows have one.
  final bool reserveBadgeSpace;

  static const double _badgeSlotWidth = 92;

  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.status,
    this.statusLabel,
    this.reserveBadgeSpace = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final badge = (status != null && statusLabel != null)
        ? StatusChip(label: statusLabel!, status: status!, dense: true)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (reserveBadgeSpace) ...[
            const SizedBox(width: AppSpacing.s),
            SizedBox(
              width: _badgeSlotWidth,
              child: badge == null
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: badge,
                      ),
                    ),
            ),
          ] else if (badge != null) ...[
            const SizedBox(width: AppSpacing.s),
            badge,
          ],
        ],
      ),
    );
  }
}

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
