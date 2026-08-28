import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/loading_indicator.dart';

/// Side-by-side comparison of every supplier available for one material —
/// quoted vs effective lead time, reliability, and on-time delivery rate —
/// so choosing between suppliers doesn't rely on quoted lead time alone.
class SupplierComparisonScreen extends StatefulWidget {
  final int factoryId;
  final int materialId;
  final String materialName;

  const SupplierComparisonScreen({
    super.key,
    required this.factoryId,
    required this.materialId,
    required this.materialName,
  });

  @override
  State<SupplierComparisonScreen> createState() =>
      _SupplierComparisonScreenState();
}

enum _LoadState { loading, error, ready }

class _SupplierComparisonScreenState extends State<SupplierComparisonScreen> {
  final _supplierService = SupplierService();
  final _orderService = OrderService();

  _LoadState _state = _LoadState.loading;
  List<SupplierComparison> _comparisons = [];
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _state = _LoadState.loading);
    try {
      final suppliers = await _supplierService.getSuppliersForMaterials([
        widget.materialId,
      ]);
      final orders = await _orderService.getOrdersForMaterials([
        widget.materialId,
      ]);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _comparisons = MrpService.compareSuppliers(
          suppliersForMaterial: suppliers,
          historyForMaterial: orders,
        );
        _state = _LoadState.ready;
      });
    } catch (e) {
      debugPrint('supply: failed to load supplier comparison: $e');
      if (!mounted || token != _loadToken) return;
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Compare suppliers — ${widget.materialName}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        if (_comparisons.isEmpty) {
          return const EmptyState(
            icon: Icons.local_shipping_outlined,
            message: 'No suppliers linked to this material yet.',
          );
        }
        
        final cards = _comparisons.map((c) => _buildCard(c)).toList();

        return ListView(padding: const EdgeInsets.all(16), children: cards);
    }
  }

  Widget _buildCard(SupplierComparison c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: c.isRecommended
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.supplier.supplierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (c.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Recommended',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            MetricRow(
              label: 'Quoted lead time',
              value: '${c.quotedLeadDays} days',
            ),
            MetricRow(
              label: 'Effective lead time',
              value: '${c.effectiveLeadDays} days',
            ),
            MetricRow(
              label: 'Reliability rating',
              value: '${c.reliabilityRating.toStringAsFixed(1)}★',
            ),
            MetricRow(
              label: 'On-time rate',
              value: c.onTimeRate != null
                  ? '${(c.onTimeRate! * 100).round()}% (${c.historyCount} delivered)'
                  : 'Not enough history (${c.historyCount} delivered)',
            ),
            MetricRow(
              label: 'Last unit price',
              value: c.unitPrice != null
                  ? formatCurrency(c.unitPrice!)
                  : 'No price history',
            ),
            if (c.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                c.reason,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
