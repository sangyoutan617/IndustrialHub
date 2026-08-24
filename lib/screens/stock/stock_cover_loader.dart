import '../../models/demand_forecast.dart';
import '../../models/finished_stock.dart';
import '../../services/demand_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/status.dart';

const int lowCoverDaysThreshold = 7;
const int overstockDaysThreshold = 60;

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

  String get status {
    if (requiredPerDay == null || requiredPerDay == 0) return 'No demand set';
    if (daysOfCover! < lowCoverDaysThreshold) {
      return 'Low stock — reorder soon';
    }
    if (daysOfCover! > overstockDaysThreshold) return 'Overstocked';
    return 'Healthy';
  }

  // Unified status mapping used by StatusChip everywhere this cover's health
  // is shown: Healthy -> success, low stock -> danger (the urgent one),
  // overstocked -> info (a real semantic info color now exists, so this no
  // longer needs to borrow colorScheme.tertiary), no demand set -> neutral.
  AppStatus get appStatus {
    if (requiredPerDay == null || requiredPerDay == 0) return AppStatus.neutral;
    if (daysOfCover! < lowCoverDaysThreshold) return AppStatus.danger;
    if (daysOfCover! > overstockDaysThreshold) return AppStatus.info;
    return AppStatus.success;
  }

  bool get needsAttention =>
      requiredPerDay != null &&
      requiredPerDay! > 0 &&
      daysOfCover != null &&
      daysOfCover! < lowCoverDaysThreshold;
}

/// Everything needed to render the Stock dashboard and a single product's
/// detail page — loaded together since days-of-cover depends on matching
/// stock against demand forecasts by product name, not on a single stock
/// row in isolation.
class StockOverview {
  final List<ProductCover> covers;
  final List<DemandForecast> forecasts;

  const StockOverview({required this.covers, required this.forecasts});
}

/// Shared by StockDashboardScreen and StockProductDetailScreen so both
/// compute days-of-cover / stock-out projections identically instead of two
/// copies of the same arithmetic drifting apart. Nothing here is new logic —
/// this is the exact computation StockDashboardScreen._load() already did,
/// pulled out so a single product's detail page can reuse it without
/// depending on the dashboard screen having already loaded.
Future<StockOverview> loadStockOverview(int factoryId) async {
  final stockService = StockService();
  final demandService = DemandService();
  final stockList = await stockService.getStockList(factoryId);
  final forecasts = await demandService.getForecasts(factoryId);

  final requiredByName = <String, int>{};
  for (final forecast in forecasts) {
    final key = forecast.productName.trim().toLowerCase();
    requiredByName[key] = (requiredByName[key] ?? 0) + forecast.requiredPerDay;
  }

  final covers = stockList.map((stock) {
    final required = requiredByName[stock.productName.trim().toLowerCase()];
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
