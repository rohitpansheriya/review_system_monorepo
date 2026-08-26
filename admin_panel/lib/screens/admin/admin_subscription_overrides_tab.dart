// lib/screens/admin/admin_subscription_overrides_tab.dart
//
// All Businesses + Subscription Overrides Tab for Platform Admin.
// Features:
//   - Filter by status (All / Active / Pending / Grace / Deleted)
//   - Filter by date range (created_at)
//   - Shows enrolled_by and created_at in the list
//   - Edit Business dialog for brand, category, owner details
//   - Override Subscription dialog for status, renewal, grace period

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/business_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/auth_provider.dart';

class AdminSubscriptionOverridesTab extends StatefulWidget {
  const AdminSubscriptionOverridesTab({super.key});

  @override
  State<AdminSubscriptionOverridesTab> createState() =>
      _AdminSubscriptionOverridesTabState();
}

class _AdminSubscriptionOverridesTabState
    extends State<AdminSubscriptionOverridesTab> {
  String _statusFilter = 'all';
  DateTimeRange? _dateRange;
  String _mobileSearch = '';  // GROUP D3: mobile number filter
  int? _monthFilter;           // GROUP D3: month filter (1-12)
  int? _yearFilter;            // GROUP D3: year filter
  String? _enrolledByFilter;   // null = All, 'admin' = Admin (Direct), emp.uid = Employee

  List<BusinessModel> _filtered(
    List<BusinessModel> businesses,
    AdminDashboardProvider provider,
  ) {
    var list = businesses;
    if (_statusFilter != 'all') {
      list = list.where((b) => b.subscriptionStatus == _statusFilter).toList();
    }
    if (_dateRange != null) {
      list = list.where((b) {
        if (b.createdAt == null) return false;
        return !b.createdAt!.isBefore(_dateRange!.start) &&
            !b.createdAt!.isAfter(
                _dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }
    // GROUP D3: Month filter
    if (_monthFilter != null && _yearFilter != null) {
      list = list.where((b) {
        if (b.createdAt == null) return false;
        return b.createdAt!.month == _monthFilter &&
               b.createdAt!.year == _yearFilter;
      }).toList();
    }
    // Enrolled by filter (Admin Direct vs Specific Employee)
    if (_enrolledByFilter != null) {
      if (_enrolledByFilter == 'admin') {
        list = list.where((b) {
          final isEmp = provider.employees.any((e) => e.uid == b.enrolledBy);
          return !isEmp || b.enrolledBy.isEmpty || b.enrolledBy == 'admin';
        }).toList();
      } else {
        list = list.where((b) => b.enrolledBy == _enrolledByFilter).toList();
      }
    }
    // Mobile number & keyword search
    if (_mobileSearch.trim().isNotEmpty) {
      final needle = _mobileSearch.trim().toLowerCase();
      final digitNeedle = _mobileSearch.replaceAll(RegExp(r'[^0-9]'), '');
      list = list.where((b) {
        final phoneDigits = (b.ownerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        final rawPhone = (b.ownerPhone ?? '').toLowerCase();
        final brand = b.brandName.toLowerCase();
        final owner = (b.ownerName ?? '').toLowerCase();
        final email = (b.ownerEmail ?? '').toLowerCase();

        final matchesDigits = digitNeedle.isNotEmpty && phoneDigits.contains(digitNeedle);
        final matchesRawPhone = rawPhone.contains(needle);
        final matchesText = brand.contains(needle) || owner.contains(needle) || email.contains(needle);

        return matchesDigits || matchesRawPhone || matchesText;
      }).toList();
    }
    return list;
  }

  void _showEditBusinessDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    BusinessModel biz,
  ) {
    final brandCtrl = TextEditingController(text: biz.brandName);
    final catCtrl = TextEditingController(text: biz.categoryType);
    final nameCtrl = TextEditingController(text: biz.ownerName ?? '');
    final emailCtrl = TextEditingController(text: biz.ownerEmail ?? '');
    final phoneCtrl = TextEditingController(text: biz.ownerPhone ?? '');
    String status = biz.subscriptionStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Edit Business — ${biz.brandName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: brandCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Brand Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: catCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Category Type'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Owner Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Owner Email *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Owner Phone *'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(
                      labelText: 'Subscription Status'),
                  items: const [
                    DropdownMenuItem(
                        value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'grace_period',
                        child: Text('Grace Period')),
                    DropdownMenuItem(
                        value: 'pending_payment',
                        child: Text('Pending Payment')),
                    DropdownMenuItem(
                        value: 'deleted', child: Text('Deleted')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlg(() => status = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await provider.updateBusinessDetailsAdmin(
                  businessId: biz.id,
                  brandName: brandCtrl.text.trim(),
                  categoryType: catCtrl.text.trim(),
                  ownerName: nameCtrl.text.trim(),
                  ownerEmail: emailCtrl.text.trim(),
                  ownerPhone: phoneCtrl.text.trim(),
                  subscriptionStatus: status,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('${biz.brandName} updated successfully.')),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOverrideDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    BusinessModel biz,
    String adminUid,
  ) {
    String selectedStatus = biz.subscriptionStatus;
    String selectedPaymentMode =
        (biz.paymentMode.toLowerCase() == 'online') ? 'online' : 'cash';
    DateTime? selectedRenewalDate =
        biz.renewalDate ?? DateTime.now().add(const Duration(days: 365));
    DateTime? selectedGracePeriodEnds = biz.gracePeriodEnds;
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Override Subscription — ${biz.brandName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Subscription Status:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: selectedStatus,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'active',
                        child: Text('Active (Full Access)')),
                    DropdownMenuItem(
                        value: 'grace_period',
                        child: Text('Grace Period')),
                    DropdownMenuItem(
                        value: 'deleted',
                        child: Text('Deleted / Lapsed')),
                    DropdownMenuItem(
                        value: 'pending_payment',
                        child: Text('Pending Payment')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => selectedStatus = val);
                  },
                ),
                if (selectedStatus == 'active') ...[
                  const SizedBox(height: 16),
                  const Text('Payment Method:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: selectedPaymentMode,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'cash',
                          child: Text('Cash Payment (CASH)')),
                      DropdownMenuItem(
                          value: 'online',
                          child: Text('Online Payment (ONLINE)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => selectedPaymentMode = val);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Renewal Date:',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                          Text(selectedRenewalDate != null
                              ? DateFormat('dd MMM yyyy')
                                  .format(selectedRenewalDate!)
                              : 'Not set'),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              selectedRenewalDate ?? DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() => selectedRenewalDate = picked);
                        }
                      },
                      child: const Text('Change Date'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (selectedStatus == 'grace_period') ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Grace Period Ends:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(selectedGracePeriodEnds != null
                                ? DateFormat('dd MMM yyyy')
                                    .format(selectedGracePeriodEnds!)
                                : 'Not set'),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedGracePeriodEnds ??
                                DateTime.now()
                                    .add(const Duration(days: 14)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(
                                () => selectedGracePeriodEnds = picked);
                          }
                        },
                        child: const Text('Extend Grace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Override *',
                    hintText:
                        'e.g. Payment dispute resolved via bank transfer',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Please provide a reason for the override.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                await provider.overrideSubscriptionStatus(
                  businessId: biz.id,
                  newStatus: selectedStatus,
                  newRenewalDate: selectedRenewalDate,
                  newGracePeriodEnds: selectedGracePeriodEnds,
                  adminUid: adminUid,
                  reason: reasonCtrl.text.trim(),
                  paymentMode: selectedStatus == 'active' ? selectedPaymentMode : 'pending',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Subscription override applied for ${biz.brandName}.')),
                  );
                }
              },
              child: const Text('Apply Override'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminDashboardProvider>().fetchAllBusinesses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final auth = context.watch<AppAuthProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('d MMM yyyy');

    final businesses = _filtered(provider.allBusinesses, provider);

    int totalShowingBranches = 0;
    int activeShowingBranches = 0;
    int pendingShowingBranches = 0;

    for (final b in businesses) {
      final bStats = provider.businessBranchStats[b.id];
      if (bStats != null) {
        totalShowingBranches += bStats.total;
        activeShowingBranches += bStats.active;
        pendingShowingBranches += bStats.pending;
      } else {
        totalShowingBranches += 1;
        if (b.subscriptionStatus == 'active') {
          activeShowingBranches += 1;
        } else if (b.subscriptionStatus == 'pending_payment') {
          pendingShowingBranches += 1;
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Businesses & Overrides',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View, edit, and manage subscription overrides for all enrolled businesses and active branch locations.',
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
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Filters ─────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in {
                'all': 'All',
                'active': 'Active',
                'pending_payment': 'Pending',
                'grace_period': 'Grace',
                'deleted': 'Deleted',
              }.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: _statusFilter == entry.key,
                  onSelected: (_) =>
                      setState(() => _statusFilter = entry.key),
                ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(_dateRange != null
                    ? '${dateFormat.format(_dateRange!.start)} – ${dateFormat.format(_dateRange!.end)}'
                    : 'Date Filter'),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: _dateRange,
                  );
                  setState(() => _dateRange = picked);
                },
              ),
              if (_dateRange != null)
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear dates'),
                  onPressed: () => setState(() => _dateRange = null),
                ),
              // Enrolled By filter (Admin Direct vs Specific Employee)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String?>(
                  hint: const Text('Enrolled By'),
                  value: _enrolledByFilter,
                  underline: const SizedBox(),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Enrollers'),
                    ),
                    const DropdownMenuItem<String?>(
                      value: 'admin',
                      child: Text('👑 Admin (Direct)'),
                    ),
                    for (final emp in provider.employees)
                      DropdownMenuItem<String?>(
                        value: emp.uid,
                        child: Text('👤 ${emp.name}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _enrolledByFilter = v),
                ),
              ),
              // GROUP D3: Month filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<int>(
                  hint: const Text('Month'),
                  value: _monthFilter,
                  underline: const SizedBox(),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('All Months')),
                    for (int m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text(DateFormat.MMMM().format(DateTime(2024, m)))),
                  ],
                  onChanged: (v) => setState(() {
                    _monthFilter = v;
                    _yearFilter = v != null ? (_yearFilter ?? DateTime.now().year) : null;
                  }),
                ),
              ),
              if (_monthFilter != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<int>(
                    value: _yearFilter ?? DateTime.now().year,
                    underline: const SizedBox(),
                    isDense: true,
                    items: [
                      for (int y = DateTime.now().year; y >= 2024; y--)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _yearFilter = v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Mobile number & keyword search field
          SizedBox(
            width: 320,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by mobile number, brand…',
                prefixIcon: Icon(Icons.phone_outlined, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _mobileSearch = v),
            ),
          ),
          const SizedBox(height: 8),

          // Count summary with both Businesses and Branch Locations breakdown
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _CountBadge(
                label: 'Businesses',
                count: businesses.length,
                color: colorScheme.primary,
              ),
              _CountBadge(
                label: 'Total Locations',
                count: totalShowingBranches,
                color: Colors.indigo,
              ),
              _CountBadge(
                label: 'Active Locations',
                count: activeShowingBranches,
                color: Colors.green,
              ),
              if (pendingShowingBranches > 0)
                _CountBadge(
                  label: 'Pending Locations',
                  count: pendingShowingBranches,
                  color: Colors.orange,
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Business List ───────────────────────────────────────────
          if (businesses.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No businesses match the current filters.',
                    style:
                        TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: businesses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final biz = businesses[index];
                final branches = provider.businessBranches[biz.id] ?? [];
                final bStats = provider.businessBranchStats[biz.id];
                final renewalStr = biz.renewalDate != null
                    ? dateFormat.format(biz.renewalDate!)
                    : '—';
                final createdStr = biz.createdAt != null
                    ? dateFormat.format(biz.createdAt!)
                    : '—';

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side:
                        BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Name + Status badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(biz.brandName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                    biz.subscriptionStatus),
                                borderRadius:
                                    BorderRadius.circular(6),
                              ),
                              child: Text(
                                biz.subscriptionStatus == 'active'
                                    ? (biz.paymentMode.toLowerCase() == 'online'
                                        ? 'ACTIVE (ONLINE)'
                                        : 'ACTIVE (CASH)')
                                    : biz.subscriptionStatus
                                        .replaceAll('_', ' ')
                                        .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _statusFg(
                                      biz.subscriptionStatus),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Row 2: Details — show resolved employee name
                        Text(
                          'Owner: ${biz.ownerName ?? "—"} • ${biz.ownerPhone ?? ""}\nEnrolled by: ${provider.resolveEmployeeName(biz.enrolledBy)} • Created: $createdStr • Renewal: $renewalStr',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant),
                        ),
                        if (branches.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.store_mall_directory_outlined, size: 15, color: colorScheme.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Locations (${branches.length} total • ${bStats?.active ?? 0} active)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                for (final branch in branches) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${branch.branchName.isNotEmpty ? branch.branchName : "Main Location"} — ${branch.address.isNotEmpty ? branch.address : "No address"}',
                                            style: const TextStyle(fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: branch.isActive
                                                ? Colors.green.withValues(alpha: 0.15)
                                                : Colors.amber.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            branch.isActive
                                                ? (branch.paymentMode.toLowerCase() == 'online' || biz.paymentMode.toLowerCase() == 'online'
                                                    ? 'ACTIVE (ONLINE)'
                                                    : 'ACTIVE (CASH)')
                                                : 'AWAITING PAYMENT',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: branch.isActive ? Colors.green[800] : Colors.deepOrange,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        // Row 3: Actions
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  context.push('/business/${biz.id}', extra: biz),
                              icon: const Icon(Icons.arrow_forward, size: 14),
                              label: const Text('View Details'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showEditBusinessDialog(
                                      context, provider, biz),
                              icon: const Icon(Icons.edit_outlined,
                                  size: 14),
                              label: const Text('Edit'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _showOverrideDialog(
                                      context,
                                      provider,
                                      biz,
                                      auth.uid ?? 'admin'),
                              icon: const Icon(
                                  Icons.edit_calendar, size: 14),
                              label: const Text('Override'),
                            ),
                            // Cash Activate — only for pending_payment
                            if (biz.subscriptionStatus == 'pending_payment')
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _showCashActivateDialog(
                                  context,
                                  provider,
                                  biz,
                                  auth.uid ?? 'admin',
                                ),
                                icon: const Icon(Icons.local_atm, size: 14),
                                label: const Text('Cash Activate'),
                              ),
                            // Delete Draft — only for pending_payment
                            if (biz.subscriptionStatus == 'pending_payment')
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                                ),
                                onPressed: () => _showDeleteDraftDialog(context, provider, biz),
                                icon: Icon(Icons.delete_outline, size: 14, color: colorScheme.error),
                                label: const Text('Delete Draft'),
                              ),
                            // Reverse Activation — only for active businesses
                            if (biz.subscriptionStatus == 'active')
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.amber.shade800,
                                  side: BorderSide(color: Colors.amber.shade600.withValues(alpha: 0.5)),
                                ),
                                onPressed: () => _showReverseActivationDialog(
                                  context, provider, biz, auth.uid ?? 'admin',
                                ),
                                icon: Icon(Icons.undo, size: 14, color: Colors.amber.shade800),
                                label: const Text('Reverse Activation'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Cash Activate Dialog ──────────────────────────────────────────────────
  void _showCashActivateDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    BusinessModel biz,
    String adminUid,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.local_atm, color: Colors.teal.shade700, size: 40),
        title: const Text('Confirm Cash Activation'),
        content: Text(
          'Activate "${biz.brandName}" directly via cash payment?\n\n'
          '• Setup fee: ₹1,999 collected in cash\n'
          '• Status: pending_payment → active\n'
          '• 365 days subscription starts immediately\n'
          '• Audit commission record marked as verified',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm & Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await provider.adminCashActivate(
        businessId: biz.id,
        adminUid: adminUid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${biz.brandName}" activated successfully via cash payment!'),
            backgroundColor: Colors.teal.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cash activation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Delete Draft Dialog ──────────────────────────────────────────────────
  void _showDeleteDraftDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    BusinessModel biz,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text(
          'This will permanently delete "${biz.brandName}" and all its branches.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await provider.deleteDraftBusiness(biz.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${biz.brandName}" draft deleted.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Reverse Activation Dialog (Double Confirm) ──────────────────────────
  void _showReverseActivationDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    BusinessModel biz,
    String adminUid,
  ) async {
    // Step 1: First confirmation
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 40),
        title: const Text('Reverse Activation?'),
        content: Text(
          'Are you sure you want to reverse activation for "${biz.brandName}"?\n\n'
          '• subscription_status → pending_payment\n'
          '• payment_mode & renewal_date cleared\n'
          '• Commission entry VOIDED (not deleted)\n'
          '• QR codes marked stale\n\n'
          'The business will become a draft again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) return;

    // Step 2: Second confirmation — type business name
    final nameCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Confirm by typing business name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Type "${biz.brandName}" exactly to confirm reversal:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Business name',
                  hintText: 'Type business name here…',
                ),
                onChanged: (_) => setDlg(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for reversal *',
                  hintText: 'e.g., Accidental activation, wrong business…',
                ),
                maxLines: 2,
                onChanged: (_) => setDlg(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: nameCtrl.text.trim() == biz.brandName &&
                      reasonCtrl.text.trim().isNotEmpty
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              child: const Text('Reverse Activation'),
            ),
          ],
        ),
      ),
    );
    if (secondConfirm != true || !context.mounted) return;

    try {
      await provider.reverseActivation(
        businessId: biz.id,
        adminUid: adminUid,
        reason: reasonCtrl.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${biz.brandName}" reversed to pending_payment. Commission voided.'),
            backgroundColor: Colors.amber.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reversal failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green.withValues(alpha: 0.15);
      case 'grace_period':
        return Colors.orange.withValues(alpha: 0.15);
      case 'pending_payment':
        return Colors.blue.withValues(alpha: 0.15);
      case 'deleted':
        return Colors.red.withValues(alpha: 0.15);
      default:
        return Colors.grey.withValues(alpha: 0.15);
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'active':
        return Colors.green.shade700;
      case 'grace_period':
        return Colors.orange.shade700;
      case 'pending_payment':
        return Colors.blue.shade700;
      case 'deleted':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }
}

// GROUP D3: Count badge widget
class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountBadge({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count ', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
