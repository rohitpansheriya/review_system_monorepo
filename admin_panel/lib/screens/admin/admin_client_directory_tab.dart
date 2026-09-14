// lib/screens/admin/admin_client_directory_tab.dart
//
// Client & Location Directory (CRM) Tab for Platform Admin.
// Replaces the old Subscription Overrides tab with a clean, searchable
// master list of all enrolled businesses.
//
// Features:
//   - 4 KPI metric cards (Businesses, Branches, Active, Cities)
//   - Instant client-side search across brand, owner, phone, city, employee
//   - Filter by subscription status and enrolled-by employee
//   - Responsive DataTable (desktop) / Card list (mobile)
//   - 1-click drill-down to BusinessDetailScreen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/business_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_kpi_card.dart';
import '../../widgets/app_search_bar.dart';

class AdminClientDirectoryTab extends StatefulWidget {
  const AdminClientDirectoryTab({super.key});

  @override
  State<AdminClientDirectoryTab> createState() => _AdminClientDirectoryTabState();
}

class _AdminClientDirectoryTabState extends State<AdminClientDirectoryTab> {
  String _searchQuery = '';
  String _statusFilter = 'all';
  String _enrolledByFilter = 'all';
  String _sortField = 'createdAt';
  bool _sortAscending = false;

  // ── City extraction helper ──────────────────────────────────────────────────
  /// 3-Tier Intelligent City Recognition for Indian Addresses:
  ///   Tier 1: Direct exact match against known Indian cities (e.g. "Surat", "Ahmedabad", "Mumbai")
  ///   Tier 2: Sub-locality / area mapping (e.g. "Adajan", "Vesu", "Varachha" → "Surat")
  ///   Tier 3: Dynamic postal segment parser (strips PIN codes, Country, State/UT names)
  String _extractCity(AdminDashboardProvider provider, BusinessModel biz) {
    final branches = provider.businessBranches[biz.id];
    if (branches == null || branches.isEmpty) return '—';
    final rawAddress = branches.first.address;
    if (rawAddress.isEmpty) return '—';

    return _parseCityFromAddress(rawAddress);
  }

  // ── Tier 1: Major Indian Cities ─────────────────────────────────────────────
  static const List<String> _knownIndianCities = [
    // Gujarat
    'Surat', 'Ahmedabad', 'Vadodara', 'Baroda', 'Rajkot', 'Gandhinagar',
    'Bhavnagar', 'Jamnagar', 'Junagadh', 'Navsari', 'Valsad', 'Vapi',
    'Bharuch', 'Ankleshwar', 'Morbi', 'Anand', 'Nadiad', 'Godhra',
    'Dahod', 'Porbandar', 'Surendranagar', 'Amreli', 'Veraval', 'Somnath',
    'Dwarka', 'Bhuj', 'Gandhidham', 'Bardoli', 'Mehsana', 'Patan',
    'Palanpur', 'Himmatnagar', 'Modasa', 'Botad', 'Keshod', 'Vyara',
    'Bilimora', 'Silvassa', 'Daman', 'Diu',
    // Maharashtra
    'Mumbai', 'Pune', 'Nagpur', 'Thane', 'Nashik', 'Navi Mumbai',
    'Aurangabad', 'Chhatrapati Sambhajinagar', 'Solapur', 'Kolhapur',
    // National & Metro
    'Delhi', 'New Delhi', 'Noida', 'Gurugram', 'Gurgaon', 'Faridabad',
    'Bengaluru', 'Bangalore', 'Hyderabad', 'Chennai', 'Kolkata',
    'Jaipur', 'Indore', 'Bhopal', 'Chandigarh', 'Lucknow', 'Kanpur',
    'Patna', 'Varanasi', 'Agra', 'Kochi', 'Coimbatore', 'Goa',
  ];

