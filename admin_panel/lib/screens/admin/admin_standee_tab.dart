// lib/screens/admin/admin_standee_tab.dart
//
// Standee Fulfillment Tracking Screen for Platform Admin.
// Features:
//   - Lists all branches of activated businesses (excluding drafts).
//   - Employee-centric batch dispatch: Filter by enrolled employee and view fixed delivery address.
//   - AWB tracking: Attach courier name & tracking number individually or in bulk.
//   - Automated proof-of-delivery: Badges branches delivered via live counter scan.
//   - Relative timestamp formatting ("Shipped 3 days ago").
//   - Inline dropdown on each row to change status immediately with AWB prompt on shipping.
//   - Responsive layout for desktop and mobile (~380px).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _selectedEmployeeFilter = 'all';
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
      final safeStatus = AppConstants.standeeStatuses.contains(item.standeeStatus)
          ? item.standeeStatus
          : AppConstants.standeeOrdered;
      final statusMatch = _selectedStatusFilter == 'all' || safeStatus == _selectedStatusFilter;
      if (!statusMatch) return false;

      final empMatch = _selectedEmployeeFilter == 'all' || item.enrolledBy == _selectedEmployeeFilter;
      if (!empMatch) return false;

      if (_searchQuery.trim().isEmpty) return true;

      final q = _searchQuery.trim().toLowerCase();
      final digitNeedle = _searchQuery.replaceAll(RegExp(r'[^0-9]'), '');

      final nameMatch = item.businessName.toLowerCase().contains(q);
      final branchMatch = item.branchName.toLowerCase().contains(q);
      final addressMatch = item.address.toLowerCase().contains(q);
      final empNameMatch = (item.enrolledByName ?? '').toLowerCase().contains(q);
      final awbMatch = (item.courierAwb ?? '').toLowerCase().contains(q);
      final phoneMatch = digitNeedle.isNotEmpty &&
          ((item.ownerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digitNeedle) ||
           (item.enrolledByPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digitNeedle));

      return nameMatch || branchMatch || addressMatch || empNameMatch || awbMatch || phoneMatch;
    }).toList();
  }

  Future<({String courierName, String courierAwb})?> _showAwbInputDialog(
    BuildContext context, {
    required String title,
    String initialCourier = 'DTDC',
  }) async {
    final courierCtrl = TextEditingController(text: initialCourier);
    final awbCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<({String courierName, String courierAwb})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.local_shipping, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the courier partner and AWB/tracking number for this shipment:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: courierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Courier Partner',
                  hintText: 'e.g. DTDC, India Post, Delhivery, Bluedart',
                  prefixIcon: Icon(Icons.business_outlined, size: 18),
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter courier partner' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: awbCtrl,
                decoration: const InputDecoration(
                  labelText: 'AWB / Tracking Number',
                  hintText: 'e.g. 123456789',
                  prefixIcon: Icon(Icons.tag, size: 18),
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter AWB number' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop((
                  courierName: courierCtrl.text.trim(),
                  courierAwb: awbCtrl.text.trim(),
                ));
              }
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm Shipment'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allItems = provider.standeeItems;
    final filtered = _filterList(allItems);

    // Build unique enrolled employee list
    final employeeMap = <String, String>{};
    for (final item in allItems) {
      if (item.enrolledBy != null && item.enrolledBy!.isNotEmpty) {
        employeeMap[item.enrolledBy!] = item.enrolledByName ?? 'Employee (${item.enrolledBy!.substring(0, 6)})';
      }
    }

    // Check if an employee is currently selected
    final selectedEmpModel = _selectedEmployeeFilter != 'all'
        ? provider.employees.where((e) => e.uid == _selectedEmployeeFilter).firstOrNull
        : null;

    final selectedEmpName = _selectedEmployeeFilter != 'all'
        ? (employeeMap[_selectedEmployeeFilter] ?? selectedEmpModel?.name ?? 'Selected Employee')
        : null;

    // Items for selected employee ready for dispatch
    final empReadyItems = _selectedEmployeeFilter != 'all'
        ? allItems.where((i) =>
            i.enrolledBy == _selectedEmployeeFilter &&
            (i.standeeStatus == AppConstants.standeeOrdered || i.standeeStatus == AppConstants.standeePrinted)).toList()
        : <StandeeFulfillmentModel>[];

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
                          'Batch standees by enrolling employee, attach AWB tracking, and track live counter handovers.',
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

              // ── Filter Controls Row ──────────────────────────────────────
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Employee Filter Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedEmployeeFilter,
                        isDense: true,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(Icons.people_outline, size: 16),
                                SizedBox(width: 8),
                                Text('All Enrolling Employees'),
                              ],
                            ),
                          ),
                          ...employeeMap.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                const Icon(Icons.person_pin_circle_outlined, size: 16, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text('Employee: ${e.value}'),
                              ],
                            ),
                          )),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedEmployeeFilter = val);
                        },
                      ),
                    ),
                  ),

                  // Search Bar
                  SizedBox(
                    width: 320,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search business, branch, AWB, phone…',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Status Filter Chips ──────────────────────────────────────
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
                        '${AppConstants.standeeStatusLabels[status] ?? status} (${allItems.where((i) => (AppConstants.standeeStatuses.contains(i.standeeStatus) ? i.standeeStatus : AppConstants.standeeOrdered) == status).length})',
                      ),
                      selected: _selectedStatusFilter == status,
                      onSelected: (_) => setState(() => _selectedStatusFilter = status),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // ── Employee Batch Shipping Card (Shown when employee filter active) ──
              if (_selectedEmployeeFilter != 'all') ...[
                _buildEmployeeBatchCard(
                  context,
                  provider,
                  employeeUid: _selectedEmployeeFilter,
                  employeeName: selectedEmpName ?? 'Employee',
                  employeePhone: selectedEmpModel?.phone ?? filtered.firstOrNull?.enrolledByPhone ?? 'No Phone',
                  employeeAddress: selectedEmpModel?.address.trim().isNotEmpty == true
                      ? selectedEmpModel!.address.trim()
                      : (filtered.firstOrNull?.enrolledByAddress?.trim().isNotEmpty == true
                          ? filtered.firstOrNull!.enrolledByAddress!.trim()
                          : 'No delivery address saved in employee profile'),
                  readyCount: empReadyItems.length,
                  totalForEmp: allItems.where((i) => i.enrolledBy == _selectedEmployeeFilter).length,
                ),
                const SizedBox(height: 24),
              ],

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
                            'No standees found matching current filters.',
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

  // ── Employee Batch Shipping Card ───────────────────────────────────────────
  Widget _buildEmployeeBatchCard(
    BuildContext context,
    AdminDashboardProvider provider, {
    required String employeeUid,
    required String employeeName,
    required String employeePhone,
    required String employeeAddress,
    required int readyCount,
    required int totalForEmp,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF), // Light purple-50
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDD6FE), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF7C3AED),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Batch Shipping to Field Employee: $employeeName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4C1D95)),
                    ),
                    Text(
                      '$totalForEmp enrolled standees total • $readyCount ready for batch dispatch',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFDDD6FE), height: 1),
          const SizedBox(height: 14),

          // Address & Contact Block
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 6),
                        const Text('Shipping Destination (Employee Address):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(employeeAddress, style: const TextStyle(fontSize: 13, height: 1.3)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('Phone: $employeePhone', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      final labelText = 'TO: $employeeName\nPHONE: $employeePhone\nSHIPPING ADDRESS:\n$employeeAddress\nCONTENTS: $readyCount Custom Acrylic Standees';
                      Clipboard.setData(ClipboardData(text: labelText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('📋 Shipping address label copied to clipboard!'), duration: Duration(seconds: 2)),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 15),
                    label: const Text('Copy Shipping Label'),
                  ),
                  const SizedBox(height: 8),
                  if (readyCount > 0)
                    FilledButton.icon(
                      onPressed: () async {
                        final result = await _showAwbInputDialog(
                          context,
                          title: 'Dispatch Batch ($readyCount Standees) to $employeeName',
                        );
                        if (result != null && context.mounted) {
                          await provider.batchShipStandeesForEmployee(
                            employeeUid: employeeUid,
                            courierName: result.courierName,
                            courierAwb: result.courierAwb,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('🚚 Batch of $readyCount standees marked as SHIPPED with AWB: ${result.courierAwb}'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text('Ship Batch ($readyCount Ready)'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Standee Card ───────────────────────────────────────────────────────────
  Widget _buildFulfillmentCard(
    BuildContext context,
    AdminDashboardProvider provider,
    StandeeFulfillmentModel item,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeStatus = AppConstants.standeeStatuses.contains(item.standeeStatus)
        ? item.standeeStatus
        : AppConstants.standeeOrdered;
    final statusColor = AppTheme.standeeStatusColor(safeStatus);
    final statusFg = AppTheme.standeeStatusForeground(safeStatus);
    final statusLabel = AppConstants.standeeStatusLabels[safeStatus] ?? safeStatus;
    final updatedText = _formatTimeAgo(item.standeeStatusUpdatedAt, safeStatus);

    final isDeliveredViaScan = item.standeeStatus == AppConstants.standeeDelivered &&
        item.deliveredVia == 'first_scan_detected';

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

            // Row 2: Location & Merchant Contact Info
            if (item.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Merchant: ${item.address}',
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

            // Enrolled By (Employee Information)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Row(
                children: [
                  const Icon(Icons.person_pin_outlined, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Enrolled by Field Agent: ',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    item.enrolledByName ?? 'Direct / Admin',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  if (item.enrolledByPhone != null && item.enrolledByPhone!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('(${item.enrolledByPhone})', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),

            // Courier / AWB Tracking Badge (when shipped or delivered)
            if (item.courierAwb != null && item.courierAwb!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_shipping, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${item.courierName ?? "Courier"}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    SelectableText(
                      item.courierAwb!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: item.courierAwb!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('AWB "${item.courierAwb}" copied!'), duration: const Duration(seconds: 1)),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.copy, size: 13, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Auto-Delivery Verification Badge
            if (isDeliveredViaScan) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.activeBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, size: 12, color: AppColors.activeFg),
                    SizedBox(width: 4),
                    Text(
                      'Verified Handover (Auto-Promoted via Live First Scan)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.activeFg),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 16),

            // Row 3: Timestamp & Inline Status Dropdown
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
                          value: safeStatus,
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

                            String? courierName = item.courierName;
                            String? courierAwb = item.courierAwb;

                            // If changing to 'shipped', ask for Courier & AWB
                            if (newVal == AppConstants.standeeShipped) {
                              final res = await _showAwbInputDialog(
                                context,
                                title: 'Ship Standee for ${item.businessName}',
                                initialCourier: item.courierName ?? 'DTDC',
                              );
                              if (res == null) return; // User cancelled
                              courierName = res.courierName;
                              courierAwb = res.courierAwb;
                            }

                            await provider.updateStandeeStatusInline(
                              businessId: item.businessId,
                              branchId: item.branchId,
                              newStatus: newVal,
                              courierName: courierName,
                              courierAwb: courierAwb,
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${item.businessName} marked as ${AppConstants.standeeStatusLabels[newVal] ?? newVal}',
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
