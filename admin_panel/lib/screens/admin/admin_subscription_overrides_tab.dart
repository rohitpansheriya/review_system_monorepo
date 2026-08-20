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

  List<BusinessModel> _filtered(List<BusinessModel> businesses) {
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
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final auth = context.watch<AppAuthProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final businesses = _filtered(provider.allBusinesses);
    final dateFormat = DateFormat('dd MMM yyyy');

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
                      'View, edit, and manage subscription overrides for all enrolled businesses.',
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
              // GROUP D3: Month filter
              DropdownButton<int>(
                hint: const Text('Month'),
                value: _monthFilter,
                underline: const SizedBox(),
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
              if (_monthFilter != null)
                DropdownButton<int>(
                  value: _yearFilter ?? DateTime.now().year,
                  underline: const SizedBox(),
                  items: [
                    for (int y = DateTime.now().year; y >= 2024; y--)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: (v) => setState(() => _yearFilter = v),
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

          // GROUP D3: Count summary
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _CountBadge(label: 'Total', count: provider.allBusinesses.length, color: colorScheme.primary),
              _CountBadge(label: 'Showing', count: businesses.length, color: colorScheme.secondary),
              _CountBadge(
                label: 'Active',
                count: provider.allBusinesses.where((b) => b.subscriptionStatus == 'active').length,
                color: Colors.green,
              ),
              _CountBadge(
                label: 'Pending',
                count: provider.allBusinesses.where((b) => b.subscriptionStatus == 'pending_payment').length,
                color: Colors.blue,
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
                                biz.subscriptionStatus
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
                        const SizedBox(height: 10),
                        // Row 3: Actions — GROUP E3: wrap for mobile
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