  // ── Tier 2: Well-known Sub-localities & Areas mapped to Parent City ─────────
  static const Map<String, String> _subLocalityToCity = {
    // Surat areas
    'adajan': 'Surat',
    'varachha': 'Surat',
    'vesu': 'Surat',
    'katargam': 'Surat',
    'althan': 'Surat',
    'bhatar': 'Surat',
    'nanpura': 'Surat',
    'pal': 'Surat',
    'palanpur': 'Surat',
    'rander': 'Surat',
    'piplod': 'Surat',
    'ghod dod': 'Surat',
    'city light': 'Surat',
    'udhna': 'Surat',
    'dindoli': 'Surat',
    'sachin': 'Surat',
    'amroli': 'Surat',
    'majura': 'Surat',
    'athwa': 'Surat',
    'athwalines': 'Surat',
    'puna gam': 'Surat',
    'mota varachha': 'Surat',
    'sarthana': 'Surat',
    'pandesara': 'Surat',
    'dumas': 'Surat',
    'hazira': 'Surat',
    'ichhapore': 'Surat',
    'jahangirpura': 'Surat',
    'ring road': 'Surat',
    // Ahmedabad areas
    'navrangpura': 'Ahmedabad',
    'satellite': 'Ahmedabad',
    'vastrapur': 'Ahmedabad',
    'bopal': 'Ahmedabad',
    'south bopal': 'Ahmedabad',
    'prahlad nagar': 'Ahmedabad',
    'maninagar': 'Ahmedabad',
    'chandkheda': 'Ahmedabad',
    'gota': 'Ahmedabad',
    'thaltej': 'Ahmedabad',
    'bodakdev': 'Ahmedabad',
    'naranpura': 'Ahmedabad',
    'paldi': 'Ahmedabad',
    'sg highway': 'Ahmedabad',
    'motera': 'Ahmedabad',
    'nikol': 'Ahmedabad',
    'naroda': 'Ahmedabad',
    // Vadodara areas
    'alkapuri': 'Vadodara',
    'akota': 'Vadodara',
    'gotri': 'Vadodara',
    'fatehgunj': 'Vadodara',
    'manjalpur': 'Vadodara',
    'karelibaug': 'Vadodara',
    'sayajigunj': 'Vadodara',
    'vasna': 'Vadodara',
    'atladara': 'Vadodara',
    // Rajkot areas
    'kalawad road': 'Rajkot',
    'yagnik road': 'Rajkot',
    '150 feet ring road': 'Rajkot',
    'kotecha': 'Rajkot',
    'mavdi': 'Rajkot',
    'university road': 'Rajkot',
    // Mumbai areas
    'andheri': 'Mumbai',
    'bandra': 'Mumbai',
    'borivali': 'Mumbai',
    'juhu': 'Mumbai',
    'goregaon': 'Mumbai',
    'malad': 'Mumbai',
    'kandivali': 'Mumbai',
    'dadar': 'Mumbai',
    'ghatkopar': 'Mumbai',
    'powai': 'Mumbai',
    'colaba': 'Mumbai',
    'worli': 'Mumbai',
  };

  // ── Indian States & Union Territories to filter out ────────────────────────
  static const Set<String> _indianStatesAndUTs = {
    'andhra pradesh', 'arunachal pradesh', 'assam', 'bihar', 'chhattisgarh',
    'goa', 'gujarat', 'haryana', 'himachal pradesh', 'jharkhand', 'karnataka',
    'kerala', 'madhya pradesh', 'maharashtra', 'manipur', 'meghalaya', 'mizoram',
    'nagaland', 'odisha', 'orissa', 'punjab', 'rajasthan', 'sikkim', 'tamil nadu',
    'telangana', 'tripura', 'uttar pradesh', 'uttarakhand', 'west bengal',
    'delhi', 'new delhi', 'chandigarh', 'puducherry', 'pondicherry', 'ladakh',
    'jammu and kashmir', 'jammu & kashmir', 'daman and diu', 'dadra and nagar haveli',
  };

  static String _parseCityFromAddress(String rawAddress) {
    if (rawAddress.trim().isEmpty) return '—';

    // ── Tier 1: Check for exact city mention anywhere in address ─────────────
    for (final city in _knownIndianCities) {
      final cityPattern = RegExp('\\b${RegExp.escape(city)}\\b', caseSensitive: false);
      if (cityPattern.hasMatch(rawAddress)) {
        return city == 'Baroda' ? 'Vadodara' : city;
      }
    }

    // ── Tier 2: Check for sub-locality / area match ──────────────────────────
    final addressLower = rawAddress.toLowerCase();
    for (final entry in _subLocalityToCity.entries) {
      final areaPattern = RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false);
      if (areaPattern.hasMatch(addressLower)) {
        return entry.value;
      }
    }

