import 'package:flutter/material.dart';
import '../../models/factory.dart';
import '../../services/factory_service.dart';
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

  _LoadState _state = _LoadState.loading;
  List<Factory> _factories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final factories = await _factoryService.getFactories();
      setState(() {
        _factories = factories;
        _state = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _state = _LoadState.error);
    }
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
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _factories.length,
        itemBuilder: (context, index) {
          final factory = _factories[index];
          final subtitle = [
            if (factory.location != null) factory.location!,
            if (factory.state != null) factory.state!,
          ].join(', ');
          return Card(
            child: ListTile(
              leading: Icon(
                Icons.factory_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                factory.factoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitle.isEmpty
                    ? (factory.msicCode ?? 'No location set')
                    : subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
