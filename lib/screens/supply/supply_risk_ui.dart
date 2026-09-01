import '../../services/mrp_service.dart';
import '../../widgets/status.dart';

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

int supplyRiskPriority(SupplyRisk risk) => switch (risk) {
  SupplyRisk.stockedOut => 0,
  SupplyRisk.reorderNow => 1,
  SupplyRisk.watch => 2,
  SupplyRisk.healthy => 3,
  SupplyRisk.noSupplier => 4,
};
