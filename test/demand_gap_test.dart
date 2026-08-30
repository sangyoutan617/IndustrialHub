import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/finished_stock.dart';
import 'package:industrial_hub/screens/stock/stock_cover_loader.dart';
import 'package:industrial_hub/widgets/status.dart';

// Formerly test/demand_name_matching_test.dart — the free-text product-name
// join (normaliseProductName/closestProductName, Levenshtein matching) that
// file's name referred to no longer exists: demand_forecast now joins to
// finished_stock through a real product_id FK (multi-product capacity plan,
// phase h), which makes an "unmatched forecast" structurally impossible.
// What's left is the ProductCover/DemandGap classification logic itself,
// which is unrelated to how the join happens and still worth testing
// directly.

FinishedStock _stock({int quantity = 100, String name = 'Cola 500ml'}) {
  return FinishedStock(
    stockId: 1,
    factoryId: 1,
    productId: 1,
    productName: name,
    currentQuantity: quantity,
  );
}

void main() {
  group('DemandGap — splitting what used to be one "No demand set"', () {
    test('a product no forecast matched reports noForecast', () {
      final cover = ProductCover(stock: _stock());

      expect(cover.demandGap, DemandGap.noForecast);
      expect(cover.status, 'No demand set');
      expect(cover.appStatus, AppStatus.neutral);
      expect(cover.needsAttention, isFalse);
    });

    test('a forecast that matched but asks for zero is a distinct state, not '
        'the same as having no forecast', () {
      final cover = ProductCover(stock: _stock(), requiredPerDay: 0);

      expect(cover.demandGap, DemandGap.zeroPerDay);
      expect(cover.status, 'Demand set to 0/day');
      expect(cover.appStatus, AppStatus.neutral);
    });

    test('a real demand figure closes the gap entirely', () {
      final cover = ProductCover(
        stock: _stock(quantity: 100),
        requiredPerDay: 10,
        daysOfCover: 10,
      );

      expect(cover.demandGap, isNull);
      expect(cover.status, 'Healthy');
      expect(cover.appStatus, AppStatus.success);
    });

    test('needsAttention never fires while a demand gap is open, so a null '
        'daysOfCover can not be dereferenced', () {
      expect(ProductCover(stock: _stock()).needsAttention, isFalse);
      expect(
        ProductCover(stock: _stock(), requiredPerDay: 0).needsAttention,
        isFalse,
      );
      expect(
        ProductCover(
          stock: _stock(),
          requiredPerDay: 50,
          daysOfCover: 2,
        ).needsAttention,
        isTrue,
      );
    });
  });
}
