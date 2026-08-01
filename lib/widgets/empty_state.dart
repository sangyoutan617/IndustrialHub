import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;

  /// Original single-line form. Still fully supported — pass this alone and
  /// the widget renders exactly as it always has.
  final String? message;

  /// Newer title/subtitle form. When [title] is given it takes over as the
  /// heading (bold, titleMedium) and [subtitle] renders as a second line
  /// underneath; [message] is ignored in that case.
  final String? title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.message,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  }) : assert(
         title != null || message != null,
         'EmptyState needs either a title or a message',
       );

  const EmptyState.error({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.actionLabel = 'Retry',
    this.onAction,
  }) : icon = Icons.error_outline,
       title = null,
       subtitle = null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usingTitle = title != null;
    final heading = title ?? message!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: usingTitle
                  ? theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodyMedium,
            ),
            if (usingTitle && subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
