import '../../models/demand_forecast.dart';
import '../../models/finished_stock.dart';
import '../../services/demand_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/status.dart';

const int lowCoverDaysThreshold = 7;
const int overstockDaysThreshold = 60;

enum DemandGap { noForecast, zeroPerDay }

class ProductCover {
  final FinishedStock stock;
  final int? requiredPerDay;
  final double? daysOfCover;
  final DateTime? stockOutDate;

  ProductCover({
    required this.stock,
    this.requiredPerDay,
    this.daysOfCover,
    this.stockOutDate,
  });

  DemandGap? get demandGap {
    if (requiredPerDay == null) return DemandGap.noForecast;
    if (requiredPerDay == 0) return DemandGap.zeroPerDay;
    return null;
  }

  String get status {
    switch (demandGap) {
      case DemandGap.noForecast:
        return 'No demand set';
      case DemandGap.zeroPerDay:
        return 'Demand set to 0/day';
      case null:
        break;
    }
    if (daysOfCover! < lowCoverDaysThreshold) {
      return 'Low stock';
    }
    if (daysOfCover! > overstockDaysThreshold) return 'Overstocked';
    return 'Healthy';
  }

  AppStatus get appStatus {
    if (demandGap != null) return AppStatus.neutral;
    if (daysOfCover! < lowCoverDaysThreshold) return AppStatus.danger;
    if (daysOfCover! > overstockDaysThreshold) return AppStatus.info;
    return AppStatus.success;
  }

  bool get needsAttention =>
      demandGap == null && daysOfCover! < lowCoverDaysThreshold;
}

class StockOverview {
  final List<ProductCover> covers;
  final List<DemandForecast> forecasts;

  const StockOverview({required this.covers, required this.forecasts});
}

Future<StockOverview> loadStockOverview(int factoryId) async {
  final stockService = StockService();
  final demandService = DemandService();
  final stockList = await stockService.getStockList(factoryId);
  final forecasts = await demandService.getForecasts(factoryId);

  final activeForecasts = DemandForecast.activeOn(forecasts, DateTime.now());
  final requiredByProduct = <int, int>{};
  for (final forecast in activeForecasts) {
    requiredByProduct[forecast.productId] =
        (requiredByProduct[forecast.productId] ?? 0) + forecast.requiredPerDay;
  }

  final covers = stockList.map((stock) {
    final required = requiredByProduct[stock.productId];
    final daysOfCover = (required != null && required > 0)
        ? stock.currentQuantity / required
        : null;
    final stockOutDate = daysOfCover != null
        ? DateTime.now().add(Duration(days: daysOfCover.floor()))
        : null;
    return ProductCover(
      stock: stock,
      requiredPerDay: required,
      daysOfCover: daysOfCover,
      stockOutDate: stockOutDate,
    );
  }).toList();

  return StockOverview(covers: covers, forecasts: forecasts);
}
