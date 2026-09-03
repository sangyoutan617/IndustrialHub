import 'package:flutter/material.dart';
import '../../widgets/responsive_grid_list.dart';
import '../../models/factory.dart';
import '../../models/profile.dart';
import '../../services/factory_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import 'admin_factory_detail_screen.dart';

enum _LoadState { loading, error, ready }

class AdminFactoriesScreen extends StatefulWidget {
  const AdminFactoriesScreen({super.key});

  @override
  State<AdminFactoriesScreen> createState() => _AdminFactoriesScreenState();
}

class _AdminFactoriesScreenState extends State<AdminFactoriesScreen> {
  final _factoryService = FactoryService();
  final _profileService = ProfileService();

  _LoadState _state = _LoadState.loading;
  List<Factory> _factories = [];
  Map<String, Profile> _ownersById = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final results = await Future.wait<dynamic>([
        _factoryService.getFactories(),
        _profileService.getProfiles(),
      ]);
      final factories = results[0] as List<Factory>;
      final profiles = results[1] as List<Profile>;
      setState(() {
        _factories = factories;
        _ownersById = {for (final p in profiles) p.id: p};
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
  }

  String _ownerName(Factory factory) {
    final owner = factory.ownerId != null
        ? _ownersById[factory.ownerId]
        : null;
    if (owner == null) return 'Unknown owner';
    return owner.displayName?.isNotEmpty == true
        ? owner.displayName!
        : (owner.email ?? 'Unknown owner');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All factories')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const LoadingIndicator();
      case _LoadState.error:
        return ErrorState(
          message: 'Could not load factories. Please try again.',
          onRetry: _load,
        );
      case _LoadState.ready:
        if (_factories.isEmpty) {
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.factory_outlined,
                  title: 'No factories exist yet',
                ),
              ],
            ),
          );
        }
        return _buildReady();
    }
  }

  Widget _buildReady() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ResponsiveGridList(
        padding: const EdgeInsets.all(16),
        itemCount: _factories.length,
        itemBuilder: (context, index) {
          final factory = _factories[index];
          final address = [
            if (factory.location != null) factory.location!,
            if (factory.state != null) factory.state!,
          ].join(', ');
          final theme = Theme.of(context);
          return Card(
            child: ListTile(
              leading: Icon(
                Icons.factory_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                factory.factoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _ownerName(factory),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      address.isEmpty ? 'No address set' : address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      factory.msicCode != null
                          ? 'MSIC ${factory.msicCode}'
                          : 'No MSIC code set',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminFactoryDetailScreen(factory: factory),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
