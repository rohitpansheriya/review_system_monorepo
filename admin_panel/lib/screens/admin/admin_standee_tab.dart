// lib/screens/admin/admin_standee_tab.dart
//
// Standee Fulfillment Tracking Screen for Platform Admin.
// Features:
//   - Lists all branches of activated businesses (excluding drafts).
//   - Colored badges for standee status (Not Ordered / Ordered / Printed / Shipped / Delivered).
//   - Relative timestamp formatting ("Shipped 3 days ago").
//   - Inline dropdown on each row to change status immediately without opening details.
//   - Filters by standee status (Daily work queue).
//   - Search by business name, branch name, or mobile number.
//   - Responsive layout for desktop and mobile (~380px).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/standee_fulfillment_model.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminStandeeTab extends StatefulWidget {
  const AdminStandeeTab({super.key});

  @override
  State<AdminStandeeTab> createState() => _AdminStandeeTabState();
}

class _AdminStandeeTabState extends State<AdminStandeeTab> {
  String _selectedStatusFilter = 'all';
  String _searchQuery = '';

  String _formatTimeAgo(DateTime? date, String status) {
    if (date == null) return 'Never updated';
    final now = DateTime.now();
    final diff = now.difference(date);

    String verb = 'Updated';
    if (status == 'printed') verb = 'Printed';
    if (status == 'shipped') verb = 'Shipped';
    if (status == 'delivered') verb = 'Delivered';
    if (status == 'ordered') verb = 'Ordered';

    if (diff.inSeconds < 60) return '$verb just now';
    if (diff.inMinutes < 60) return '$verb ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '$verb ${diff.inHours}h ago';
    if (diff.inDays == 1) return '$verb yesterday';
    if (diff.inDays < 30) return '$verb ${diff.inDays} days ago';
    return '$verb on ${DateFormat('d MMM yyyy').format(date)}';
  }

  List<StandeeFulfillmentModel> _filterList(List<StandeeFulfillmentModel> items) {
    return items.where((item) {
      final statusMatch = _selectedStatusFilter == 'all' || item.standeeStatus == _selectedStatusFilter;
      if (!statusMatch) return false;

      if (_searchQuery.trim().isEmpty) return true;

      final q = _searchQuery.trim().toLowerCase();
      final digitNeedle = _searchQuery.replaceAll(RegExp(r'[^0-9]'), '');

      final nameMatch = item.businessName.toLowerCase().contains(q);
      final branchMatch = item.branchName.toLowerCase().contains(q);
      final addressMatch = item.address.toLowerCase().contains(q);
      final phoneMatch = digitNeedle.isNotEmpty &&
          (item.ownerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digitNeedle);

      return nameMatch || branchMatch || addressMatch || phoneMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allItems = provider.standeeItems;
    final filtered = _filterList(allItems);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => provider.fetchStandeeFulfillments(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                          'Standee Fulfillment Tracking',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Track acrylic standee printing, shipping, and delivery across all activated businesses.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => provider.fetchStandeeFulfillments(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh fulfillments',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Filter Chips ─────────────────────────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text('All (${allItems.length})'),
                    selected: _selectedStatusFilter == 'all',
                    onSelected: (_) => setState(() => _selectedStatusFilter = 'all'),
                  ),
                  for (final status in AppConstants.standeeStatuses) ...[
                    FilterChip(
                      label: Text(
                        '${AppConstants.standeeStatusLabels[status] ?? status} (${allItems.where((i) => i.standeeStatus == status).length})',
                      ),
                      selected: _selectedStatusFilter == status,
                      onSelected: (_) => setState(() => _selectedStatusFilter = status),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── Search Bar ───────────────────────────────────────────────
              SizedBox(
                width: 380,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by business name, branch, phone…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(height: 20),

              // ── List Section ─────────────────────────────────────────────
              if (provider.standeeLoading && allItems.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (provider.standeeError != null && allItems.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 40),
                        const SizedBox(height: 12),
                        Text('Error: ${provider.standeeError}'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => provider.fetchStandeeFulfillments(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No businesses found matching "$_selectedStatusFilter" status.',
                            style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildFulfillmentCard(context, provider, item);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFulfillmentCard(
    BuildContext context,
    AdminDashboardProvider provider,
    StandeeFulfillmentModel item,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = AppTheme.standeeStatusColor(item.standeeStatus);
    final statusFg = AppTheme.standeeStatusForeground(item.standeeStatus);
    final statusLabel = AppConstants.standeeStatusLabels[item.standeeStatus] ?? item.standeeStatus;
    final updatedText = _formatTimeAgo(item.standeeStatusUpdatedAt, item.standeeStatus);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Brand & Branch Name + Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    item.businessName.isNotEmpty ? item.businessName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.businessName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.branchName.isNotEmpty && item.branchName != item.businessName)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            'Branch: ${item.branchName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: statusFg,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Row 2: Location & Contact Info
            if (item.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.address,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            if (item.ownerPhone != null && item.ownerPhone!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      item.ownerPhone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 16),

            // Row 3: Timestamp & Inline Status Dropdown (Responsive wrap)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      updatedText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Update Status: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: item.standeeStatus,
                          isDense: true,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          items: AppConstants.standeeStatuses.map((s) {
                            return DropdownMenuItem<String>(
                              value: s,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.standeeStatusForeground(s),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(AppConstants.standeeStatusLabels[s] ?? s),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (newVal) async {
                            if (newVal == null || newVal == item.standeeStatus) return;
                            await provider.updateStandeeStatusInline(
                              businessId: item.businessId,
                              branchId: item.branchId,
                              newStatus: newVal,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${item.businessName} standee marked as ${AppConstants.standeeStatusLabels[newVal] ?? newVal}',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
