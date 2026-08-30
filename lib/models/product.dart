class Product {
  final int productId;
  final int factoryId;
  final String productName;
  final String unit;

  /// True for the single auto-created catch-all every factory got when
  /// multi-product support was introduced — every machine/manpower shift/
  /// material rate that predated real products was migrated onto it. Not a
  /// product a user deliberately modelled; surfaced distinctly in pickers
  /// (e.g. listed last, or labelled "General") rather than hidden, since
  /// machines/manpower must always reference some product and this is a
  /// legitimate one to assign to.
  final bool isGeneral;

  const Product({
    required this.productId,
    required this.factoryId,
    required this.productName,
    this.unit = 'units',
    this.isGeneral = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      productId: json['product_id'] as int,
      factoryId: json['factory_id'] as int,
      productName: json['product_name'] as String,
      unit: json['unit'] as String? ?? 'units',
      isGeneral: json['is_general'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson(int factoryId) {
    return {
      'factory_id': factoryId,
      'product_name': productName,
      'unit': unit,
      // is_general is never set from the client — only the migration's
      // one-per-factory catch-all is ever true, enforced by a partial
      // unique index; every product a user creates is a real one.
    };
  }
}
