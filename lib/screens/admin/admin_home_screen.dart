import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => AuthService().signOut(),
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
            icon: Icons.bar_chart_outlined,
            title: 'Cross-factory analytics',
            subtitle: 'Coming soon',
          ),
          _adminTile(
            icon: Icons.factory_outlined,
            title: 'All factories',
            subtitle: 'Coming soon',
          ),
          _adminTile(
            icon: Icons.people_outline,
            title: 'Users',
            subtitle: 'Coming soon',
          ),
          _adminTile(
            icon: Icons.storage_outlined,
            title: 'Data & seed management',
            subtitle: 'Coming soon',
          ),
        ],
      ),
    );
  }

  Widget _adminTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: false,
      ),
    );
  }
}
