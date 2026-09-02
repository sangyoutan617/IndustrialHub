import 'package:flutter/material.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import 'admin_analytics_screen.dart';
import 'admin_factories_screen.dart';
import 'admin_data_screen.dart';
import 'admin_users_screen.dart';
import 'issue_reports_list_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService().signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Oversight & analytics',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _adminTile(
            context,
            icon: Icons.bar_chart_outlined,
            title: 'Cross-factory analytics',
            subtitle:
                'Achievable output, demand and bottlenecks across all factories',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminAnalyticsScreen()),
            ),
          ),
          _adminTile(
            context,
            icon: Icons.factory_outlined,
            title: 'All factories',
            subtitle: 'Every factory, read-only detail and live alerts',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminFactoriesScreen()),
            ),
          ),
          _adminTile(
            context,
            icon: Icons.people_outline,
            title: 'Users',
            subtitle: 'All registered users, searchable',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AdminUsersScreen())),
          ),
          _adminTile(
            context,
            icon: Icons.storage_outlined,
            title: 'Data & seed management',
            subtitle: 'Run seed and view simulated-data counts',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AdminDataScreen())),
          ),
          _adminTile(
            context,
            icon: Icons.error_outline,
            title: 'Issue Reports',
            subtitle: 'User-submitted issues, review and update status',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IssueReportsListScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
