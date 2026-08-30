/// The single normalisation used to match a product name against another
/// one when no foreign key ties them together — trim, then lowercase.
///
/// Today that's `demand_forecast.product_name` against `products`/
/// `finished_stock` names (see stock_cover_loader.dart and
/// SupplyService.load). A real `product_id` FK on `demand_forecast` is
/// planned to replace this (multi-product capacity plan, phase h); until
/// then every caller must normalise identically or a forecast silently
/// stops counting, so this stays the one place that logic lives.
String normaliseProductName(String name) => name.trim().toLowerCase();
