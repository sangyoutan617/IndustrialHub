import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../services/mrp_service.dart';

class MaterialProjectionSheet extends StatelessWidget {
  final MaterialPlan plan;

  const MaterialProjectionSheet({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final days = plan.dailyBalances.length > 30
        ? plan.dailyBalances.sublist(0, 30)
        : plan.dailyBalances;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plan.material.materialName} — 30-day projection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < days.length; i++)
                          FlSpot(i.toDouble(), days[i]),
                      ],
                      isCurved: true,
                      dotData: const FlDotData(show: false),
                      color: primaryColor,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: primaryColor.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              plan.stockOutDate != null
                  ? 'Balance is projected to cross zero on '
                        '${formatDate(plan.stockOutDate!)}.'
                  : 'Balance stays positive for the shown window.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}


void showMaterialProjectionSheet(BuildContext context, MaterialPlan plan) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => MaterialProjectionSheet(plan: plan),
  );
}
