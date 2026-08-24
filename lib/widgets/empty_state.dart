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

  /// Optional second, less-prominent action (e.g. "Load demo data" next to
  /// a primary "Create factory"). Rendered as an OutlinedButton below the
  /// primary action; [secondaryActionLoading] swaps its label for a spinner.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool secondaryActionLoading;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.message,
    this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.secondaryActionLoading = false,
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
       subtitle = null,
       secondaryActionLabel = null,
       onSecondaryAction = null,
       secondaryActionLoading = false;

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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            Text(
              heading,
              textAlign: TextAlign.center,
              style: usingTitle
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium,
            ),
            if (usingTitle && subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryActionLabel != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onSecondaryAction,
                child: secondaryActionLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
