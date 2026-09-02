import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/issue_report.dart';
import '../../services/issue_report_service.dart';
import '../../widgets/issue_report_status_ui.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status.dart';

class IssueReportDetailScreen extends StatefulWidget {
  final IssueReport report;

  const IssueReportDetailScreen({super.key, required this.report});

  @override
  State<IssueReportDetailScreen> createState() =>
      _IssueReportDetailScreenState();
}

class _IssueReportDetailScreenState extends State<IssueReportDetailScreen> {
  final _service = IssueReportService();
  late IssueReport _report = widget.report;
  bool _isSaving = false;

  Future<void> _updateStatus(String status) async {
    if (status == _report.status) return;
    setState(() => _isSaving = true);
    try {
      final updated = await _service.updateStatus(_report.reportId, status);
      if (!mounted) return;
      setState(() => _report = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update status. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Issue report')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.l),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _report.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusChip(
                  label: issueReportStatusLabel(_report.status),
                  status: issueReportStatusFor(_report.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.l,
                  vertical: AppSpacing.s,
                ),
                child: Column(
                  children: [
                    MetricRow(
                      label: 'Submitted by',
                      value: _report.submitterLabel,
                    ),
                    MetricRow(
                      label: 'Submitted at',
                      value: formatDate(_report.createdAt),
                    ),
                    MetricRow(
                      label: 'Last updated',
                      value: formatDate(_report.updatedAt),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            const SectionHeader(title: 'Description'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Text(_report.description),
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            const SectionHeader(title: 'Status'),
            SegmentedButton<String>(
              segments: [
                for (final status in IssueReportStatus.all)
                  ButtonSegment(
                    value: status,
                    label: Text(issueReportStatusLabel(status)),
                  ),
              ],
              selected: {_report.status},
              onSelectionChanged: _isSaving
                  ? null
                  : (selection) => _updateStatus(selection.first),
            ),
          ],
        ),
      ),
    );
  }
}
