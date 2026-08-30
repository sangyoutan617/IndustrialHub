import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../models/factory.dart';
import '../screens/stock/stock_cover_loader.dart';
import 'bottleneck_service.dart';
import 'mrp_service.dart';
import 'product_service.dart';
import 'supply_service.dart';

/// Builds a one-page PDF summary of a factory — the per-product bottleneck
/// verdict, finished-goods stock, and supply risk — from figures the
/// deterministic engines already computed. Nothing here recalculates: it
/// reads [BottleneckService] (once per product), [loadStockOverview] and
/// [SupplyService] and lays their numbers out. Loops every product rather
/// than offering a picker — a PDF read offline later doesn't benefit from
/// one, unlike the live capacity dashboard.
class ReportService {
  final BottleneckService _bottleneckService = BottleneckService();
  final SupplyService _supplyService = SupplyService();
  final ProductService _productService = ProductService();

  // Matches the app's teal brand (lib/core/theme.dart AppColors).
  static const _green = PdfColor.fromInt(0xFF0F766E);
  static const _darkGreen = PdfColor.fromInt(0xFF115E59);
  static const _grey = PdfColor.fromInt(0xFF6B7280);

  Future<Uint8List> buildFactoryReportPdf(Factory factory) async {
    final products = await _productService.getProducts(factory.factoryId);
    final bottlenecks = await Future.wait(
      products.map(
        (p) => _bottleneckService.computeForProduct(
          factory.factoryId,
          p.productId,
        ),
      ),
    );
    final productBottlenecks = [
      for (var i = 0; i < products.length; i++)
        ProductBottleneck(product: products[i], bottleneck: bottlenecks[i]),
    ];
    final stock = await loadStockOverview(factory.factoryId);
    final supply = await _supplyService.load(factory.factoryId);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(factory),
            pw.SizedBox(height: 20),
            _capacitySection(productBottlenecks),
            pw.SizedBox(height: 18),
            _stockOverview(stock),
            pw.SizedBox(height: 18),
            _supplyRisk(supply),
            pw.Spacer(),
            _footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _header(Factory factory) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          factory.factoryName,
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: _darkGreen,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Capacity, stock & supply report · generated ${formatDate(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 11, color: _grey),
        ),
        pw.Divider(color: _green, thickness: 1.5),
      ],
    );
  }

  /// One line per product rather than a single factory-wide verdict —
  /// achievable/demand can be in different units from one product to the
  /// next, so "X of Y products meeting demand" is the summary figure that
  /// stays meaningful, same as the admin cross-factory rollup.
  pw.Widget _capacitySection(List<ProductBottleneck> productBottlenecks) {
    if (productBottlenecks.isEmpty) {
      return _section('Capacity', [
        pw.Text(
          'No products configured for this factory.',
          style: const pw.TextStyle(fontSize: 11, color: _grey),
        ),
      ]);
    }
    final withData = productBottlenecks.where((p) => p.bottleneck.hasData);
    final meetingDemand = withData
        .where((p) => p.bottleneck.canMeetDemand)
        .length;

    final rows = <pw.Widget>[
      _row(
        'Products meeting demand',
        '$meetingDemand of ${withData.length}'
            '${productBottlenecks.length != withData.length ? ' (${productBottlenecks.length - withData.length} with no production data yet)' : ''}',
      ),
      pw.SizedBox(height: 4),
    ];
    for (final pb in productBottlenecks) {
      final r = pb.bottleneck;
      if (!r.hasData) {
        rows.add(_row(pb.product.productName, 'No production data yet'));
        continue;
      }
      final verdict = r.canMeetDemand
          ? '${formatUnits(r.achievable)}/day achievable vs '
                '${formatUnits(r.requiredPerDay)}/day required — meeting demand'
          : 'Short by ${formatUnits(r.shortfall ?? 0)}/day '
                '(${_limiterLabel(r.limiter)} limited)';
      rows.add(_row(pb.product.productName, verdict));
    }
    return _section('Capacity — by product', rows);
  }

  pw.Widget _stockOverview(StockOverview stock) {
    final withCover = stock.covers.where((c) => c.daysOfCover != null).toList()
      ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!));
    final lowStock = withCover
        .where((c) => c.daysOfCover! < lowCoverDaysThreshold)
        .length;
    final overstocked = withCover
        .where((c) => c.daysOfCover! > overstockDaysThreshold)
        .length;

    return _section('Finished-goods stock', [
      _row('Products tracked', stock.covers.length.toString()),
      _row('Low stock (reorder soon)', lowStock.toString()),
      _row('Overstocked', overstocked.toString()),
      if (withCover.isNotEmpty)
        _row(
          'Closest to stock-out',
          '${withCover.first.stock.productName}'
              '${withCover.first.stockOutDate != null ? ' — predicted ${formatDate(withCover.first.stockOutDate!)}' : ''}',
        ),
    ]);
  }

  pw.Widget _supplyRisk(SupplyOverview supply) {
    final plans = supply.plans;
    bool isReorder(MaterialPlan p) =>
        p.risk == SupplyRisk.reorderNow || p.risk == SupplyRisk.stockedOut;
    final reorderCount = plans.where(isReorder).length;
    final watchCount = plans
        .where(
          (p) =>
              !isReorder(p) &&
              (p.risk == SupplyRisk.watch || p.belowReorderLevel),
        )
        .length;

    final attention = plans.where((p) => p.needsAttention).toList()
      ..sort((a, b) {
        final ad = a.orderByDate;
        final bd = b.orderByDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    final inventoryValue = MrpService.inventoryValue(supply.materials);

    return _section('Supply risk', [
      _row('Raw materials tracked', plans.length.toString()),
      _row('Reorder now', reorderCount.toString()),
      _row('Watch', watchCount.toString()),
      if (inventoryValue > 0)
        _row('Inventory value', formatCurrency(inventoryValue)),
      if (attention.isNotEmpty)
        _row(
          'Most urgent',
          '${attention.first.material.materialName}'
              '${attention.first.orderByDate != null ? ' — order by ${formatDate(attention.first.orderByDate!)}' : ''}',
        ),
    ]);
  }

  pw.Widget _section(String title, List<pw.Widget> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _green,
            letterSpacing: 0.8,
          ),
        ),
        pw.SizedBox(height: 6),
        ...rows,
      ],
    );
  }

  pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 11, color: _grey),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _darkGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer() {
    return pw.Text(
      'Industrial Hub — Malaysia Industrial Hub Innovation Platform. '
      'Benchmarks from DOSM open data (data.gov.my).',
      style: const pw.TextStyle(fontSize: 8, color: _grey),
    );
  }

  String _limiterLabel(String? limiter) {
    switch (limiter) {
      case 'MACHINE':
        return 'Machines';
      case 'MANPOWER':
        return 'Manpower';
      case 'RAW MATERIAL':
        return 'Raw material';
      default:
        return 'None';
    }
  }
}
