import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/issue_report.dart';

class IssueReportService {
  final SupabaseClient _client = Supabase.instance.client;

  static const _selectWithUser = '*, profiles(display_name, email)';

  Future<IssueReport> submitReport({
    required String title,
    required String description,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('issue_reports')
        .insert({
          'user_id': userId,
          'title': title,
          'description': description,
          'status': IssueReportStatus.pending,
        })
        .select(_selectWithUser)
        .single();
    return IssueReport.fromJson(row);
  }

  Future<List<IssueReport>> getAllReports() async {
    final rows = await _client
        .from('issue_reports')
        .select(_selectWithUser)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => IssueReport.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<IssueReport>> getMyReports() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('issue_reports')
        .select(_selectWithUser)
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => IssueReport.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteReport(int reportId) async {
    await _client.from('issue_reports').delete().eq('report_id', reportId);
  }

  Future<IssueReport> updateStatus(int reportId, String status) async {
    final row = await _client
        .from('issue_reports')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('report_id', reportId)
        .select(_selectWithUser)
        .single();
    return IssueReport.fromJson(row);
  }
}
