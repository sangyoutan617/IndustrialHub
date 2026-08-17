import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../models/factory.dart';
import 'bottleneck_service.dart';
import 'mrp_service.dart';
import 'supply_service.dart';

/// Builds a one-page PDF summary of a factory — the bottleneck verdict,
/// capacity breakdown, and supply risk — from figures the deterministic
/// engines already computed. Nothing here recalculates: it reads
/// [BottleneckService] and [SupplyService] and lays their numbers out.
class ReportService {
  final BottleneckService _bottleneckService = BottleneckService();
  final SupplyService _supplyService = SupplyService();

  static const _green = PdfColor.fromInt(0xFF16794F);
  static const _darkGreen = PdfColor.fromInt(0xFF0E4030);
  static const _grey = PdfColor.fromInt(0xFF6B7280);

  Future<Uint8List> buildFactoryReportPdf(Factory factory) async {
    final bottleneck = await _bottleneckService.computeForFactory(
      factory.factoryId,
    );
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
            _factoryHealth(bottleneck),
            pw.SizedBox(height: 18),
            _capacityBreakdown(bottleneck),
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
          'Capacity & supply report · generated ${formatDate(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 11, color: _grey),
        ),
        pw.Divider(color: _green, thickness: 1.5),
      ],
    );
  }

  pw.Widget _factoryHealth(BottleneckResult r) {
    if (!r.hasData) {
      return _section('Factory health', [
        pw.Text(
          'No production data yet — add machines, manpower, materials and '
          'demand to activate the bottleneck engine.',
          style: const pw.TextStyle(fontSize: 11, color: _grey),
        ),
      ]);
    }
    final verdict = r.canMeetDemand
        ? 'Meeting demand'
        : 'Short by ${formatUnits(r.shortfall ?? 0)}/day';
    return _section('Factory health', [
      _row('Achievable output', '${formatUnits(r.achievable)}/day'),
      _row('Demand required', '${formatUnits(r.requiredPerDay)}/day'),
      _row('Verdict', verdict),
      _row('Binding constraint', _limiterLabel(r.limiter)),
    ]);
  }

  pw.Widget _capacityBreakdown(BottleneckResult r) {
    if (!r.hasData) return pw.SizedBox();
    return _section('Capacity breakdown', [
      _row('Machine capacity', '${formatUnits(r.machineCapacity)}/day'),
      _row('Manpower capacity', '${formatUnits(r.manpowerCapacity)}/day'),
      _row(
        'Raw-material ceiling',
        r.materialCeiling != null
            ? '${formatUnits(r.materialCeiling!)}/day'
            : 'not set',
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

    return _section('Supply risk', [
      _row('Raw materials tracked', plans.length.toString()),
      _row('Reorder now', reorderCount.toString()),
      _row('Watch', watchCount.toString()),
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
