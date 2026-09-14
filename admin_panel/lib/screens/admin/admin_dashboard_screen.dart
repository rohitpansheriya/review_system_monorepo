// lib/screens/admin/admin_dashboard_screen.dart
//
// Main Platform Admin Dashboard Shell (Doc 04 Admin Panel).
// Supports NavigationRail / BottomNavigationBar with 6 admin tabs:
//   1. Platform Stats (count() aggregations, revenue snapshot, renewal windows)
//   2. Enroll Business Directly (Reuses 03 EnrollScreen with no restrictions)
//   3. Employee Management (Create, metrics, offboarding bulk-reassign, KYC verification)
//   4. Category Template Library (Doc 07 CRUD UI, phrase pools, versions)
//   5. Subscription Overrides (Manual grace extend, reactivation, audit log)
//   6. Commission Verification Queue (Two-step cash gate, mark paid)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/logout_helper.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/auth_provider.dart';
import '../enroll/enroll_screen.dart';
import '../../widgets/app_animated_loader.dart';
import '../../widgets/app_brand_title.dart';
import '../../widgets/app_splash_screen.dart';
import 'admin_platform_stats_tab.dart';
import 'admin_employees_tab.dart';
import 'admin_templates_tab.dart';
import 'admin_client_directory_tab.dart';
import 'admin_commission_queue_screen.dart';
import 'admin_standee_tab.dart';
import 'admin_leads_tab.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String? initialTab;
  const AdminDashboardScreen({super.key, this.initialTab});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminNavDestination {
  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Color? selectedIconColor;

  const _AdminNavDestination({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.selectedIconColor,
  });
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _destinations = [
    _AdminNavDestination(
      key: 'stats',
      label: 'Stats',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
    ),
    _AdminNavDestination(
      key: 'leads',
      label: 'Leads',
      icon: Icons.flash_on_outlined,
      selectedIcon: Icons.flash_on,
      selectedIconColor: Color(0xFFF59E0B),
    ),
    _AdminNavDestination(
      key: 'enroll',
      label: 'Enroll',
      icon: Icons.add_business_outlined,
      selectedIcon: Icons.add_business,
    ),
    _AdminNavDestination(
      key: 'employees',
      label: 'Employees',
      icon: Icons.people_outlined,
      selectedIcon: Icons.people,
    ),
    _AdminNavDestination(
      key: 'templates',
      label: 'Templates',
      icon: Icons.library_books_outlined,
      selectedIcon: Icons.library_books,
    ),
    _AdminNavDestination(
      key: 'directory',
      label: 'Directory',
      icon: Icons.store_mall_directory_outlined,
      selectedIcon: Icons.store_mall_directory,
    ),
    _AdminNavDestination(
      key: 'commission',
      label: 'Commission',
      icon: Icons.verified_outlined,
      selectedIcon: Icons.verified,
    ),
    _AdminNavDestination(
      key: 'standees',
      label: 'Standees',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
  ];

  static List<String> get _tabKeys => _destinations.map((d) => d.key).toList();

  final ScrollController _bottomNavScrollController = ScrollController();
  int _selectedTabIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _applyTabKey(widget.initialTab);
  }

  @override
  void dispose() {
    _bottomNavScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AdminDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _applyTabKey(widget.initialTab);
    }
  }

  void _applyTabKey(String? key) {
    if (key == null || key.trim().isEmpty) return;
    final idx = _tabKeys.indexOf(key.trim().toLowerCase());
    if (idx != -1) {
      _selectedTabIndex = idx;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveTab());
    }
  }

  void _onTabSelected(int idx) {
    if (idx < 0 || idx >= _destinations.length) return;
    setState(() => _selectedTabIndex = idx);
    _scrollToActiveTab();
    context.go('/admin?tab=${_destinations[idx].key}');
  }

  void _scrollToActiveTab() {
    if (!_bottomNavScrollController.hasClients) return;
    final targetOffset = (_selectedTabIndex * 80.0) - 80.0;
    _bottomNavScrollController.animateTo(
      targetOffset.clamp(0.0, _bottomNavScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AppAuthProvider>(context);
    final provider = Provider.of<AdminDashboardProvider>(context, listen: false);
    if (auth.isAdmin) {
      if (!_initialized) {
        _initialized = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            provider.loadAdminData();
          }
        });
      } else if (!provider.loading && provider.allBusinesses.isEmpty && provider.employees.isEmpty && provider.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            provider.loadAdminData();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (auth.status == AuthStatus.unknown || auth.loading) {
      return const AppSplashScreen(message: 'Authenticating…');
    }

    if (!auth.isAdmin) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gpp_maybe, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Access Denied: Admin role required.',
                style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => confirmAndSignOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Log Out'),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.loading) {
      return const Scaffold(
        body: AppAnimatedLoader.fullScreen(
          message: 'Loading Platform Metrics & Directory…',
        ),
      );
    }

    if (provider.error != null && provider.allBusinesses.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const AppBrandTitle(subtitle: 'Admin Panel'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: () => confirmAndSignOut(context),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  provider.error!,
                  style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<AdminDashboardProvider>().loadAdminData(forceReload: true);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Loading Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tabs = [
      const AdminPlatformStatsTab(),
      const AdminLeadsTab(),
      const EnrollScreen(), // Reused directly per 04
      const AdminEmployeesTab(),
      const AdminTemplatesTab(),
      const AdminClientDirectoryTab(),
      const AdminCommissionQueueScreen(),
      const AdminStandeeTab(),
    ];

    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle(subtitle: 'Admin Panel'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Chip(
                avatar: const Icon(Icons.admin_panel_settings, size: 16),
                label: Text(auth.user?.email ?? 'Admin'),
                backgroundColor: colorScheme.primaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => confirmAndSignOut(context),
          ),
        ],
      ),
      body: isDesktop
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedTabIndex,
                  onDestinationSelected: _onTabSelected,
                  labelType: NavigationRailLabelType.all,
                  destinations: _destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon, color: d.selectedIconColor),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: tabs,
                  ),
                ),
              ],
            )
          : IndexedStack(
              index: _selectedTabIndex,
              children: tabs,
            ),
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(context, colorScheme),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00458B).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: SingleChildScrollView(
            controller: _bottomNavScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_destinations.length, (idx) {
                final dest = _destinations[idx];
                final isSelected = _selectedTabIndex == idx;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => _onTabSelected(idx),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected ? dest.selectedIcon : dest.icon,
                              size: 22,
                              color: isSelected
                                  ? (dest.selectedIconColor ?? colorScheme.primary)
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dest.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
