import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/factory.dart';
import '../../services/auth_service.dart';
import '../../services/factory_service.dart';
import '../../services/notification_service.dart';
import '../../services/report_service.dart';
import '../../services/seed_service.dart';
import '../../services/supply_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/bottleneck_banner.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/loading_indicator.dart';
import '../capacity/capacity_dashboard_screen.dart';
import '../stock/stock_dashboard_screen.dart';
import '../supply/material_list_screen.dart';
import 'about_screen.dart';
import 'dashboard_home_screen.dart';
import 'factory_settings_screen.dart';
import 'profile_screen.dart';

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
  final _supplyService = SupplyService();

  _LoadState _loadState = _LoadState.loading;
  List<Factory> _factories = [];
  Factory? _selectedFactory;
  int _tabIndex = 0;
  bool _isSeeding = false;
  int _bottleneckRefreshTick = 0;

  // Tabs are built lazily (on first visit) and then kept alive via
  // IndexedStack, so switching tabs never re-fetches a module's data, but a
  // module you've never opened never loads at startup either.
  final Set<int> _visitedTabs = {0};

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
      // The auth gate can dispose this screen (e.g. a "remember me" sign-out
      // completing) while getFactories() is still in flight.
      if (!mounted) return;
      setState(() {
        _factories = factories;
        _selectedFactory = factories.isNotEmpty ? factories.first : null;
        _loadState = _LoadState.ready;
      });
      if (_selectedFactory != null) _checkAlerts(_selectedFactory!);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  // Best-effort supply-risk notification when a factory is opened. Never
  // blocks the UI or surfaces an error — the alert is a nice-to-have on top
  // of the in-app risk display. Skipped on web (no local notifications).
  Future<void> _checkAlerts(Factory factory) async {
    if (kIsWeb) return;
    try {
      final overview = await _supplyService.load(factory.factoryId);
      await NotificationService.instance.notifySupplyRisk(factory, overview);
    } catch (_) {
      // Ignore — best-effort only.
    }
  }

  Future<void> _createFactory() async {
    final controller = TextEditingController();
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.add_business_outlined),
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
    } finally {
      controller.dispose();
    }
    if (name == null || name.isEmpty) return;
    try {
      final factory = await _factoryService.createFactory(name);
      if (!mounted) return;
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
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.edit_outlined),
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
    } finally {
      controller.dispose();
    }
    if (name == null || name.isEmpty || name == factory.factoryName) return;
    try {
      final updated = await _factoryService.renameFactory(
        factory.factoryId,
        name,
      );
      if (!mounted) return;
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

  Future<void> _editFactoryDetails(Factory factory) async {
    final updated = await Navigator.of(context).push<Factory>(
      MaterialPageRoute(
        builder: (_) => FactorySettingsScreen(factory: factory),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _factories = [
        for (final f in _factories)
          f.factoryId == updated.factoryId ? updated : f,
      ];
      if (_selectedFactory?.factoryId == updated.factoryId) {
        _selectedFactory = updated;
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Factory details updated')));
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Factories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            for (final factory in _factories)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: factory.factoryId ==
                          _selectedFactory?.factoryId
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: factory.factoryId ==
                          _selectedFactory?.factoryId
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  child: const Icon(Icons.factory_outlined, size: 18),
                ),
                title: Text(factory.factoryName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (factory.factoryId == _selectedFactory?.factoryId)
                      Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        Navigator.pop(context);
                        if (value == 'rename') {
                          _renameFactory(factory);
                        } else if (value == 'settings') {
                          _editFactoryDetails(factory);
                        } else if (value == 'delete') {
                          _deleteFactory(factory);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'settings',
                          child: Text('Edit details'),
                        ),
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
            const Divider(height: 1),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabLabels = [
      l10n.tabHome,
      l10n.tabCapacity,
      l10n.tabStock,
      l10n.tabSupply,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedFactory?.factoryName ?? l10n.appTitle,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My profile',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.factory_outlined),
            tooltip: l10n.homeSwitchFactory,
            onPressed: _loadState == _LoadState.ready ? _pickFactory : null,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.homeShareReport,
            onPressed:
                (_loadState == _LoadState.ready && _selectedFactory != null)
                ? _shareReport
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.homeAbout,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.homeSignOut,
            onPressed: _signOut,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() {
          _tabIndex = index;
          _visitedTabs.add(index);
          _bottleneckRefreshTick++;
        }),
        destinations: [
          for (var i = 0; i < tabLabels.length; i++)
            NavigationDestination(
              icon: Icon(_tabIcons[i]),
              label: tabLabels[i],
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadState == _LoadState.loading) {
      return const LoadingIndicator();
    }
    if (_loadState == _LoadState.error) {
      return ErrorState(
        message: 'Could not load factory data.',
        onRetry: _loadFactories,
      );
    }
    if (_selectedFactory == null) {
      return EmptyState(
        icon: Icons.factory_outlined,
        title: 'No factory set up yet',
        subtitle: 'Create a factory to start tracking capacity, stock and supply.',
        actionLabel: 'Create factory',
        onAction: _isSeeding ? null : _createFactory,
        secondaryActionLabel: 'Load demo data',
        onSecondaryAction: _isSeeding ? null : _loadDemoData,
        secondaryActionLoading: _isSeeding,
      );
    }

    // The banner is handed to each tab to render as the first item in its
    // own scrollable list (see _buildTabContent) rather than pinned here as
    // a fixed sibling — it should scroll away with the rest of the content,
    // not permanently occupy screen space above it.
    return _buildTabContent();
  }

  // IndexedStack keeps every visited tab's widget (and its State — loaded
  // data, scroll position, in-progress filters) alive underneath the visible
  // one, so switching tabs is instant and never re-fetches. A tab that
  // hasn't been opened yet renders nothing instead of eagerly loading its
  // data at startup. Keys include the factory id so switching factories
  // still forces each tab to load fresh, correctly-scoped data.
  // Re-keyed by _bottleneckRefreshTick so the (cheap, single-RPC) banner
  // still refreshes on every tab visit, even though the surrounding tab's
  // own (heavier) data stays cached across switches via IndexedStack above.
  // padding: zero because it's embedded as the first item of a list that
  // already applies its own padding — see CapacityDashboardScreen /
  // StockDashboardScreen / MaterialListScreen's bottleneckBanner param.
  Widget _bottleneckBanner(int factoryId) {
    return BottleneckBanner(
      key: ValueKey('banner-$factoryId-$_bottleneckRefreshTick'),
      factoryId: factoryId,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildTabContent() {
    final factory = _selectedFactory!;
    return IndexedStack(
      index: _tabIndex,
      children: [
        _visitedTabs.contains(0)
            ? DashboardHomeScreen(
                key: ValueKey('home-${factory.factoryId}'),
                factory: factory,
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(1)
            ? CapacityDashboardScreen(
                key: ValueKey('capacity-${factory.factoryId}'),
                factory: factory,
                bottleneckBanner: _bottleneckBanner(factory.factoryId),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(2)
            ? StockDashboardScreen(
                key: ValueKey('stock-${factory.factoryId}'),
                factoryId: factory.factoryId,
                bottleneckBanner: _bottleneckBanner(factory.factoryId),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(3)
            ? MaterialListScreen(
                key: ValueKey('supply-${factory.factoryId}'),
                factoryId: factory.factoryId,
                bottleneckBanner: _bottleneckBanner(factory.factoryId),
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}
