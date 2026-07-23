import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../services/profile_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

enum _LoadState { loading, error, ready }

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _profileService = ProfileService();
  final _searchController = TextEditingController();

  _LoadState _state = _LoadState.loading;
  List<Profile> _profiles = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final profiles = await _profileService.getProfiles();
      setState(() {
        _profiles = profiles;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  List<Profile> get _filtered {
    if (_query.isEmpty) return _profiles;
    final q = _query.toLowerCase();
    return _profiles.where((p) {
      return (p.email?.toLowerCase().contains(q) ?? false) ||
          (p.displayName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return EmptyState.error(onAction: _load);
      case _LoadState.ready:
        if (_profiles.isEmpty) {
          return const EmptyState(
            icon: Icons.people_outline,
            message: 'No registered users yet.',
          );
        }
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search by name or email',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.search_off,
                        message: 'No users match that search.',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final profile = filtered[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primaryLight,
                            child: Icon(
                              Icons.person_outline,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            profile.displayName?.isNotEmpty == true
                                ? profile.displayName!
                                : (profile.email ?? 'Unknown'),
                          ),
                          subtitle: Text(
                            profile.displayName?.isNotEmpty == true
                                ? (profile.email ?? '')
                                : 'Joined ${_formatDate(profile.createdAt)}',
                          ),
                          trailing: Text(
                            _formatDate(profile.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
