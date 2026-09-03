import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/issue_report.dart';
import '../../services/issue_report_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/issue_report_status_ui.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/report_issue_dialog.dart';
import '../../widgets/status.dart';

enum _LoadState { loading, error, ready }

class MyIssueReportsScreen extends StatefulWidget {
  const MyIssueReportsScreen({super.key});

  @override
  State<MyIssueReportsScreen> createState() => _MyIssueReportsScreenState();
}

class _MyIssueReportsScreenState extends State<MyIssueReportsScreen> {
  final _service = IssueReportService();

  _LoadState _state = _LoadState.loading;
  List<IssueReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final reports = await _service.getMyReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _newReport() async {
    final submitted = await showReportIssueDialog(context);
    if (submitted != true || !mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks — your report has been submitted.')),
    );
  }

  Future<bool> _delete(IssueReport report) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete report?',
      message: 'This removes "${report.title}" permanently.',
    );
    if (!confirmed) return false;
    try {
      await _service.deleteReport(report.reportId);
      if (!mounted) return true;
      await _load();
      if (!mounted) return true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report deleted')));
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete report. Please try again.'),
        ),
      );
      return false;
    }
  }

  void _openDetail(IssueReport report) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(report.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(
                label: issueReportStatusLabel(report.status),
                status: issueReportStatusFor(report.status),
              ),
              const SizedBox(height: AppSpacing.m),
              Text(report.description),
              const SizedBox(height: AppSpacing.m),
              Text(
                'Submitted ${formatDate(report.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My reports')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _newReport,
        tooltip: 'Report an issue',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load your reports. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_reports.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.error_outline,
                  title: 'No reports submitted yet',
                  subtitle: 'Tap + to report an issue.',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            itemCount: _reports.length,
            itemBuilder: (context, index) {
              final report = _reports[index];
              return Dismissible(
                key: ValueKey(report.reportId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _delete(report),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.l,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                child: Card(
                  child: ListTile(
                    title: Text(report.title),
                    subtitle: Text(formatDate(report.createdAt)),
                    trailing: StatusChip(
                      label: issueReportStatusLabel(report.status),
                      status: issueReportStatusFor(report.status),
                      dense: true,
                    ),
                    onTap: () => _openDetail(report),
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}
