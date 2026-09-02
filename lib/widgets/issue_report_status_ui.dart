import '../models/issue_report.dart';
import 'status.dart';

AppStatus issueReportStatusFor(String status) {
  switch (status) {
    case IssueReportStatus.solved:
      return AppStatus.success;
    case IssueReportStatus.rejected:
      return AppStatus.neutral;
    case IssueReportStatus.pending:
    default:
      return AppStatus.warning;
  }
}

String issueReportStatusLabel(String status) {
  switch (status) {
    case IssueReportStatus.solved:
      return 'Solved';
    case IssueReportStatus.rejected:
      return 'Rejected';
    case IssueReportStatus.pending:
    default:
      return 'Pending';
  }
}
