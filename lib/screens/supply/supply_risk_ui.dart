import '../../services/mrp_service.dart';
import '../../widgets/status.dart';

/// Single source of truth for mapping [SupplyRisk] onto the app-wide status
/// vocabulary and its label — shared by the material list and material
/// detail screens so the two can never drift apart. stockedOut and
/// reorderNow share the danger color family (both are urgent/red); the
/// label text still tells them apart.
AppStatus supplyRiskStatus(SupplyRisk risk) {
  switch (risk) {
    case SupplyRisk.stockedOut:
    case SupplyRisk.reorderNow:
      return AppStatus.danger;
    case SupplyRisk.watch:
      return AppStatus.warning;
    case SupplyRisk.noSupplier:
      return AppStatus.neutral;
    case SupplyRisk.healthy:
      return AppStatus.success;
  }
}

String supplyRiskLabel(SupplyRisk risk) {
  switch (risk) {
    case SupplyRisk.stockedOut:
      return 'Stocked out';
    case SupplyRisk.reorderNow:
      return 'Reorder now';
    case SupplyRisk.watch:
      return 'Watch';
    case SupplyRisk.noSupplier:
      return 'No supplier';
    case SupplyRisk.healthy:
      return 'Healthy';
  }
}

/// Sorts the most urgent materials first — same ordering used by the
/// materials list and the AI prompt, pulled out so the new "Attention
/// required" section on the Supply home screen can reuse it exactly.
int supplyRiskPriority(SupplyRisk risk) => switch (risk) {
  SupplyRisk.stockedOut => 0,
  SupplyRisk.reorderNow => 1,
  SupplyRisk.watch => 2,
  SupplyRisk.healthy => 3,
  SupplyRisk.noSupplier => 4,
};
