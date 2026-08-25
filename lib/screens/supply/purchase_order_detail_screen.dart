import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/purchase_order.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status.dart';
import 'order_form_screen.dart';

/// Formats a purchase order id the same way everywhere it's shown (list,
/// detail, snackbars) — e.g. po_id 42 -> "PO-0042".
String formatPoNumber(int poId) => 'PO-${poId.toString().padLeft(4, '0')}';

/// Decision-focused detail view for one purchase order — every field the
/// list card used to pack into one dense row, plus the status-transition
/// actions that used to live inline in that row. Reuses the exact same
/// OrderService calls and status-transition rules as the list screen; only
/// the presentation moved.
class PurchaseOrderDetailScreen extends StatefulWidget {
  final int factoryId;
  final PurchaseOrder order;
  final String materialName;
  final String supplierName;

  const PurchaseOrderDetailScreen({
    super.key,
    required this.factoryId,
    required this.order,
    required this.materialName,
    required this.supplierName,
  });

  @override
  State<PurchaseOrderDetailScreen> createState() =>
      _PurchaseOrderDetailScreenState();
}

const _openStatuses = [
  PurchaseOrderStatus.pending,
  PurchaseOrderStatus.processing,
  PurchaseOrderStatus.shipped,
];

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  final _orderService = OrderService();
  late PurchaseOrder _order;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  AppStatus _statusFor(String status) {
    switch (status) {
      case PurchaseOrderStatus.pending:
      case PurchaseOrderStatus.processing:
        return AppStatus.info;
      case PurchaseOrderStatus.shipped:
        return AppStatus.warning;
      case PurchaseOrderStatus.delivered:
        return AppStatus.success;
      case PurchaseOrderStatus.cancelled:
        return AppStatus.neutral;
      default:
        return AppStatus.neutral;
    }
  }

  String _relativeDeliveryText() {
    final expected = _order.expectedDelivery;
    if (expected == null) return '';
    final today = DateTime.now();
    final days = DateTime(
      expected.year,
      expected.month,
      expected.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days > 0) return 'Arriving in $days day${days == 1 ? '' : 's'}';
    if (days == 0) return 'Arriving today';
    return 'Overdue by ${-days} day${-days == 1 ? '' : 's'}';
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            OrderFormScreen(factoryId: widget.factoryId, order: _order),
      ),
    );
    if (!mounted || saved != true) return;
    Navigator.of(context).pop(true);
  }

  // Pops back to the list (with a "changed" result) on every successful
  // transition, the same as _receiveDelivery/_deletePermanently/_edit
  // below — a plain back-button tap after a status change would otherwise
  // leave the list showing the pre-change status, since Navigator.pop()
  // from the system back gesture returns null, not true.
  Future<void> _advanceStatus(String newStatus) async {
    setState(() => _busy = true);
    try {
      await _orderService.updateStatus(_order.poId, newStatus);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('supply: failed to update order status: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update order. Please try again.'),
        ),
      );
    }
  }

  Future<void> _receiveDelivery() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Receive delivery?',
      message:
          'This adds ${formatUnits(_order.quantity)} to '
          '${widget.materialName}\'s stock and marks the order Delivered.',
      confirmLabel: 'Receive',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _orderService.receiveDelivery(_order);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('supply: failed to receive delivery: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not receive delivery. Please try again.'),
        ),
      );
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel order?',
      message:
          'This marks the ${widget.materialName} order Cancelled. Stock is '
          'not affected.',
      confirmLabel: 'Cancel order',
    );
    if (!confirmed) return;
    await _advanceStatus(PurchaseOrderStatus.cancelled);
  }

  Future<void> _deletePermanently() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete order permanently?',
      message:
          'This removes the cancelled ${widget.materialName} order from '
          'history for good.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _orderService.deleteOrder(_order.poId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('supply: failed to delete order: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete order. Please try again.'),
        ),
      );
    }
  }

  List<Widget> _actions() {
    switch (_order.status) {
      case PurchaseOrderStatus.pending:
        return [
          FilledButton(
            onPressed: _busy
                ? null
                : () => _advanceStatus(PurchaseOrderStatus.processing),
            child: const Text('Start processing'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _edit,
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel order'),
          ),
        ];
      case PurchaseOrderStatus.processing:
        return [
          FilledButton(
            onPressed: _busy
                ? null
                : () => _advanceStatus(PurchaseOrderStatus.shipped),
            child: const Text('Mark shipped'),
          ),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel order'),
          ),
        ];
      case PurchaseOrderStatus.shipped:
        return [
          FilledButton(
            onPressed: _busy ? null : _receiveDelivery,
            child: const Text('Receive delivery'),
          ),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: const Text('Cancel order'),
          ),
        ];
      case PurchaseOrderStatus.cancelled:
        return [
          OutlinedButton(
            onPressed: _busy ? null : _deletePermanently,
            child: const Text('Delete permanently'),
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusFor(_order.status);
    final isOpen = _openStatuses.contains(_order.status);
    return Scaffold(
      appBar: AppBar(title: Text(formatPoNumber(_order.poId))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.materialName, style: theme.textTheme.titleLarge),
              ),
              StatusChip(label: _order.status, status: status),
            ],
          ),
          if (isOpen && _order.expectedDelivery != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _relativeDeliveryText(),
              style: theme.textTheme.bodyMedium?.copyWith(color: status.color),
            ),
          ],
          const SizedBox(height: AppSpacing.l),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.l,
                vertical: AppSpacing.s,
              ),
              child: Column(
                children: [
                  MetricRow(label: 'PO number', value: formatPoNumber(_order.poId)),
                  MetricRow(label: 'Supplier', value: widget.supplierName),
                  MetricRow(label: 'Material', value: widget.materialName),
                  MetricRow(label: 'Quantity', value: formatUnits(_order.quantity)),
                  if (_order.unitPrice != null) ...[
                    MetricRow(
                      label: 'Unit price',
                      value: formatCurrency(_order.unitPrice!),
                    ),
                    MetricRow(
                      label: 'Order total',
                      value: formatCurrency(MrpService.orderTotal(_order)!),
                    ),
                  ],
                  MetricRow(label: 'Order date', value: formatDate(_order.orderDate)),
                  MetricRow(
                    label: 'Expected delivery',
                    value: _order.expectedDelivery != null
                        ? formatDate(_order.expectedDelivery!)
                        : 'Not set',
                  ),
                  if (_order.deliveredAt != null)
                    MetricRow(
                      label: 'Delivered on',
                      value: formatDate(_order.deliveredAt!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          const SectionHeader(title: 'Actions'),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: _actions(),
          ),
        ],
      ),
    );
  }
}