    // ── Tier 3: Dynamic segment parser (fallback) ────────────────────────────
    final parts = rawAddress
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    for (int i = parts.length - 1; i >= 0; i--) {
      String seg = parts[i];

      // Remove country
      if (seg.toLowerCase() == 'india' || seg.toLowerCase() == 'in') continue;

      // Remove 6-digit pin codes and numbers/hyphens
      seg = seg.replaceAll(RegExp(r'\b\d{6}\b'), '');
      seg = seg.replaceAll(RegExp(r'\b\d{3}\s*\d{3}\b'), '');
      seg = seg.replaceAll(RegExp(r'[\d\-\(\)\.]+'), ' ').trim();

      if (seg.isEmpty) continue;

      final lower = seg.toLowerCase();

      // Skip if it's solely a state/UT name
      if (_indianStatesAndUTs.contains(lower)) continue;

      // If segment has state attached (e.g. "Surat Gujarat"), strip the state
      for (final state in _indianStatesAndUTs) {
        if (lower.endsWith(state) && lower.length > state.length) {
          seg = seg.substring(0, seg.length - state.length).trim();
          break;
        }
      }

      final cleanedLower = seg.toLowerCase();
      if (seg.isNotEmpty && !_indianStatesAndUTs.contains(cleanedLower)) {
        return seg.split(RegExp(r'\s+')).map((w) {
          if (w.isEmpty) return '';
          return w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : '');
        }).join(' ').trim();
      }
    }

    return '—';
  }

  // ── Filtering logic ─────────────────────────────────────────────────────────
  List<BusinessModel> _filteredBusinesses(AdminDashboardProvider provider) {
    var list = provider.allBusinesses.toList();

    // Status filter
    if (_statusFilter != 'all') {
      list = list.where((b) => b.subscriptionStatus == _statusFilter).toList();
    }

    // Enrolled-by filter
    if (_enrolledByFilter != 'all') {
      if (_enrolledByFilter == 'admin') {
        list = list.where((b) =>
            provider.isAdminUid(b.enrolledBy) ||
            provider.isAdminUid(b.currentlyManagedBy)
        ).toList();
      } else {
        list = list.where((b) =>
            b.enrolledBy == _enrolledByFilter ||
            b.currentlyManagedBy == _enrolledByFilter
        ).toList();
      }
    }

    // Search
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      final digitNeedle = _searchQuery.replaceAll(RegExp(r'[^0-9]'), '');

      list = list.where((b) {
        if (b.businessCode?.toLowerCase().contains(q) == true) return true;
        if (b.brandName.toLowerCase().contains(q)) return true;
        if (b.ownerName?.toLowerCase().contains(q) == true) return true;
        if (b.categoryType.toLowerCase().contains(q) == true) return true;

        // Phone search (digits only)
        if (digitNeedle.length >= 3) {
          final phone = (b.ownerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
          if (phone.contains(digitNeedle)) return true;
        }

        // City search
        final city = _extractCity(provider, b).toLowerCase();
        if (city.contains(q)) return true;

        // Employee name search
        final empName = provider.resolveEmployeeName(b.enrolledBy).toLowerCase();
        if (empName.contains(q)) return true;

        return false;
      }).toList();
    }

    // Sorting
    list.sort((a, b) {
      int cmp = 0;
      switch (_sortField) {
        case 'brandName':
          cmp = a.brandName.toLowerCase().compareTo(b.brandName.toLowerCase());
          break;
        case 'status':
          cmp = a.subscriptionStatus.compareTo(b.subscriptionStatus);
          break;
        case 'renewalDate':
          final aDate = a.renewalDate ?? DateTime(2000);
          final bDate = b.renewalDate ?? DateTime(2000);
          cmp = aDate.compareTo(bDate);
          break;
        case 'createdAt':
        default:
          final aDate = a.createdAt ?? DateTime(2000);
          final bDate = b.createdAt ?? DateTime(2000);
          cmp = aDate.compareTo(bDate);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return list;
  }

  void _onSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final filtered = _filteredBusinesses(provider);

    // Compute KPI values
    final totalBusinesses = provider.allBusinesses.length;
    final activeBusinesses = provider.allBusinesses
        .where((b) => b.subscriptionStatus == AppConstants.statusActive)
        .length;
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Client & Location Directory',
                      style: (isMobile ? theme.textTheme.titleLarge : theme.textTheme.headlineMedium)?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Master list of all enrolled businesses. Search, filter, and open any business workspace.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => provider.fetchAllBusinesses(),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Directory',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── KPI Summary Cards ─────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 900
                  ? 4
                  : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                childAspectRatio: constraints.maxWidth > 900 ? 1.5 : (constraints.maxWidth > 600 ? 1.7 : 2.6),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  AppKpiCard(
                    icon: Icons.business_rounded,
                    label: 'Total Brands',
                    value: '$totalBusinesses',
                    color: AppColors.primary,
                    compact: constraints.maxWidth <= 600,
                  ),
                  AppKpiCard(
                    icon: Icons.check_circle_rounded,
                    label: 'Active Businesses',
                    value: '$activeBusinesses',
                    color: AppColors.activeFg,
                    compact: constraints.maxWidth <= 600,
                  ),
                  AppKpiCard(
                    icon: Icons.location_on_rounded,
                    label: 'Active Branches',
                    value: '${provider.businessBranchStats.values.fold<int>(0, (sum, s) => sum + s.active)}',
                    color: AppColors.secondary,
                    compact: constraints.maxWidth <= 600,
                  ),
                  AppKpiCard(
                    icon: Icons.map_rounded,
                    label: 'Cities Covered',
                    value: '${(() {
                      final citySet = <String>{};
                      for (final biz in provider.allBusinesses) {
                        final city = _extractCity(provider, biz);
                        if (city != '—') citySet.add(city.toLowerCase());
                      }
                      return citySet.length;
                    })()}',
                    color: AppColors.star,
                    compact: constraints.maxWidth <= 600,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Search & Filter Bar ───────────────────────────────────────────
          _buildSearchFilterBar(provider, (() {
            final enrolledByUids = <String>{};
            bool hasAdmin = false;
            for (final biz in provider.allBusinesses) {
              if (biz.enrolledBy.isNotEmpty) {
                if (provider.isAdminUid(biz.enrolledBy)) {
                  hasAdmin = true;
                } else {
                  enrolledByUids.add(biz.enrolledBy);
                }
              }
            }
            final items = <String, String>{
              'all': 'All Agents',
            };
            if (hasAdmin || provider.allBusinesses.any((b) => provider.isAdminUid(b.enrolledBy))) {
              items['admin'] = 'Admin (Direct)';
            }
            for (final uid in enrolledByUids) {
              items[uid] = provider.resolveEmployeeName(uid);
            }
            return items;
          })(), theme, colorScheme),
          const SizedBox(height: 8),

          // ── Results count ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              '${filtered.length} business${filtered.length == 1 ? '' : 'es'} found',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // ── Data Table (desktop) or Card List (mobile) ────────────────────
          if (isDesktop)
            _buildDesktopTable(provider, filtered, theme, colorScheme)
          else
            _buildMobileCardList(provider, filtered, theme, colorScheme),
        ],
      ),
    );
  }

  // ── Search & Filter Bar Widget ──────────────────────────────────────────────
  Widget _buildSearchFilterBar(
    AdminDashboardProvider provider,
    Map<String, String> enrolledByItems,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search field
        AppSearchBar(
          width: MediaQuery.of(context).size.width > 500 ? 320 : double.infinity,
          hintText: 'Search brand, phone, city, agent…',
          initialValue: _searchQuery,
          onChanged: (v) => setState(() => _searchQuery = v),
        ),

        // Status filter
        _buildFilterDropdown<String>(
          value: _statusFilter,
          icon: Icons.filter_list_rounded,
          items: const {
            'all': 'All Statuses',
            'active': '🟢 Active',
            'grace_period': '🟡 Grace Period',
            'suspended': '🔴 Suspended / Lapsed',
            'deleted': '⚫ Deleted',
            'pending_payment': '🟠 Pending Payment',
          },
          onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
        ),

        // Enrolled-by filter
        _buildFilterDropdown<String>(
          value: enrolledByItems.containsKey(_enrolledByFilter) ? _enrolledByFilter : 'all',
          icon: Icons.person_search_rounded,
          items: enrolledByItems,
          onChanged: (v) => setState(() => _enrolledByFilter = v ?? 'all'),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required IconData icon,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00458B).withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(14),
            elevation: 8,
            icon: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            isDense: true,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            items: items.entries
                .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ── Desktop DataTable ───────────────────────────────────────────────────────
  Widget _buildDesktopTable(
    AdminDashboardProvider provider,
    List<BusinessModel> businesses,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (businesses.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No businesses found',
        subtitle: _searchQuery.isNotEmpty || _statusFilter != 'all' || _enrolledByFilter != 'all'
            ? 'No businesses match the current filter or search criteria.'
            : 'No clients or businesses have been enrolled yet.',
        actionLabel: _searchQuery.isNotEmpty || _statusFilter != 'all' || _enrolledByFilter != 'all'
            ? 'Clear Filters'
            : null,
        onAction: _searchQuery.isNotEmpty || _statusFilter != 'all' || _enrolledByFilter != 'all'
            ? () {
                setState(() {
                  _searchQuery = '';
                  _statusFilter = 'all';
                  _enrolledByFilter = 'all';
                });
              }
            : null,
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          horizontalMargin: 20,
          columnSpacing: 24,
          columns: [
            DataColumn(
              label: const Text('Brand Name'),
              onSort: (_, __) => _onSort('brandName'),
            ),
            const DataColumn(label: Text('Category')),
            const DataColumn(label: Text('City')),
            const DataColumn(label: Text('Owner')),
            const DataColumn(label: Text('Enrolled By')),
            const DataColumn(label: Text('Branches'), numeric: true),
            DataColumn(
              label: const Text('Status'),
              onSort: (_, __) => _onSort('status'),
            ),
            DataColumn(
              label: const Text('Renewal'),
              onSort: (_, __) => _onSort('renewalDate'),
            ),
            DataColumn(
              label: const Text('Enrolled'),
              onSort: (_, __) => _onSort('createdAt'),
            ),
            const DataColumn(label: Text('Action')),
          ],
          rows: businesses.map((biz) {
            final branchStats = provider.businessBranchStats[biz.id];
            final branchCount = branchStats?.active ?? 0;
            final branchGrace = branchStats?.grace ?? 0;
            final branchSuspended = branchStats?.suspended ?? 0;
            final branchPending = branchStats?.pending ?? 0;
            final branchDeleted = branchStats?.deleted ?? 0;
            final branchInactive = branchPending + branchSuspended + branchDeleted;
            final totalBranches = branchStats?.total ?? 1;

            final city = _extractCity(provider, biz);
            final enrolledByName = provider.resolveEmployeeName(biz.enrolledBy);

            return DataRow(
              cells: [
                // Brand Name
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (biz.businessCode != null || biz.isTestAccount) ...[
                        AppBadge.code(
                          biz.displayCode,
                          isTest: biz.isTestAccount,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          biz.brandName,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Category
                DataCell(Text(
                  biz.categoryType.isNotEmpty ? biz.categoryType : '—',
                  style: theme.textTheme.bodySmall,
                )),
                // City
                DataCell(Text(city, style: theme.textTheme.bodySmall)),
                // Owner (name + phone)
                DataCell(_buildOwnerCell(biz, theme)),
                // Enrolled By
                DataCell(
                  InkWell(
                    onTap: () => _showQuickChangeEnrollerDialog(context, biz, enrolledByName),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              enrolledByName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 14,
                            color: colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Branch count
                DataCell(Center(
                  child: AppBadge.count(
                    label: totalBranches > 1 ? '$branchCount / $totalBranches' : '$branchCount',
                    color: branchGrace > 0
                        ? AppColors.graceFg
                        : (branchInactive > 0 ? AppColors.pendingFg : colorScheme.primary),
                    backgroundColor: branchGrace > 0
                        ? AppColors.graceBg
                        : (branchInactive > 0 ? AppColors.pendingBg : colorScheme.primaryContainer.withValues(alpha: 0.5)),
                  ),
                )),
                // Status pill with branch indicator
                DataCell(_buildStatusPill(
                  biz.subscriptionStatus,
                  theme,
                  activeBranches: branchCount,
                  graceBranches: branchGrace,
                  inactiveBranches: branchInactive,
                  totalBranches: totalBranches,
                )),
                // Renewal date
                DataCell(Text(
                  biz.renewalDate != null
                      ? DateFormat('d MMM yyyy').format(biz.renewalDate!)
                      : '—',
                  style: theme.textTheme.bodySmall,
                )),
                // Enrolled date
                DataCell(Text(
                  biz.createdAt != null
                      ? DateFormat('d MMM yyyy').format(biz.createdAt!)
                      : '—',
                  style: theme.textTheme.bodySmall,
                )),
                // Action
                DataCell(
                  TextButton.icon(
                    onPressed: () => context.push('/business/${biz.id}', extra: biz),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Owner cell with copy-to-clipboard ───────────────────────────────────────
  Widget _buildOwnerCell(BusinessModel biz, ThemeData theme) {
    final name = biz.ownerName ?? '—';
    final phone = biz.ownerPhone ?? '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        if (phone.isNotEmpty)
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: phone));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied: $phone'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_outlined, size: 12,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    phone,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 11,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Status pill widget ──────────────────────────────────────────────────────
  Widget _buildStatusPill(
    String status,
    ThemeData theme, {
    int activeBranches = 1,
    int graceBranches = 0,
    int inactiveBranches = 0,
    int totalBranches = 1,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBadge.subscription(status),
        if (graceBranches > 0) ...[
          const SizedBox(height: 4),
          AppBadge(
            label: '$graceBranches in Grace',
            backgroundColor: AppColors.graceBg,
            foregroundColor: AppColors.graceFg,
            icon: Icons.warning_amber_rounded,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ] else if (inactiveBranches > 0 && status == AppConstants.statusActive) ...[
          const SizedBox(height: 4),
          AppBadge(
            label: '$inactiveBranches Inactive',
            backgroundColor: AppColors.pendingBg,
            foregroundColor: AppColors.pendingFg,
            icon: Icons.info_outline,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ],
      ],
    );
  }

  // ── Mobile Card List ────────────────────────────────────────────────────────
  Widget _buildMobileCardList(
    AdminDashboardProvider provider,
    List<BusinessModel> businesses,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (businesses.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No businesses found',
        subtitle: _searchQuery.isNotEmpty || _statusFilter != 'all' || _enrolledByFilter != 'all'
            ? 'No businesses match the current filter or search criteria.'
            : 'No clients or businesses have been enrolled yet.',
        actionLabel: _searchQuery.isNotEmpty || _statusFilter != 'all' || _enrolledByFilter != 'all'
            ? 'Clear Filters'
            : null,
        onAction: _searchQuery.isNotEmpty || _statusFilter != 'all' || _enrolledByFilter != 'all'
            ? () {
                setState(() {
                  _searchQuery = '';
                  _statusFilter = 'all';
                  _enrolledByFilter = 'all';
                });
              }
            : null,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: businesses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final biz = businesses[index];
        final branchStats = provider.businessBranchStats[biz.id];
        final branchCount = branchStats?.active ?? 0;
        final branchGrace = branchStats?.grace ?? 0;
        final branchSuspended = branchStats?.suspended ?? 0;
        final branchPending = branchStats?.pending ?? 0;
        final branchDeleted = branchStats?.deleted ?? 0;
        final branchInactive = branchPending + branchSuspended + branchDeleted;
        final totalBranches = branchStats?.total ?? 1;

        final city = _extractCity(provider, biz);
        final enrolledByName = provider.resolveEmployeeName(biz.enrolledBy);

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.15)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => context.push('/business/${biz.id}', extra: biz),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Brand name + code badge + status pill
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (biz.businessCode != null || biz.isTestAccount) ...[
                        AppBadge.code(
                          biz.displayCode,
                          isTest: biz.isTestAccount,
                          fontSize: 10,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          biz.brandName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusPill(
                        biz.subscriptionStatus,
                        theme,
                        activeBranches: branchCount,
                        graceBranches: branchGrace,
                        inactiveBranches: branchInactive,
                        totalBranches: totalBranches,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 2: Category + City
                  Row(
                    children: [
                      if (biz.categoryType.isNotEmpty) ...[
                        Icon(Icons.category_outlined, size: 14,
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            biz.categoryType,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Icon(Icons.location_on_outlined, size: 14,
                          color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          city,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 3: Owner + Phone
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14,
                          color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        biz.ownerName ?? '—',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (biz.ownerPhone != null && biz.ownerPhone!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: biz.ownerPhone!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied: ${biz.ownerPhone}'),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Text(
                            biz.ownerPhone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Row 4: Metadata chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(
                        Icons.person_search_rounded,
                        enrolledByName,
                        colorScheme,
                        onTap: () => _showQuickChangeEnrollerDialog(context, biz, enrolledByName),
                      ),
                      _metaChip(Icons.storefront_rounded, '$branchCount branch${branchCount == 1 ? '' : 'es'}', colorScheme),
                      if (biz.createdAt != null)
                        _metaChip(Icons.calendar_today, DateFormat('d MMM yyyy').format(biz.createdAt!), colorScheme),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metaChip(
    IconData icon,
    String label,
    ColorScheme colorScheme, {
    VoidCallback? onTap,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.swap_horiz_rounded, size: 12, color: colorScheme.primary),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: chip,
      );
    }
    return chip;
  }

  Future<void> _showQuickChangeEnrollerDialog(
    BuildContext context,
    BusinessModel biz,
    String currentEnrolledByName,
  ) async {
    final provider = context.read<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final employees = provider.employees;

    String selectedEmployeeUid = provider.isAdminUid(biz.enrolledBy) ? 'admin' : biz.enrolledBy;
    String reason = '';

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isCurrent = selectedEmployeeUid == (provider.isAdminUid(biz.enrolledBy) ? 'admin' : biz.enrolledBy);

            return AppModalDialog(
              icon: Icons.swap_horiz_rounded,
              iconColor: AppColors.primary,
              title: 'Change Enrolled Employee',
              subtitle: 'Reassign which employee is credited for enrolling "${biz.brandName}".',
              maxWidth: 520,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 20, color: Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Currently Enrolled By', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text(
                                currentEnrolledByName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedEmployeeUid,
                    dropdownColor: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    elevation: 8,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    decoration: const InputDecoration(
                      labelText: 'Select New Enrolled Employee *',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'admin',
                        child: Text('Admin (Direct Enrollment / No Commission)'),
                      ),
                      ...employees
                          .where((emp) => !emp.isAdmin)
                          .map((emp) => DropdownMenuItem(
                            value: emp.uid,
                            child: Text(
                              '${emp.name} (${emp.email})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedEmployeeUid = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Reason for Reassignment (Optional)',
                      hintText: 'e.g. Territory reallocation or correction',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    onChanged: (val) => reason = val.trim(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Impact of change:\n'
                            '• Moves business to selected employee’s workspace.\n'
                            '• Removes it from previous employee’s view.\n'
                            '• Transferred pending commissions & enrollment counters.',
                            style: TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isCurrent
                      ? null
                      : () {
                          Navigator.of(ctx).pop(true);
                        },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirm Reassignment'),
                ),
              ],
            );
          },
        );
      },
    );

    if (success == true && context.mounted) {
      try {
        await provider.reassignBusinessEnroller(
          businessId: biz.id,
          newEmployeeId: selectedEmployeeUid,
          reason: reason.isNotEmpty ? reason : 'Admin reassignment from CRM',
        );

        if (context.mounted) {
          final newName = provider.resolveEmployeeName(selectedEmployeeUid);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Enrolled employee changed to "$newName" successfully.'),
              backgroundColor: AppColors.activeFg,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to reassign enrolled employee: $e'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      }
    }
  }
}
