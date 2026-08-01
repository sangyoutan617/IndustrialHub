import 'package:flutter/material.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'loading_indicator.dart';

enum AsyncViewStatus { loading, error, empty, data }

/// Wraps the loading/error/empty/data branching every list screen repeats,
/// so a screen only has to describe *what* each state looks like, not the
/// branching itself.
class AsyncListView<T> extends StatelessWidget {
  final AsyncViewStatus status;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;

  final String? loadingMessage;

  final String errorMessage;
  final VoidCallback onRetry;

  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  /// When set, the data state is wrapped in a [RefreshIndicator].
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;

  const AsyncListView({
    super.key,
    required this.status,
    required this.items,
    required this.itemBuilder,
    required this.errorMessage,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptySubtitle,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.loadingMessage,
    this.onRefresh,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case AsyncViewStatus.loading:
        return LoadingIndicator(message: loadingMessage);
      case AsyncViewStatus.error:
        return ErrorState(message: errorMessage, onRetry: onRetry);
      case AsyncViewStatus.empty:
        return EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          subtitle: emptySubtitle,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
        );
      case AsyncViewStatus.data:
        final list = ListView.builder(
          padding: padding,
          itemCount: items.length,
          itemBuilder: (context, index) => itemBuilder(context, items[index]),
        );
        if (onRefresh == null) return list;
        return RefreshIndicator(onRefresh: onRefresh!, child: list);
    }
  }
}
