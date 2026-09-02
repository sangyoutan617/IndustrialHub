class IssueReportStatus {
  static const pending = 'pending';
  static const solved = 'solved';
  static const rejected = 'rejected';
  static const all = [pending, solved, rejected];
}

class IssueReport {
  final int reportId;
  final String userId;
  final String title;
  final String description;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? submitterName;
  final String? submitterEmail;

  const IssueReport({
    required this.reportId,
    required this.userId,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.submitterName,
    this.submitterEmail,
  });

  factory IssueReport.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return IssueReport(
      reportId: json['report_id'] as int,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      status: json['status'] as String? ?? IssueReportStatus.pending,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      submitterName: profile?['display_name'] as String?,
      submitterEmail: profile?['email'] as String?,
    );
  }

  String get submitterLabel =>
      (submitterName?.isNotEmpty ?? false) ? submitterName! : (submitterEmail ?? 'Unknown user');
}
