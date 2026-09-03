import 'package:flutter/material.dart';
import '../../widgets/responsive_grid_list.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/status.dart';

enum _LoadState { loading, error, ready }

enum _SortMode { newest, oldest, nameAsc }

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _profileService = ProfileService();
  final _adminService = AdminService();
  final _searchController = TextEditingController();

  _LoadState _state = _LoadState.loading;
  List<Profile> _profiles = [];
  Map<String, bool> _banStatuses = {};
  String _query = '';
  _SortMode _sortMode = _SortMode.newest;
  final Set<String> _updatingUserIds = {};

  String? get _currentUserId => AuthService().currentUser?.id;

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
      Map<String, bool> banStatuses = {};
      try {
        banStatuses = await _adminService.getUserBanStatuses();
      } catch (e) {
        debugPrint('admin: failed to load user ban statuses: $e');
      }
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _banStatuses = banStatuses;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  bool _isBanned(Profile profile) => _banStatuses[profile.id] ?? false;

  Future<void> _toggleBanned(Profile profile) async {
    final banning = !_isBanned(profile);
    final confirmed = await showConfirmDialog(
      context,
      title: banning ? 'Deactivate user?' : 'Reactivate user?',
      message: banning
          ? '"${profile.displayName?.isNotEmpty == true ? profile.displayName : profile.email}" '
                'will no longer be able to sign in.'
          : '"${profile.displayName?.isNotEmpty == true ? profile.displayName : profile.email}" '
                'will be able to sign in again.',
      confirmLabel: banning ? 'Deactivate' : 'Reactivate',
      isDestructive: banning,
    );
    if (!confirmed) return;
    setState(() => _updatingUserIds.add(profile.id));
    try {
      await _adminService.setUserBanned(profile.id, banning);
      if (!mounted) return;
      setState(() => _banStatuses = {..._banStatuses, profile.id: banning});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(banning ? 'User deactivated' : 'User reactivated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update this user. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingUserIds.remove(profile.id));
      }
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

  List<Profile> get _sorted {
    final list = List<Profile>.from(_filtered);
    switch (_sortMode) {
      case _SortMode.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortMode.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _SortMode.nameAsc:
        list.sort((a, b) {
          final an = a.displayName?.isNotEmpty == true ? a.displayName! : (a.email ?? '');
          final bn = b.displayName?.isNotEmpty == true ? b.displayName! : (b.email ?? '');
          return an.toLowerCase().compareTo(bn.toLowerCase());
        });
        break;
    }
    return list;
  }

  static const _sortLabels = {
    _SortMode.newest: 'Newest first',
    _SortMode.oldest: 'Oldest first',
    _SortMode.nameAsc: 'Name (A-Z)',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          PopupMenuButton<_SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sortMode,
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (context) => [
              for (final mode in _SortMode.values)
                PopupMenuItem(value: mode, child: Text(_sortLabels[mode]!)),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load users. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_profiles.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.people_outline,
                  title: 'No registered users yet',
                ),
              ],
            ),
          );
        }
        return _buildReady();
    }
  }

  Widget _buildReady() {
    final sorted = _sorted;
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
            child: sorted.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.search_off,
                        title: 'No users match that search',
                      ),
                    ],
                  )
                : ResponsiveGridList(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final profile = sorted[index];
                      final scheme = Theme.of(context).colorScheme;
                      final banned = _isBanned(profile);
                      final isSelf = profile.id == _currentUserId;
                      final isUpdating = _updatingUserIds.contains(profile.id);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: banned
                                ? AppColors.dangerLight
                                : scheme.primaryContainer,
                            child: Icon(
                              banned
                                  ? Icons.person_off_outlined
                                  : Icons.person_outline,
                              color: banned
                                  ? AppColors.danger
                                  : scheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            profile.displayName?.isNotEmpty == true
                                ? profile.displayName!
                                : (profile.email ?? 'Unknown'),
                          ),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  profile.displayName?.isNotEmpty == true
                                      ? (profile.email ?? '')
                                      : 'Joined ${formatDate(profile.createdAt)}',
                                ),
                              ),
                              if (banned) ...[
                                const SizedBox(width: AppSpacing.s),
                                const StatusChip(
                                  label: 'Deactivated',
                                  status: AppStatus.danger,
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                          trailing: isUpdating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: Icon(
                                    banned
                                        ? Icons.lock_open_outlined
                                        : Icons.lock_outline,
                                  ),
                                  tooltip: isSelf
                                      ? 'You can\'t deactivate your own account'
                                      : (banned ? 'Reactivate user' : 'Deactivate user'),
                                  onPressed: isSelf
                                      ? null
                                      : () => _toggleBanned(profile),
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
