import '../models/supplier.dart';

class SupplierValidators {
  const SupplierValidators._();

  static const int maxNameLength = 100;
  static const int maxLeadTimeDays = 14;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _phonePattern = RegExp(r'^\+?[0-9]{9,12}$');

  static bool isDuplicateName(
    List<Supplier> existingSuppliers,
    String name, {
    int? excludingSupplierId,
  }) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return existingSuppliers.any(
      (s) =>
          s.supplierId != excludingSupplierId &&
          s.supplierName.trim().toLowerCase() == normalized,
    );
  }

  static String? validateName(
    String? value, {
    required List<Supplier> existingSuppliers,
    int? excludingSupplierId,
  }) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Required';
    if (trimmed.length > maxNameLength) {
      return 'Must be $maxNameLength characters or fewer';
    }
    if (isDuplicateName(
      existingSuppliers,
      trimmed,
      excludingSupplierId: excludingSupplierId,
    )) {
      return 'A supplier with this name already exists';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _emailPattern.hasMatch(trimmed) ? null : 'Enter a valid email';
  }

  static String? validateLeadTime(String? value) {
    final trimmed = value?.trim() ?? '';
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      return 'Enter a non-negative whole number';
    }
    if (parsed > maxLeadTimeDays) {
      return 'Lead time cannot exceed $maxLeadTimeDays working days';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final digitsOnly = trimmed.replaceAll(RegExp(r'[\s-]'), '');
    return _phonePattern.hasMatch(digitsOnly)
        ? null
        : 'Enter a valid phone number';
  }
}
