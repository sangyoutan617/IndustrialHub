import '../../core/product_name_matching.dart';
import '../../models/demand_forecast.dart';
import '../../models/finished_stock.dart';
import '../../services/demand_service.dart';
import '../../services/stock_service.dart';
import '../../widgets/status.dart';

// Re-exported so existing importers of this file (demand_form_screen.dart,
// tests) keep working unchanged — normaliseProductName is also now used by
// SupplyService, which can't depend on a screens/ file, hence the move.
export '../../core/product_name_matching.dart';

const int lowCoverDaysThreshold = 7;
const int overstockDaysThreshold = 60;

/// Why a product has no demand figure. Distinguishing these is the point:
/// [noForecast] and [zeroPerDay] used to both render as "No demand set",
/// which also happened to be how a *mis-typed* forecast looked — so a
/// product about to stock out was indistinguishable from one nobody had
/// forecast yet. See [StockOverview.unmatchedForecasts] for the other half.
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

/// A demand forecast that is in effect today but whose product name matches
/// no finished-stock product, so nothing counts it.
///
/// This is the detectable half of the name-join problem. A stock row with no
/// matching forecast is ambiguous — it may genuinely have no demand set — but
/// a *forecast* matching no product is unambiguously doing nothing, and is
/// almost always a spelling difference rather than an intention.
class UnmatchedForecast {
  final DemandForecast forecast;

  /// The existing product name closest to [forecast]'s, when one is near
  /// enough to be worth offering as "did you mean". Null when nothing is
  /// close — a wrong guess here is worse than no guess.
  final String? closestProductName;

  const UnmatchedForecast({
    required this.forecast,
    required this.closestProductName,
  });
}

/// Everything needed to render the Stock dashboard and a single product's
/// detail page — loaded together since days-of-cover depends on matching
/// stock against demand forecasts by product name, not on a single stock
/// row in isolation.
class StockOverview {
  final List<ProductCover> covers;
  final List<DemandForecast> forecasts;

  /// Active forecasts that matched no product. Surfaced so a mis-typed name
  /// reads as a warning instead of as silence.
  final List<UnmatchedForecast> unmatchedForecasts;

  const StockOverview({
    required this.covers,
    required this.forecasts,
    this.unmatchedForecasts = const [],
  });
}

/// Levenshtein edit distance, iterative with two rows so it stays O(min) in
/// space. Only ever run over one factory's product list, so the O(n×m) time
/// is irrelevant here.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final substitution = previous[j] + (a[i] == b[j] ? 0 : 1);
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      current[j + 1] = substitution < insertion
          ? (substitution < deletion ? substitution : deletion)
          : (insertion < deletion ? insertion : deletion);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// The candidate closest to [name], or null when none is close enough to
/// suggest. The tolerance scales with length — two characters on a short
/// name, up to 20% of a long one — so "Bottle" doesn't get matched to
/// "Carton" while "Coca-Cola 500ml" still reaches "Coca Cola 500ml".
String? closestProductName(String name, Iterable<String> candidates) {
  final target = normaliseProductName(name);
  if (target.isEmpty) return null;

  final tolerance = (target.length * 0.2).round().clamp(2, 6);
  String? best;
  var bestDistance = tolerance + 1;

  for (final candidate in candidates) {
    final distance = _editDistance(target, normaliseProductName(candidate));
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  return bestDistance <= tolerance ? best : null;
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
  final requiredByName = <String, int>{};
  for (final forecast in activeForecasts) {
    final key = normaliseProductName(forecast.productName);
    requiredByName[key] = (requiredByName[key] ?? 0) + forecast.requiredPerDay;
  }

  final covers = stockList.map((stock) {
    final required = requiredByName[normaliseProductName(stock.productName)];
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

  // The reverse direction of the same join: forecasts that landed on no
  // product at all. Scoped to active forecasts, matching exactly what drives
  // days-of-cover above — a future-dated typo is caught at entry instead, by
  // the demand form's own product picker.
  final stockNames = stockList.map((s) => s.productName).toList();
  final normalisedStockNames = stockNames.map(normaliseProductName).toSet();
  final unmatched = <UnmatchedForecast>[
    for (final forecast in activeForecasts)
      if (!normalisedStockNames.contains(
        normaliseProductName(forecast.productName),
      ))
        UnmatchedForecast(
          forecast: forecast,
          closestProductName: closestProductName(
            forecast.productName,
            stockNames,
          ),
        ),
  ];

  return StockOverview(
    covers: covers,
    forecasts: forecasts,
    unmatchedForecasts: unmatched,
  );
}
