import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/purchase_order.dart';
import '../../services/mrp_service.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status.dart';
import 'order_form_screen.dart';

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
      await NotificationService.instance.notifyDeliveryReceived(
        factoryId: widget.factoryId,
        materialName: widget.materialName,
        quantity: _order.quantity,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Received ${formatUnits(_order.quantity)} of ${widget.materialName}. Stock updated.',
          ),
        ),
      );
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
      case PurchaseOrderStatus.processing:
        return [
          FilledButton(
            onPressed: _busy
                ? null
                : () => _advanceStatus(PurchaseOrderStatus.shipped),
            child: const Text('Mark shipped'),
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

    final header = Row(
      children: [
        Expanded(
          child: Text(
            widget.materialName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge,
          ),
        ),
        StatusChip(label: _order.status, status: status),
      ],
    );

    final deliveryText = isOpen && _order.expectedDelivery != null ? Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        _relativeDeliveryText(),
        style: theme.textTheme.bodyMedium?.copyWith(color: status.color),
      ),
    ) : const SizedBox.shrink();

    final detailsCard = Card(
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
    );

    final actionsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Actions'),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: _actions(),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(formatPoNumber(_order.poId))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: [
          header,
          deliveryText,
          const SizedBox(height: AppSpacing.l),
          detailsCard,
          const SizedBox(height: AppSpacing.l),
          actionsSection,
        ],
      ),
    );
  }
}
