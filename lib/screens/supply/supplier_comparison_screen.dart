import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/mrp_service.dart';
import '../../services/order_service.dart';
import '../../services/supplier_service.dart';
import '../../widgets/empty_state.dart';
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
      appBar: AppBar(title: Text('Compare suppliers — ${widget.materialName}')),
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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [for (final c in _comparisons) _buildCard(c)],
        );
    }
  }

  Widget _buildCard(SupplierComparison c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: c.isRecommended
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.primary, width: 2),
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
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Recommended',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _statRow('Quoted lead time', '${c.quotedLeadDays} days'),
            _statRow('Effective lead time', '${c.effectiveLeadDays} days'),
            _statRow(
              'Reliability rating',
              '${c.reliabilityRating.toStringAsFixed(1)}★',
            ),
            _statRow(
              'On-time rate',
              c.onTimeRate != null
                  ? '${(c.onTimeRate! * 100).round()}% (${c.historyCount} delivered)'
                  : 'Not enough history (${c.historyCount} delivered)',
            ),
            if (c.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                c.reason,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
