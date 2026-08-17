import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/factory.dart';
import '../../services/auth_service.dart';
import '../../services/factory_service.dart';
import '../../services/report_service.dart';
import '../../services/seed_service.dart';
import '../../widgets/bottleneck_banner.dart';
import '../../widgets/confirm_dialog.dart';
import '../capacity/capacity_dashboard_screen.dart';
import '../stock/stock_dashboard_screen.dart';
import '../supply/material_list_screen.dart';
import 'about_screen.dart';
import 'dashboard_home_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _LoadState { loading, error, ready }

class _HomeScreenState extends State<HomeScreen> {
  final _factoryService = FactoryService();
  final _authService = AuthService();
  final _seedService = SeedService();
  final _reportService = ReportService();

  _LoadState _loadState = _LoadState.loading;
  List<Factory> _factories = [];
  Factory? _selectedFactory;
  int _tabIndex = 0;
  bool _isSeeding = false;
  int _bottleneckRefreshTick = 0;

  static const _tabs = ['Home', 'Capacity', 'Stock', 'Supply'];
  static const _tabIcons = [
    Icons.home_rounded,
    Icons.precision_manufacturing,
    Icons.inventory_2,
    Icons.local_shipping,
  ];

  @override
  void initState() {
    super.initState();
    _loadFactories();
  }

  Future<void> _loadFactories() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final factories = await _factoryService.getFactories();
      setState(() {
        _factories = factories;
        _selectedFactory = factories.isNotEmpty ? factories.first : null;
        _loadState = _LoadState.ready;
      });
    } catch (_) {
      setState(() => _loadState = _LoadState.error);
    }
  }

  Future<void> _createFactory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New factory'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Factory name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final factory = await _factoryService.createFactory(name);
      setState(() {
        _factories = [..._factories, factory];
        _selectedFactory = factory;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create factory. Please try again.'),
        ),
      );
    }
  }

  Future<void> _loadDemoData() async {
    setState(() => _isSeeding = true);
    try {
      final result = await _seedService.seedDemoData();
      final factories = await _factoryService.getFactories();
      setState(() {
        _factories = factories;
        _selectedFactory = result.factory;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.outcome == SeedOutcome.created
                ? 'Demo data loaded.'
                : 'Demo data was already loaded — switched to it.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load demo data. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      if (!mounted) return;
      // Usually a no-op (AuthGate renders HomeScreen in place, so the
      // sign-out stream event alone swaps it back to LoginScreen). But a
      // non-admin who came in via the admin login link reaches HomeScreen
      // pushed on top of AuthGate instead — pop back down so that path
      // also lands on LoginScreen rather than an inert HomeScreen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    }
  }

  Future<void> _shareReport() async {
    final factory = _selectedFactory;
    if (factory == null) return;
    try {
      final bytes = await _reportService.buildFactoryReportPdf(factory);
      final safeName = factory.factoryName.replaceAll(
        RegExp(r'[^A-Za-z0-9]+'),
        '_',
      );
      await Printing.sharePdf(bytes: bytes, filename: '${safeName}_report.pdf');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate report. Please try again.'),
        ),
      );
    }
  }

  Future<void> _renameFactory(Factory factory) async {
    final controller = TextEditingController(text: factory.factoryName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename factory'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Factory name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == factory.factoryName) return;
    try {
      final updated = await _factoryService.renameFactory(
        factory.factoryId,
        name,
      );
      setState(() {
        _factories = [
          for (final f in _factories)
            f.factoryId == updated.factoryId ? updated : f,
        ];
        if (_selectedFactory?.factoryId == updated.factoryId) {
          _selectedFactory = updated;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not rename factory. Please try again.'),
        ),
      );
    }
  }

  Future<void> _deleteFactory(Factory factory) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete factory?',
      message:
          'This permanently removes "${factory.factoryName}". Remove its '
          'machines, stock and material data first if the delete is refused.',
    );
    if (!confirmed) return;
    try {
      await _factoryService.deleteFactory(factory.factoryId);
      final factories = await _factoryService.getFactories();
      setState(() {
        _factories = factories;
        if (_selectedFactory?.factoryId == factory.factoryId) {
          _selectedFactory = factories.isNotEmpty ? factories.first : null;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Factory deleted')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not delete factory — remove its machines, stock and '
            'materials first.',
          ),
        ),
      );
    }
  }

  void _pickFactory() {
    if (_factories.isEmpty) {
      _createFactory();
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final factory in _factories)
              ListTile(
                title: Text(factory.factoryName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (factory.factoryId == _selectedFactory?.factoryId)
                      const Icon(Icons.check),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        Navigator.pop(context);
                        if (value == 'rename') {
                          _renameFactory(factory);
                        } else if (value == 'delete') {
                          _deleteFactory(factory);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
                onTap: () {
                  setState(() => _selectedFactory = factory);
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New factory'),
              onTap: () {
                Navigator.pop(context);
                _createFactory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Load demo data'),
              onTap: () {
                Navigator.pop(context);
                _loadDemoData();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedFactory?.factoryName ?? 'Industrial Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.factory_outlined),
            tooltip: 'Switch factory',
            onPressed: _loadState == _LoadState.ready ? _pickFactory : null,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share report',
            onPressed:
                (_loadState == _LoadState.ready && _selectedFactory != null)
                ? _shareReport
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() {
          _tabIndex = index;
          _bottleneckRefreshTick++;
        }),
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(icon: Icon(_tabIcons[i]), label: _tabs[i]),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadState == _LoadState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadState == _LoadState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load factory data.'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loadFactories, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_selectedFactory == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No factory set up yet.'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isSeeding ? null : _createFactory,
              child: const Text('Create factory'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isSeeding ? null : _loadDemoData,
              child: _isSeeding
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load demo data'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // The Home tab has its own, richer bottleneck engine card built
        // in — showing this banner above it too would just duplicate the
        // same verdict, so it's skipped only for that tab.
        if (_tabIndex != 0)
          BottleneckBanner(
            key: ValueKey(
              '${_selectedFactory!.factoryId}-$_bottleneckRefreshTick',
            ),
            factoryId: _selectedFactory!.factoryId,
          ),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildTabContent() {
    if (_tabIndex == 0) {
      return DashboardHomeScreen(
        key: ValueKey(_selectedFactory!.factoryId),
        factory: _selectedFactory!,
      );
    }
    if (_tabIndex == 1) {
      return CapacityDashboardScreen(
        key: ValueKey(_selectedFactory!.factoryId),
        factory: _selectedFactory!,
      );
    }
    if (_tabIndex == 2) {
      return StockDashboardScreen(
        key: ValueKey(_selectedFactory!.factoryId),
        factoryId: _selectedFactory!.factoryId,
      );
    }
    return MaterialListScreen(
      key: ValueKey(_selectedFactory!.factoryId),
      factoryId: _selectedFactory!.factoryId,
    );
  }
}
