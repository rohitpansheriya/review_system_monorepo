// lib/screens/owner/owner_dashboard_screen.dart
//
// Main Owner Dashboard Scaffold for role=owner.
// Integrates NavigationRail / BottomNavigationBar with 5 tabs:
//   1. Home (Pre-aggregated stats & renewal banners)
//   2. Categories (Category management & active toggles)
//   3. Star Routing (Star-routing table & immediate updates)
//   4. Renewal (₹999 Razorpay checkout & subscription status)
//   5. Reply to Reviews (Phase 2 Stub — Google Business Profile API)
//
// SUBSCRIPTION STATE GATING:
// - deleted: shows "Your subscription has lapsed and data was removed — contact us to re-enroll"
// - pending_payment: shows pending enrollment notice
// - grace_period: full dashboard usable, category editing read-only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_dashboard_provider.dart';
import '../../core/logout_helper.dart';
import 'owner_home_tab.dart';
import 'owner_categories_tab.dart';
import 'owner_star_routing_tab.dart';
import 'owner_renewal_tab.dart';
import 'google_reply_stub_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _selectedTabIndex = 0;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final auth = context.read<AppAuthProvider>();
      if (auth.uid != null) {
        context.read<OwnerDashboardProvider>().loadOwnerData(auth.uid!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final provider = context.watch<OwnerDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (provider.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Owner Dashboard'),
          actions: [_buildLogoutButton(context)],
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
                    if (auth.uid != null) {
                      provider.loadOwnerData(auth.uid!);
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Gating: Deleted Business ──────────────────────────────────────────────
    if (provider.isDeleted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Account Lapsed'),
          actions: [_buildLogoutButton(context)],
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(32.0),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_off, size: 64, color: colorScheme.error),
                    const SizedBox(height: 20),
                    Text(
                      'Subscription Lapsed',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your subscription has lapsed and data was removed — contact us to re-enroll.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => confirmAndSignOut(context),
                      icon: const Icon(Icons.logout),
                      label: const Text('Log Out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Widget pendingBanner = provider.isPendingPayment
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: colorScheme.errorContainer,
            child: Row(
              children: [
                Icon(Icons.pending_actions, color: colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '⚠️ Account Pending Activation — Payment / Cash collected is awaiting Admin verification. Standee & Review System will activate automatically once verified.',
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: colorScheme.onErrorContainer),
                  tooltip: 'Check Status',
                  onPressed: () {
                    if (auth.uid != null) {
                      provider.loadOwnerData(auth.uid!);
                    }
                  },
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    // ── Active / Grace Period Dashboard Views ─────────────────────────────────
    final tabs = [
      const OwnerHomeTab(),
      const OwnerCategoriesTab(),
      const OwnerStarRoutingTab(),
      const OwnerRenewalTab(),
      const GoogleReplyStubScreen(),
    ];

    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.business?.brandName ?? 'Owner Dashboard'),
        actions: [_buildLogoutButton(context)],
      ),
      body: Column(
        children: [
          pendingBanner,
          Expanded(
            child: isDesktop
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _selectedTabIndex,
                        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
                        labelType: NavigationRailLabelType.all,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            selectedIcon: Icon(Icons.dashboard),
                            label: Text('Dashboard'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.category_outlined),
                            selectedIcon: Icon(Icons.category),
                            label: Text('Categories'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.star_outline),
                            selectedIcon: Icon(Icons.star),
                            label: Text('Star Routing'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.payment_outlined),
                            selectedIcon: Icon(Icons.payment),
                            label: Text('Renewal'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.rate_review_outlined),
                            selectedIcon: Icon(Icons.rate_review),
                            label: Text('Google Reply'),
                          ),
                        ],
                      ),
                      const VerticalDivider(thickness: 1, width: 1),
                      Expanded(child: tabs[_selectedTabIndex]),
                    ],
                  )
                : tabs[_selectedTabIndex],
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : BottomNavigationBar(
              currentIndex: _selectedTabIndex,
              onTap: (idx) => setState(() => _selectedTabIndex = idx),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: colorScheme.primary,
              unselectedItemColor: colorScheme.onSurfaceVariant,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.category_outlined),
                  label: 'Categories',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.star_outline),
                  label: 'Routing',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.payment_outlined),
                  label: 'Renewal',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.rate_review_outlined),
                  label: 'Reply',
                ),
              ],
            ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Log out',
      onPressed: () => confirmAndSignOut(context),
    );
  }
}
