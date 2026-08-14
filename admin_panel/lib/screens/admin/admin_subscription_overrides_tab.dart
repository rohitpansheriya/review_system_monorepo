// lib/screens/admin/admin_subscription_overrides_tab.dart
//
// Subscription / Renewal Overrides Tab for Platform Admin (Doc 04 / Doc 05).
// Allows manual override of grace_period_ends, renewal_date, or subscription_status
// (e.g. edge-case payment disputes, manual extensions, reactivating deleted businesses).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/business_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/auth_provider.dart';

class AdminSubscriptionOverridesTab extends StatelessWidget {
  const AdminSubscriptionOverridesTab({super.key});

  void _showOverrideDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    BusinessModel biz,
    String adminUid,
  ) {
    String selectedStatus = biz.subscriptionStatus;
    DateTime? selectedRenewalDate = biz.renewalDate ?? DateTime.now().add(const Duration(days: 365));
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
                const Text('Subscription Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: selectedStatus,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active (Full Access)')),
                    DropdownMenuItem(value: 'grace_period', child: Text('Grace Period')),
                    DropdownMenuItem(value: 'deleted', child: Text('Deleted / Lapsed')),
                    DropdownMenuItem(value: 'pending_payment', child: Text('Pending Payment')),
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
                          const Text('Renewal Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(selectedRenewalDate != null ? DateFormat('dd MMM yyyy').format(selectedRenewalDate!) : 'Not set'),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedRenewalDate ?? DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setState(() => selectedRenewalDate = picked);
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
                            const Text('Grace Period Ends:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(selectedGracePeriodEnds != null ? DateFormat('dd MMM yyyy').format(selectedGracePeriodEnds!) : 'Not set'),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedGracePeriodEnds ?? DateTime.now().add(const Duration(days: 14)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => selectedGracePeriodEnds = picked);
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
                    hintText: 'e.g. Payment dispute resolved via bank transfer',
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
                    const SnackBar(content: Text('Please provide a reason for the override.')),
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
                    SnackBar(content: Text('Subscription override applied for ${biz.brandName}.')),
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
    final businesses = provider.allBusinesses;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subscription & Renewal Overrides',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Admin-only manual override of subscription status, grace periods, or renewal dates.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton.filledTonal(
                onPressed: () => provider.fetchAllBusinesses(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (businesses.isEmpty)
            const Center(child: Text('No businesses found.'))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: businesses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final biz = businesses[index];
                final dateFormat = DateFormat('dd MMM yyyy');
                final renewalStr = biz.renewalDate != null ? dateFormat.format(biz.renewalDate!) : 'Not set';

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    title: Text(biz.brandName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Status: ${biz.subscriptionStatus.toUpperCase()} • Renewal: $renewalStr • Enrolled By: ${biz.enrolledBy}'),
                    trailing: ElevatedButton.icon(
                      onPressed: () => _showOverrideDialog(context, provider, biz, auth.uid ?? 'admin'),
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      label: const Text('Override Subscription'),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
