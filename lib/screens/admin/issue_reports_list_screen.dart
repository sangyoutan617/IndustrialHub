import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../models/issue_report.dart';
import '../../services/issue_report_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/issue_report_status_ui.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';
import 'issue_report_detail_screen.dart';

enum _LoadState { loading, error, ready }

class IssueReportsListScreen extends StatefulWidget {
  const IssueReportsListScreen({super.key});

  @override
  State<IssueReportsListScreen> createState() =>
      _IssueReportsListScreenState();
}

class _IssueReportsListScreenState extends State<IssueReportsListScreen> {
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
      final reports = await _service.getAllReports();
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

  Future<void> _openDetail(IssueReport report) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IssueReportDetailScreen(report: report)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Issue Reports')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load issue reports. Please try again.',
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
                  title: 'No issue reports yet',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _reports.length,
            itemBuilder: (context, index) {
              final report = _reports[index];
              return Card(
                child: ListTile(
                  title: Text(report.title),
                  subtitle: Text(
                    '${report.submitterLabel} · ${formatDate(report.createdAt)}',
                  ),
                  trailing: StatusChip(
                    label: issueReportStatusLabel(report.status),
                    status: issueReportStatusFor(report.status),
                    dense: true,
                  ),
                  onTap: () => _openDetail(report),
                ),
              );
            },
          ),
        );
    }
  }
}
