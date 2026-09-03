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
      list = list.where((b) =>
          b.enrolledBy == _enrolledByFilter ||
          b.currentlyManagedBy == _enrolledByFilter
      ).toList();
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
    final totalActiveBranches = provider.businessBranchStats.values
        .fold<int>(0, (sum, s) => sum + s.active);

    // Unique cities
    final citySet = <String>{};
    for (final biz in provider.allBusinesses) {
      final city = _extractCity(provider, biz);
      if (city != '—') citySet.add(city.toLowerCase());
    }

    // Unique enrolled-by employees for filter dropdown
    final enrolledByUids = <String>{};
    for (final biz in provider.allBusinesses) {
      if (biz.enrolledBy.isNotEmpty) enrolledByUids.add(biz.enrolledBy);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
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
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Master list of all enrolled businesses. Search, filter, and open any business workspace.',
                      style: theme.textTheme.bodyMedium?.copyWith(
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

          // ── KPI Metric Cards ──────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 800
                  ? 4
                  : (constraints.maxWidth > 500 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                childAspectRatio: 2.2,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _KpiCard(
                    icon: Icons.store_rounded,
                    label: 'Total Businesses',
                    value: '$totalBusinesses',
                    color: AppColors.primary,
                  ),
                  _KpiCard(
                    icon: Icons.check_circle_rounded,
                    label: 'Active Businesses',
                    value: '$activeBusinesses',
                    color: AppColors.activeFg,
                  ),
                  _KpiCard(
                    icon: Icons.location_on_rounded,
                    label: 'Active Branches',
                    value: '$totalActiveBranches',
                    color: AppColors.secondary,
                  ),
                  _KpiCard(
                    icon: Icons.map_rounded,
                    label: 'Cities Covered',
                    value: '${citySet.length}',
                    color: AppColors.star,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Search & Filter Bar ───────────────────────────────────────────
          _buildSearchFilterBar(provider, enrolledByUids, theme, colorScheme),
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
    Set<String> enrolledByUids,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search field
        SizedBox(
          width: 320,
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search brand, phone, city, agent…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ),

        // Status filter
        _buildFilterDropdown<String>(
          value: _statusFilter,
          icon: Icons.filter_list_rounded,
          items: const {
            'all': 'All Statuses',
            'active': '🟢 Active',
            'grace_period': '🟡 Grace Period',
            'deleted': '🔴 Expired / Lapsed',
            'pending_payment': '🟠 Pending Payment',
          },
          onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
        ),

        // Enrolled-by filter
        _buildFilterDropdown<String>(
          value: _enrolledByFilter,
          icon: Icons.person_search_rounded,
          items: {
            'all': 'All Agents',
            for (final uid in enrolledByUids)
              uid: provider.resolveEmployeeName(uid),
          },
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.15)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
            final branchPending = branchStats?.pending ?? 0;
            final branchDeleted = branchStats?.deleted ?? 0;
            final branchInactive = branchPending + branchDeleted;
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: biz.isTestAccount ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: biz.isTestAccount ? AppColors.warning : AppColors.primary.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            biz.displayCode,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: biz.isTestAccount ? AppColors.warning : AppColors.primary,
                            ),
                          ),
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
                DataCell(Text(
                  enrolledByName,
                  style: theme.textTheme.bodySmall,
                )),
                // Branch count
                DataCell(Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: branchGrace > 0
                          ? AppColors.graceBg
                          : (branchInactive > 0 ? AppColors.pendingBg : colorScheme.primaryContainer.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      totalBranches > 1 ? '$branchCount / $totalBranches' : '$branchCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: branchGrace > 0
                            ? AppColors.graceFg
                            : (branchInactive > 0 ? AppColors.pendingFg : colorScheme.onPrimaryContainer),
                      ),
                    ),
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
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case AppConstants.statusActive:
        bg = AppColors.activeBg;
        fg = AppColors.activeFg;
        label = 'Active';
        break;
      case AppConstants.statusGracePeriod:
        bg = AppColors.graceBg;
        fg = AppColors.graceFg;
        label = 'Grace';
        break;
      case AppConstants.statusDeleted:
        bg = AppColors.deletedBg;
        fg = AppColors.deletedFg;
        label = 'Lapsed';
        break;
      case AppConstants.statusPendingPayment:
        bg = AppColors.pendingBg;
        fg = AppColors.pendingFg;
        label = 'Pending';
        break;
      default:
        bg = AppColors.deletedBg;
        fg = AppColors.deletedFg;
        label = status;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (graceBranches > 0) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.graceBg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.graceFg.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 11, color: AppColors.graceFg),
                const SizedBox(width: 3),
                Text(
                  '$graceBranches in Grace',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.graceFg,
                  ),
                ),
              ],
            ),
          ),
        ] else if (inactiveBranches > 0 && status == AppConstants.statusActive) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.pendingBg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.pendingFg.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 11, color: AppColors.pendingFg),
                const SizedBox(width: 3),
                Text(
                  '$inactiveBranches Inactive',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.pendingFg,
                  ),
                ),
              ],
            ),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, size: 56, color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text(
                'No businesses match your search.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
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
        final branchPending = branchStats?.pending ?? 0;
        final branchDeleted = branchStats?.deleted ?? 0;
        final branchInactive = branchPending + branchDeleted;
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: biz.isTestAccount ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: biz.isTestAccount ? AppColors.warning : AppColors.primary.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            biz.displayCode,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: biz.isTestAccount ? AppColors.warning : AppColors.primary,
                            ),
                          ),
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
                      _metaChip(Icons.person_search_rounded, enrolledByName, colorScheme),
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

  Widget _metaChip(IconData icon, String label, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
        ],
      ),
    );
  }
}

// ── KPI Card Widget ──────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
