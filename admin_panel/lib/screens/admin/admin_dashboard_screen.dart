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

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _tabKeys = [
    'stats',
    'leads',
    'enroll',
    'employees',
    'templates',
    'directory',
    'commission',
    'standees',
  ];

  int _selectedTabIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _applyTabKey(widget.initialTab);
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
    }
  }

  void _onTabSelected(int idx) {
    if (idx < 0 || idx >= _tabKeys.length) return;
    setState(() => _selectedTabIndex = idx);
    context.go('/admin?tab=${_tabKeys[idx]}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AppAuthProvider>();
    if (!_initialized && auth.isAdmin) {
      _initialized = true;
      context.read<AdminDashboardProvider>().loadAdminData();
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
        title: const Text('Platform Admin Dashboard'),
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
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.analytics_outlined),
                      selectedIcon: Icon(Icons.analytics),
                      label: Text('Stats'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.flash_on_outlined),
                      selectedIcon: Icon(Icons.flash_on, color: Color(0xFFF59E0B)),
                      label: Text('Leads'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.add_business_outlined),
                      selectedIcon: Icon(Icons.add_business),
                      label: Text('Enroll'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outlined),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Employees'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.library_books_outlined),
                      selectedIcon: Icon(Icons.library_books),
                      label: Text('Templates'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.store_mall_directory_outlined),
                      selectedIcon: Icon(Icons.store_mall_directory),
                      label: Text('Directory'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.verified_outlined),
                      selectedIcon: Icon(Icons.verified),
                      label: Text('Commission'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Standees'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: tabs[_selectedTabIndex]),
              ],
            )
          : tabs[_selectedTabIndex],
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedTabIndex,
              onTap: _onTabSelected,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: colorScheme.primary,
              unselectedItemColor: colorScheme.onSurfaceVariant,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'Stats'),
                BottomNavigationBarItem(icon: Icon(Icons.flash_on_outlined), label: 'Leads'),
                BottomNavigationBarItem(icon: Icon(Icons.add_business_outlined), label: 'Enroll'),
                BottomNavigationBarItem(icon: Icon(Icons.people_outlined), label: 'Employees'),
                BottomNavigationBarItem(icon: Icon(Icons.library_books_outlined), label: 'Templates'),
                BottomNavigationBarItem(icon: Icon(Icons.store_mall_directory_outlined), label: 'Directory'),
                BottomNavigationBarItem(icon: Icon(Icons.verified_outlined), label: 'Queue'),
                BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'Standees'),
              ],
            ),
    );
  }
}
