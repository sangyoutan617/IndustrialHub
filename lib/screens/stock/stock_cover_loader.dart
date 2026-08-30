import '../../models/demand_forecast.dart';
import '../../models/finished_stock.dart';
import '../../services/demand_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/status.dart';

const int lowCoverDaysThreshold = 7;
const int overstockDaysThreshold = 60;

/// Why a product has no demand figure. Distinguishing these is the point:
/// [noForecast] and [zeroPerDay] used to both render as "No demand set",
/// which also happened to be how a demand-forecast row *targeting a
/// different product* looked — so a product about to stock out was
/// indistinguishable from one nobody had forecast yet.
enum DemandGap { noForecast, zeroPerDay }

/// One finished-goods product's days-of-cover read-out — shared by the
/// Stock dashboard's list, the "Critical products" highlight section, and
/// StockProductDetailScreen so all three always agree.
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

  /// Null once there is a real demand figure to divide by.
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
      return 'Low stock — reorder soon';
    }
    if (daysOfCover! > overstockDaysThreshold) return 'Overstocked';
    return 'Healthy';
  }

  // Unified status mapping used by StatusChip everywhere this cover's health
  // is shown: Healthy -> success, low stock -> danger (the urgent one),
  // overstocked -> info (a real semantic info color now exists, so this no
  // longer needs to borrow colorScheme.tertiary), either demand gap ->
  // neutral.
  AppStatus get appStatus {
    if (demandGap != null) return AppStatus.neutral;
    if (daysOfCover! < lowCoverDaysThreshold) return AppStatus.danger;
    if (daysOfCover! > overstockDaysThreshold) return AppStatus.info;
    return AppStatus.success;
  }

  bool get needsAttention =>
      demandGap == null && daysOfCover! < lowCoverDaysThreshold;
}

/// Everything needed to render the Stock dashboard and a single product's
/// detail page — loaded together since days-of-cover depends on matching
/// stock against demand forecasts by product, not on a single stock row in
/// isolation.
class StockOverview {
  final List<ProductCover> covers;
  final List<DemandForecast> forecasts;

  const StockOverview({required this.covers, required this.forecasts});
}

/// Shared by StockDashboardScreen and StockProductDetailScreen so both
/// compute days-of-cover / stock-out projections identically instead of two
/// copies of the same arithmetic drifting apart.
Future<StockOverview> loadStockOverview(int factoryId) async {
  final stockService = StockService();
  final demandService = DemandService();
  final stockList = await stockService.getStockList(factoryId);
  final forecasts = await demandService.getForecasts(factoryId);

  // Days-of-cover reflects only demand in effect today — an expired or
  // future-dated forecast shouldn't count against current stock. The full
  // forecast list is still returned below for the demand-management views.
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
