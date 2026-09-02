import 'package:flutter_test/flutter_test.dart';
import 'package:industrial_hub/core/supplier_validators.dart';
import 'package:industrial_hub/models/supplier.dart';

Supplier _supplier({
  required int id,
  required String name,
}) {
  return Supplier(
    supplierId: id,
    supplierName: name,
    leadTimeDays: 7,
    reliabilityRating: 3,
    isSimulated: false,
  );
}

void main() {
  group('SupplierValidators.validateEmail', () {
    for (final email in [
      'supplier@gmail.com',
      'sales@company.com',
      'john.doe@company.com',
    ]) {
      test('accepts $email', () {
        expect(SupplierValidators.validateEmail(email), isNull);
      });
    }

    for (final email in ['abc', 'abc@', '@abc', 'abc@xyz', 'abc.com']) {
      test('rejects $email', () {
        expect(SupplierValidators.validateEmail(email), isNotNull);
      });
    }

    test('accepts empty (optional field)', () {
      expect(SupplierValidators.validateEmail(''), isNull);
      expect(SupplierValidators.validateEmail(null), isNull);
      expect(SupplierValidators.validateEmail('   '), isNull);
    });
  });

  group('SupplierValidators.validatePhone', () {
    for (final phone in [
      '0123456789',
      '012-3456789',
      '01112345678',
      '+60123456789',
      '+60 12-345 6789',
    ]) {
      test('accepts $phone', () {
        expect(SupplierValidators.validatePhone(phone), isNull);
      });
    }

    for (final phone in ['abc', '123', 'hello123', '++++']) {
      test('rejects $phone', () {
        expect(SupplierValidators.validatePhone(phone), isNotNull);
      });
    }

    test('accepts empty (optional field)', () {
      expect(SupplierValidators.validatePhone(''), isNull);
      expect(SupplierValidators.validatePhone(null), isNull);
    });
  });

  group('SupplierValidators.validateLeadTime', () {
    test('rejects empty input', () {
      expect(SupplierValidators.validateLeadTime(''), isNotNull);
      expect(SupplierValidators.validateLeadTime(null), isNotNull);
    });

    test('rejects a negative number', () {
      expect(SupplierValidators.validateLeadTime('-1'), isNotNull);
    });

    test('rejects a decimal value', () {
      expect(SupplierValidators.validateLeadTime('3.5'), isNotNull);
    });

    test('rejects non-numeric input', () {
      expect(SupplierValidators.validateLeadTime('abc'), isNotNull);
    });

    test('accepts zero (same-day delivery)', () {
      expect(SupplierValidators.validateLeadTime('0'), isNull);
    });

    test('accepts a value within the 14-day cap', () {
      expect(SupplierValidators.validateLeadTime('7'), isNull);
    });

    test('accepts exactly 14 days', () {
      expect(SupplierValidators.validateLeadTime('14'), isNull);
    });

    test('rejects a value over 14 days', () {
      expect(SupplierValidators.validateLeadTime('15'), isNotNull);
    });
  });

  group('SupplierValidators.isDuplicateName', () {
    final existing = [
      _supplier(id: 1, name: 'ABC Supplier'),
      _supplier(id: 2, name: 'Other Supplier'),
    ];

    test('flags an exact match', () {
      expect(SupplierValidators.isDuplicateName(existing, 'ABC Supplier'),
          isTrue);
    });

    test('flags a case-insensitive match', () {
      expect(
          SupplierValidators.isDuplicateName(existing, 'abc supplier'), isTrue);
    });

    test('flags a match with leading/trailing spaces', () {
      expect(SupplierValidators.isDuplicateName(existing, '  ABC Supplier  '),
          isTrue);
    });

    test('does not flag a genuinely different name', () {
      expect(SupplierValidators.isDuplicateName(existing, 'New Supplier'),
          isFalse);
    });

    test('excludes the supplier being edited from its own duplicate check',
        () {
      expect(
        SupplierValidators.isDuplicateName(
          existing,
          'ABC Supplier',
          excludingSupplierId: 1,
        ),
        isFalse,
      );
    });

    test('still flags a collision with a different supplier while editing',
        () {
      expect(
        SupplierValidators.isDuplicateName(
          existing,
          'Other Supplier',
          excludingSupplierId: 1,
        ),
        isTrue,
      );
    });
  });

  group('SupplierValidators.validateName', () {
    final existing = [_supplier(id: 1, name: 'ABC Supplier')];

    test('rejects empty name', () {
      expect(SupplierValidators.validateName('', existingSuppliers: existing),
          isNotNull);
    });

    test('rejects whitespace-only name', () {
      expect(
          SupplierValidators.validateName('   ', existingSuppliers: existing),
          isNotNull);
    });

    test('rejects a name over the max length', () {
      final tooLong = 'A' * (SupplierValidators.maxNameLength + 1);
      expect(
          SupplierValidators.validateName(tooLong, existingSuppliers: existing),
          isNotNull);
    });

    test('accepts a name at the max length', () {
      final atLimit = 'A' * SupplierValidators.maxNameLength;
      expect(
          SupplierValidators.validateName(atLimit, existingSuppliers: existing),
          isNull);
    });

    test('rejects a duplicate name on create', () {
      expect(
        SupplierValidators.validateName('abc supplier',
            existingSuppliers: existing),
        isNotNull,
      );
    });

    test('allows a supplier to keep its own unchanged name on update', () {
      expect(
        SupplierValidators.validateName(
          'ABC Supplier',
          existingSuppliers: existing,
          excludingSupplierId: 1,
        ),
        isNull,
      );
    });

    test('accepts a valid, non-duplicate name', () {
      expect(
        SupplierValidators.validateName('New Supplier',
            existingSuppliers: existing),
        isNull,
      );
    });
  });
}
