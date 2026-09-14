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
import '../../models/employee_profile_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_fulfillment_stepper.dart';
import '../../widgets/app_kpi_card.dart';
import '../../widgets/app_search_bar.dart';

class AdminStandeeTab extends StatefulWidget {
  const AdminStandeeTab({super.key});

  @override
  State<AdminStandeeTab> createState() => _AdminStandeeTabState();
}

class _AdminStandeeTabState extends State<AdminStandeeTab> {
  String _selectedStatusFilter = 'all';
  String _selectedEmployeeFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<AdminDashboardProvider>();
        if (provider.standeeItems.isEmpty && !provider.standeeLoading) {
          provider.fetchStandeeFulfillments();
        }
      }
    });
  }

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
          (((item.ownerPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digitNeedle)) ||
           ((item.enrolledByPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digitNeedle)));

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
      builder: (ctx) => AppModalDialog(
        icon: Icons.local_shipping_rounded,
        iconColor: AppColors.primary,
        title: title,
        subtitle: 'Enter courier details and tracking number for this shipment.',
        maxWidth: 480,
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: courierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Courier Partner *',
                  hintText: 'e.g. DTDC, India Post, Delhivery, Bluedart',
                  prefixIcon: Icon(Icons.business_outlined, size: 18),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter courier partner' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: awbCtrl,
                decoration: const InputDecoration(
                  labelText: 'AWB / Tracking Number *',
                  hintText: 'e.g. 123456789',
                  prefixIcon: Icon(Icons.tag_rounded, size: 18),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter AWB number' : null,
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
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

  Future<void> _updateStatus(
    AdminDashboardProvider provider,
    StandeeFulfillmentModel item,
    String newVal,
  ) async {
    if (newVal == item.standeeStatus) return;

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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.businessName} marked as ${AppConstants.standeeStatusLabels[newVal] ?? newVal}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allItems = provider.standeeItems;
    final filtered = _filterList(allItems);

    // Summary counts for KPI cards
    final orderedCount = allItems.where((i) => (AppConstants.standeeStatuses.contains(i.standeeStatus) ? i.standeeStatus : AppConstants.standeeOrdered) == AppConstants.standeeOrdered).length;
    final printedCount = allItems.where((i) => (AppConstants.standeeStatuses.contains(i.standeeStatus) ? i.standeeStatus : AppConstants.standeeOrdered) == AppConstants.standeePrinted).length;
    final shippedCount = allItems.where((i) => (AppConstants.standeeStatuses.contains(i.standeeStatus) ? i.standeeStatus : AppConstants.standeeOrdered) == AppConstants.standeeShipped).length;
    final deliveredCount = allItems.where((i) => (AppConstants.standeeStatuses.contains(i.standeeStatus) ? i.standeeStatus : AppConstants.standeeOrdered) == AppConstants.standeeDelivered).length;

    // Build unique enrolled employee list
    final employeeMap = <String, String>{};
    for (final item in allItems) {
      if (item.enrolledBy != null && item.enrolledBy!.trim().isNotEmpty) {
        final uid = item.enrolledBy!.trim();
        final name = (item.enrolledByName != null && item.enrolledByName!.trim().isNotEmpty)
            ? item.enrolledByName!.trim()
            : 'Employee (${uid.substring(0, uid.length > 6 ? 6 : uid.length)})';
        employeeMap[uid] = name;
      }
    }

    // Also include any employees from the provider's employee list if not yet mapped
    for (final emp in provider.employees) {
      if (!employeeMap.containsKey(emp.uid)) {
        employeeMap[emp.uid] = emp.name.isNotEmpty ? emp.name : 'Employee (${emp.uid.substring(0, emp.uid.length > 6 ? 6 : emp.uid.length)})';
      }
    }

    final safeEmployeeFilter = (employeeMap.containsKey(_selectedEmployeeFilter) || _selectedEmployeeFilter == 'all')
        ? _selectedEmployeeFilter
        : 'all';

    // Check if an employee is currently selected
    EmployeeProfileModel? selectedEmpModel;
    if (safeEmployeeFilter != 'all') {
      for (final e in provider.employees) {
        if (e.uid == safeEmployeeFilter) {
          selectedEmpModel = e;
          break;
        }
      }
    }

    final selectedEmpName = safeEmployeeFilter != 'all'
        ? (employeeMap[safeEmployeeFilter] ?? selectedEmpModel?.name ?? 'Selected Employee')
        : null;

    // Resolve employee address & phone safely
    String employeeAddress = 'No delivery address saved in employee profile';
    if (selectedEmpModel != null && selectedEmpModel.address.trim().isNotEmpty) {
      employeeAddress = selectedEmpModel.address.trim();
    } else {
      final firstWithAddr = filtered.where((i) => i.enrolledByAddress != null && i.enrolledByAddress!.trim().isNotEmpty).firstOrNull;
      if (firstWithAddr != null && firstWithAddr.enrolledByAddress != null && firstWithAddr.enrolledByAddress!.trim().isNotEmpty) {
        employeeAddress = firstWithAddr.enrolledByAddress!.trim();
      }
    }

    String employeePhone = 'No Phone';
    if (selectedEmpModel != null && selectedEmpModel.phone.trim().isNotEmpty) {
      employeePhone = selectedEmpModel.phone.trim();
    } else {
      final firstWithPhone = filtered.where((i) => i.enrolledByPhone != null && i.enrolledByPhone!.trim().isNotEmpty).firstOrNull;
      if (firstWithPhone != null && firstWithPhone.enrolledByPhone != null && firstWithPhone.enrolledByPhone!.trim().isNotEmpty) {
        employeePhone = firstWithPhone.enrolledByPhone!.trim();
      }
    }

    // Items for selected employee ready for dispatch
    final empReadyItems = safeEmployeeFilter != 'all'
        ? allItems.where((i) =>
            i.enrolledBy == safeEmployeeFilter &&
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

              // ── Summary KPI Metric Cards ─────────────────────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  final isMedium = constraints.maxWidth > 600;
                  final crossAxisCount = isWide ? 4 : (isMedium ? 2 : 1);
                  final ratio = isWide ? 1.45 : (isMedium ? 1.7 : 2.5);

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    childAspectRatio: ratio,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      AppKpiCard(
                        label: 'Ordered / Pending Print',
                        value: '$orderedCount',
                        subtitle: 'Awaiting acrylic printing',
                        icon: Icons.shopping_bag_outlined,
                        color: const Color(0xFFF59E0B),
                        onTap: () => setState(() => _selectedStatusFilter = AppConstants.standeeOrdered),
                      ),
                      AppKpiCard(
                        label: 'Printed / In Stock',
                        value: '$printedCount',
                        subtitle: 'Ready for batch dispatch',
                        icon: Icons.print_rounded,
                        color: const Color(0xFF2563EB),
                        onTap: () => setState(() => _selectedStatusFilter = AppConstants.standeePrinted),
                      ),
                      AppKpiCard(
                        label: 'Shipped / In Transit',
                        value: '$shippedCount',
                        subtitle: 'With courier or field agent',
                        icon: Icons.local_shipping_rounded,
                        color: const Color(0xFF7C3AED),
                        onTap: () => setState(() => _selectedStatusFilter = AppConstants.standeeShipped),
                      ),
                      AppKpiCard(
                        label: 'Delivered & Active',
                        value: '$deliveredCount',
                        subtitle: 'Live at merchant counter',
                        icon: Icons.verified_rounded,
                        color: const Color(0xFF10B981),
                        onTap: () => setState(() => _selectedStatusFilter = AppConstants.standeeDelivered),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── Filter Controls Row ──────────────────────────────────────
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Employee Filter Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00458B).withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: safeEmployeeFilter,
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 8,
                        icon: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
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
                    child: AppSearchBar(
                      hintText: 'Search business, branch, AWB, phone…',
                      initialValue: _searchQuery,
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
              if (safeEmployeeFilter != 'all') ...[
                _buildEmployeeBatchCard(
                  context,
                  provider,
                  employeeUid: safeEmployeeFilter,
                  employeeName: selectedEmpName ?? 'Employee',
                  employeePhone: employeePhone,
                  employeeAddress: employeeAddress,
                  readyCount: empReadyItems.length,
                  totalForEmp: allItems.where((i) => i.enrolledBy == safeEmployeeFilter).length,
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
                AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No standees found',
                  subtitle: _searchQuery.isNotEmpty || _selectedStatusFilter != 'all' || safeEmployeeFilter != 'all'
                      ? 'No standees match your active filters.'
                      : 'No branch standee fulfillment records found.',
                  actionLabel: _searchQuery.isNotEmpty || _selectedStatusFilter != 'all' || safeEmployeeFilter != 'all'
                      ? 'Clear Filters'
                      : null,
                  onAction: _searchQuery.isNotEmpty || _selectedStatusFilter != 'all' || safeEmployeeFilter != 'all'
                      ? () => setState(() {
                            _searchQuery = '';
                            _selectedStatusFilter = 'all';
                            _selectedEmployeeFilter = 'all';
                          })
                      : null,
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
    final colorScheme = Theme.of(context).colorScheme;

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
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 650;
              final addressColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Color(0xFF7C3AED)),
                      SizedBox(width: 6),
                      Text('Shipping Destination (Employee Address):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
              );

              final actionButtons = Column(
                crossAxisAlignment: isWide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
              );

              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: addressColumn),
                        const SizedBox(width: 16),
                        actionButtons,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        addressColumn,
                        const SizedBox(height: 12),
                        actionButtons,
                      ],
                    );
            },
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
    final updatedText = _formatTimeAgo(item.standeeStatusUpdatedAt, safeStatus);

    final isDeliveredViaScan = item.standeeStatus == AppConstants.standeeDelivered &&
        item.deliveredVia == 'first_scan_detected';

    final initialChar = item.businessName.trim().isNotEmpty
        ? item.businessName.trim()[0].toUpperCase()
        : '?';

    // Determine next step label and icon for quick action button
    String? nextStepStatus;
    String? nextStepLabel;
    IconData? nextStepIcon;
    Color? nextStepColor;

    if (safeStatus == AppConstants.standeeOrdered) {
      nextStepStatus = AppConstants.standeePrinted;
      nextStepLabel = 'Mark Printed';
      nextStepIcon = Icons.print_rounded;
      nextStepColor = const Color(0xFF2563EB);
    } else if (safeStatus == AppConstants.standeePrinted) {
      nextStepStatus = AppConstants.standeeShipped;
      nextStepLabel = 'Ship with AWB';
      nextStepIcon = Icons.local_shipping_rounded;
      nextStepColor = const Color(0xFF7C3AED);
    } else if (safeStatus == AppConstants.standeeShipped) {
      nextStepStatus = AppConstants.standeeDelivered;
      nextStepLabel = 'Mark Delivered';
      nextStepIcon = Icons.verified_rounded;
      nextStepColor = const Color(0xFF10B981);
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
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
                    initialChar,
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
                AppBadge.standee(safeStatus),
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
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
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

            // ── Interactive Visual Pipeline Stepper ──────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: AppFulfillmentStepper(
                currentStatus: safeStatus,
                isInteractive: true,
                onStepSelected: (newVal) => _updateStatus(provider, item, newVal),
              ),
            ),

            // Courier / AWB Tracking Badge (when shipped or delivered)
            if (item.courierAwb != null && item.courierAwb!.isNotEmpty) ...[
              const SizedBox(height: 10),
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
                      borderRadius: BorderRadius.circular(4),
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
              const SizedBox(height: 8),
              AppBadge(
                label: 'Verified Handover (Auto-Promoted via Live First Scan)',
                backgroundColor: AppColors.activeBg,
                foregroundColor: AppColors.activeFg,
                icon: Icons.verified,
                fontSize: 11,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                borderRadius: BorderRadius.circular(6),
              ),
            ],

            const Divider(height: 20),

            // Row 3: Timestamp & Status Controls
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
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (nextStepStatus != null && nextStepLabel != null)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: nextStepColor,
                          backgroundColor: nextStepColor?.withValues(alpha: 0.12),
                        ),
                        onPressed: () => _updateStatus(provider, item, nextStepStatus!),
                        icon: Icon(nextStepIcon ?? Icons.arrow_forward_rounded, size: 16),
                        label: Text(nextStepLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00458B).withValues(alpha: 0.03),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: safeStatus,
                          dropdownColor: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          elevation: 8,
                          icon: const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
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
                          onChanged: (newVal) {
                            if (newVal != null) {
                              _updateStatus(provider, item, newVal);
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
