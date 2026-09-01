import 'package:flutter/material.dart';
import '../core/theme.dart';

enum AppStatus { success, warning, danger, info, neutral }

extension AppStatusStyle on AppStatus {
  Color get color => switch (this) {
    AppStatus.success => AppColors.success,
    AppStatus.warning => AppColors.warning,
    AppStatus.danger => AppColors.danger,
    AppStatus.info => AppColors.info,
    AppStatus.neutral => AppColors.neutral700,
  };

  Color get background => switch (this) {
    AppStatus.success => AppColors.successLight,
    AppStatus.warning => AppColors.warningLight,
    AppStatus.danger => AppColors.dangerLight,
    AppStatus.info => AppColors.infoLight,
    AppStatus.neutral => AppColors.neutral100,
  };

  IconData get icon => switch (this) {
    AppStatus.success => Icons.check_circle_rounded,
    AppStatus.warning => Icons.warning_rounded,
    AppStatus.danger => Icons.error_rounded,
    AppStatus.info => Icons.info_rounded,
    AppStatus.neutral => Icons.circle,
  };
}

class StatusChip extends StatelessWidget {
  final String label;
  final AppStatus status;
  final bool dense;

  const StatusChip({
    super.key,
    required this.label,
    required this.status,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: dense ? 12 : 14, color: status.color),
          SizedBox(width: dense ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              color: status.color,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String message;
  final String? title;
  final AppStatus status;
  final String? actionLabel;
  final VoidCallback? onAction;

  const InfoBanner({
    super.key,
    required this.message,
    this.title,
    this.status = AppStatus.info,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: status.color, size: 20),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: status.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.color,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.s),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: status.color,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
