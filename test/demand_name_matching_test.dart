import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/finished_stock.dart';
import 'package:industrial_hub/screens/stock/stock_cover_loader.dart';
import 'package:industrial_hub/widgets/status.dart';

// Demand is joined to finished stock by product name, with no foreign key
// behind it. These cover the two halves of making that join's failure
// visible: normalisation (what the join forgives), and the "did you mean"
// suggestion offered when it doesn't match.

FinishedStock _stock({int quantity = 100, String name = 'Cola 500ml'}) {
  return FinishedStock(
    stockId: 1,
    factoryId: 1,
    productName: name,
    currentQuantity: quantity,
  );
}

void main() {
  group('normaliseProductName', () {
    test('absorbs case and surrounding whitespace — the differences the '
        'join is meant to forgive', () {
      expect(
        normaliseProductName('  Coca Cola 500ml  '),
        normaliseProductName('coca cola 500ml'),
      );
    });

    test('does not absorb internal punctuation or spacing, which is exactly '
        'where the silent mismatch used to come from', () {
      expect(
        normaliseProductName('Coca-Cola 500ml'),
        isNot(normaliseProductName('Coca Cola 500ml')),
      );
      expect(
        normaliseProductName('500 ml'),
        isNot(normaliseProductName('500ml')),
      );
    });
  });

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

  group('closestProductName', () {
    const products = ['Coca Cola 500ml', 'Sparkling Water 1L', 'Ginger Beer'];

    test('reaches across a punctuation difference — the motivating case', () {
      expect(
        closestProductName('Coca-Cola 500ml', products),
        'Coca Cola 500ml',
      );
    });

    test('reaches across a small typo', () {
      expect(closestProductName('Ginger Ber', products), 'Ginger Beer');
    });

    test('is case- and whitespace-insensitive, like the join itself', () {
      expect(
        closestProductName('  COCA COLA 500ML ', products),
        'Coca Cola 500ml',
      );
    });

    test('offers nothing when nothing is close — a wrong guess is worse '
        'than no guess', () {
      expect(closestProductName('Motor Oil', products), isNull);
    });

    test('does not match two genuinely different short names that happen to '
        'share a length', () {
      expect(closestProductName('Carton', ['Bottle']), isNull);
    });

    test('empty input and empty candidate list yield no suggestion', () {
      expect(closestProductName('', products), isNull);
      expect(closestProductName('Cola', const []), isNull);
    });

    test('picks the nearest candidate when several are plausible', () {
      expect(
        closestProductName('Ginger Beerr', ['Ginger Beer', 'Ginger Bear']),
        'Ginger Beer',
      );
    });
  });
}
