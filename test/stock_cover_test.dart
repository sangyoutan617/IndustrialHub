import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/models/finished_stock.dart';
import 'package:industrial_hub/screens/stock/stock_cover_loader.dart';
import 'package:industrial_hub/widgets/status.dart';

// Stock module had zero unit-test coverage before this file — the
// days-of-cover / low-stock / overstocked classification lived entirely in
// StockDashboardScreen's private ProductCover class, so it was untestable
// from outside the file. ProductCover and the two threshold constants were
// made public (pure visibility change, no behavior change) and later moved
// into stock_cover_loader.dart so StockProductDetailScreen could reuse them
// too, specifically so this file could exercise them directly instead of
// only through a live widget + database.
void main() {
  FinishedStock stock({int quantity = 100}) => FinishedStock(
    stockId: 1,
    factoryId: 1,
    productId: 1,
    productName: 'Test Product',
    currentQuantity: quantity,
  );

  group('ProductCover.status / appStatus', () {
    test('no demand forecast (null) reads as "No demand set" / neutral', () {
      final cover = ProductCover(stock: stock(), requiredPerDay: null);
      expect(cover.status, 'No demand set');
      expect(cover.appStatus, AppStatus.neutral);
    });

    // Zero demand used to render as "No demand set" too, which hid a real
    // difference: nobody set a forecast, versus somebody set one asking for
    // nothing. The states are separate now. What this still guards is the
    // short-circuit — a zero demand must not fall through to the
    // daysOfCover branches, even when handed a nonsense cover figure the
    // loader would never produce alongside it.
    test('demand forecast of exactly zero is its own state, and still '
        'short-circuits the cover branches', () {
      final cover = ProductCover(
        stock: stock(),
        requiredPerDay: 0,
        daysOfCover: 999,
      );
      expect(cover.demandGap, DemandGap.zeroPerDay);
      expect(cover.status, 'Demand set to 0/day');
      expect(cover.appStatus, AppStatus.neutral);
    });

    test('days of cover under the low threshold is Low stock / danger', () {
      final cover = ProductCover(
        stock: stock(),
        requiredPerDay: 10,
        daysOfCover: lowCoverDaysThreshold - 0.01,
      );
      expect(cover.status, 'Low stock — reorder soon');
      expect(cover.appStatus, AppStatus.danger);
    });

    test('zero days of cover (stocked out) is Low stock / danger', () {
      final cover = ProductCover(
        stock: stock(quantity: 0),
        requiredPerDay: 10,
        daysOfCover: 0,
      );
      expect(cover.status, 'Low stock — reorder soon');
      expect(cover.appStatus, AppStatus.danger);
    });

    test(
      'days of cover exactly at the low threshold is Healthy, not Low '
      '(boundary is exclusive — only strictly under the threshold counts)',
      () {
        final cover = ProductCover(
          stock: stock(),
          requiredPerDay: 10,
          daysOfCover: lowCoverDaysThreshold.toDouble(),
        );
        expect(cover.status, 'Healthy');
        expect(cover.appStatus, AppStatus.success);
      },
    );

    test('days of cover comfortably between the thresholds is Healthy', () {
      final cover = ProductCover(
        stock: stock(),
        requiredPerDay: 10,
        daysOfCover:
            ((lowCoverDaysThreshold + overstockDaysThreshold) / 2)
                .toDouble(),
      );
      expect(cover.status, 'Healthy');
      expect(cover.appStatus, AppStatus.success);
    });

    test(
      'days of cover exactly at the overstock threshold is still Healthy '
      '(boundary is exclusive — only strictly over the threshold counts)',
      () {
        final cover = ProductCover(
          stock: stock(),
          requiredPerDay: 10,
          daysOfCover: overstockDaysThreshold.toDouble(),
        );
        expect(cover.status, 'Healthy');
        expect(cover.appStatus, AppStatus.success);
      },
    );

    test('days of cover over the overstock threshold is Overstocked / info', () {
      final cover = ProductCover(
        stock: stock(),
        requiredPerDay: 10,
        daysOfCover: overstockDaysThreshold + 0.01,
      );
      expect(cover.status, 'Overstocked');
      expect(cover.appStatus, AppStatus.info);
    });

    test('a very large days-of-cover value is still Overstocked, not NaN/Infinity', () {
      final cover = ProductCover(
        stock: stock(quantity: 1000000),
        requiredPerDay: 1,
        daysOfCover: 1000000,
      );
      expect(cover.status, 'Overstocked');
      expect(cover.daysOfCover!.isFinite, isTrue);
    });
  });

  group('days-of-cover arithmetic (as computed in StockDashboardScreen._load)', () {
    double? daysOfCoverFor(int currentQuantity, int? requiredPerDay) {
      return (requiredPerDay != null && requiredPerDay > 0)
          ? currentQuantity / requiredPerDay
          : null;
    }

    test('normal case divides stock on hand by daily demand', () {
      expect(daysOfCoverFor(100, 10), 10.0);
    });

    test('zero stock on hand with positive demand is zero days, not negative', () {
      expect(daysOfCoverFor(0, 10), 0.0);
    });

    test('null demand yields null days of cover, not a divide-by-zero', () {
      expect(daysOfCoverFor(100, null), isNull);
    });

    test('zero demand yields null days of cover, not a divide-by-zero', () {
      expect(daysOfCoverFor(100, 0), isNull);
    });

    test('negative demand (should never occur, but must not crash or go '
        'negative-infinite) is treated the same as no demand', () {
      expect(daysOfCoverFor(100, -5), isNull);
    });
  });
}
