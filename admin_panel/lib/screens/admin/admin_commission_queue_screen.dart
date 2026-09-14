import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/employee_commission_model.dart';
import '../../models/employee_profile_model.dart';
import '../../providers/admin_dashboard_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';

class AdminCommissionQueueScreen extends StatefulWidget {
  const AdminCommissionQueueScreen({super.key});

  @override
  State<AdminCommissionQueueScreen> createState() =>
      _AdminCommissionQueueScreenState();
}

class _AdminCommissionQueueScreenState
    extends State<AdminCommissionQueueScreen> {
  String? _selectedEmployeeId;
  String _statusFilter = 'all'; // 'all', 'pending', 'paid'
  String? _monthFilter;

  void _exportPayoutCsv({
    required BuildContext context,
    required List<EmployeeCommissionModel> commissions,
    required List<EmployeeProfileModel> employees,
    required String format, // 'razorpayx', 'icici', 'universal'
    bool onlyPending = true,
  }) {
    final filtered = onlyPending
        ? commissions.where((c) => c.isPending).toList()
        : commissions;

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No commissions match the criteria for payout export.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Group commissions by employee ID
    final empMap = {for (final e in employees) e.uid: e};
    final Map<String, List<EmployeeCommissionModel>> grouped = {};
    for (final comm in filtered) {
      grouped.putIfAbsent(comm.employeeId, () => []).add(comm);
    }

    final StringBuffer csvBuffer = StringBuffer();
    final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    String filename = 'AppNexa_Payouts_$nowStr.csv';

    if (format == 'razorpayx') {
      filename = 'RazorpayX_Bulk_Payout_$nowStr.csv';
      // RazorpayX Bulk IMPS / Bank Account Upload format
      csvBuffer.writeln(
        'Payout Amount*,Payout Currency*,Payout Mode*,Account Number*,Account Type*,IFSC*,Beneficiary Name*,Beneficiary Email,Beneficiary Mobile,Payment Description,Notes',
      );

      for (final entry in grouped.entries) {
        final empId = entry.key;
        final comms = entry.value;
        final emp = empMap[empId];
        final empName = emp?.name ?? 'Employee ($empId)';
        final empEmail = emp?.email ?? '';
        final empPhone = emp?.phone ?? '';
        final bankAcc = emp?.bankAccountNo ?? '';
        final bankIfsc = emp?.bankIfsc ?? '';
        final totalAmount = comms.fold<double>(0, (s, c) => s + c.amount);

        final notes = 'AppNexa Commission - ${comms.length} activations';
        final description = 'Commission Payout ${_monthFilter ?? "Ledger"}';

        csvBuffer.writeln(
          '${totalAmount.toStringAsFixed(2)},INR,IMPS,"$bankAcc",bank_account,"$bankIfsc","$empName","$empEmail","$empPhone","$description","$notes"',
        );
      }
    } else if (format == 'icici') {
      filename = 'ICICI_Bulk_IMPS_$nowStr.csv';
      // ICICI Bank Bulk IMPS Format
      csvBuffer.writeln(
        'Payment Mode,Beneficiary Account No,Beneficiary IFSC,Amount,Beneficiary Name,Remarks / Narration,Payment Reference',
      );

      for (final entry in grouped.entries) {
        final empId = entry.key;
        final comms = entry.value;
        final emp = empMap[empId];
        final empName = emp?.name ?? 'Employee ($empId)';
        final bankAcc = emp?.bankAccountNo ?? '';
        final bankIfsc = emp?.bankIfsc ?? '';
        final totalAmount = comms.fold<double>(0, (s, c) => s + c.amount);
        final remarks = 'AppNexa Comm ${_monthFilter ?? "Payout"}';
        final ref = 'COMM_${empId.substring(0, empId.length > 8 ? 8 : empId.length)}_$nowStr';

        csvBuffer.writeln(
          'IMPS,"$bankAcc","$bankIfsc",${totalAmount.toStringAsFixed(2)},"$empName","$remarks","$ref"',
        );
      }
    } else {
      filename = 'AppNexa_Commissions_Universal_$nowStr.csv';
      // Universal detailed CSV
      csvBuffer.writeln(
        'Employee Name,Employee ID,Email,Phone,Bank Account Number,IFSC Code,UPI ID,Payout Method,Commission Count,Total Amount (INR),Status,Month,Businesses',
      );

      for (final entry in grouped.entries) {
        final empId = entry.key;
        final comms = entry.value;
        final emp = empMap[empId];
        final empName = emp?.name ?? 'Employee';
        final empEmail = emp?.email ?? '';
        final empPhone = emp?.phone ?? '';
        final bankAcc = emp?.bankAccountNo ?? '';
        final bankIfsc = emp?.bankIfsc ?? '';
        final upi = emp?.upiId ?? '';
        final method = emp?.payoutMethod.label ?? 'Bank';
        final totalAmount = comms.fold<double>(0, (s, c) => s + c.amount);
        final businesses = comms.map((c) => c.businessName).join(' | ');

        csvBuffer.writeln(
          '"$empName","$empId","$empEmail","$empPhone","$bankAcc","$bankIfsc","$upi","$method",${comms.length},${totalAmount.toStringAsFixed(2)},${onlyPending ? "Pending" : "Mixed"},"${_monthFilter ?? "All"}","$businesses"',
        );
      }
    }

    // Trigger Browser Download
    final bytes = utf8.encode(csvBuffer.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Downloaded $filename (${grouped.length} beneficiary payouts)'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showExportModal(
    BuildContext context,
    List<EmployeeCommissionModel> commissions,
    List<EmployeeProfileModel> employees,
  ) {
    String selectedFormat = 'razorpayx';
    bool onlyPending = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final pendingCount = commissions.where((c) => c.isPending).length;
          final pendingAmount = commissions
              .where((c) => c.isPending)
              .fold<double>(0, (s, c) => s + c.amount);

          return AppModalDialog(
            icon: Icons.file_download_outlined,
            iconColor: const Color(0xFF4F46E5),
            title: 'Export Bulk Payout CSV',
            subtitle: 'Generate bank-ready payout files for batch disbursement.',
            maxWidth: 500,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pending Payouts', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            '₹${pendingAmount.toStringAsFixed(0)} ($pendingCount records)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                          ),
                        ],
                      ),
                      if (_monthFilter != null)
                        Chip(
                          label: Text(_monthFilter!),
                          backgroundColor: Colors.white,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Select Bank / Gateway Export Format:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  value: 'razorpayx',
                  groupValue: selectedFormat,
                  title: const Text('RazorpayX Bulk Payout (IMPS/NEFT)'),
                  subtitle: const Text('Ready for direct upload to RazorpayX Corporate Payouts dashboard', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setDlgState(() => selectedFormat = v!),
                ),
                RadioListTile<String>(
                  value: 'icici',
                  groupValue: selectedFormat,
                  title: const Text('ICICI Bank Corporate Bulk IMPS'),
                  subtitle: const Text('Compliant with ICICI Corporate Banking Bulk Transfer file format', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setDlgState(() => selectedFormat = v!),
                ),
                RadioListTile<String>(
                  value: 'universal',
                  groupValue: selectedFormat,
                  title: const Text('Universal Summary CSV / Excel'),
                  subtitle: const Text('Full breakdown including employee bank details, UPI, and enrolled businesses', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setDlgState(() => selectedFormat = v!),
                ),
                const Divider(height: 20),
                CheckboxListTile(
                  value: onlyPending,
                  title: const Text('Export ONLY Unpaid / Pending Records', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Excludes commissions already marked as paid', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setDlgState(() => onlyPending = v ?? true),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _exportPayoutCsv(
                    context: context,
                    commissions: commissions,
                    employees: employees,
                    format: selectedFormat,
                    onlyPending: onlyPending,
                  );
                },
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download CSV'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final adminUid = context.read<AppAuthProvider>().uid ?? '';
    final scheme = Theme.of(context).colorScheme;
    final employees = provider.employees;
    final isMobile = MediaQuery.of(context).size.width <= 760;

    // Generate month options (last 12 months)
    final now = DateTime.now();
    final months = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });

    final hasActiveFilter = _selectedEmployeeId != null || _statusFilter != 'all' || _monthFilter != null;

    final employeeDropdown = DropdownButtonFormField<String?>(
      value: _selectedEmployeeId,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: const InputDecoration(
        labelText: 'Employee',
        prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Employees'),
        ),
        ...employees.map(
          (e) => DropdownMenuItem<String?>(
            value: e.uid,
            child: Text(e.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _selectedEmployeeId = v),
    );

    final statusDropdown = DropdownButtonFormField<String>(
      value: _statusFilter,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: const InputDecoration(
        labelText: 'Status',
        prefixIcon: Icon(Icons.filter_list_rounded, size: 18),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All')),
        DropdownMenuItem(value: 'pending', child: Text('Pending')),
        DropdownMenuItem(value: 'paid', child: Text('Paid')),
      ],
      onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
    );

    final monthDropdown = DropdownButtonFormField<String?>(
      value: _monthFilter,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: const InputDecoration(
        labelText: 'Month',
        prefixIcon: Icon(Icons.calendar_month_outlined, size: 18),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Months'),
        ),
        ...months.map(
          (m) => DropdownMenuItem<String?>(
            value: m,
            child: Text(
              DateFormat.yMMM().format(DateTime.parse('$m-01')),
            ),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _monthFilter = v),
    );

    return Column(
      children: [
        // ── Responsive Filter Bar ─────────────────────────────────────────
        Container(
          width: double.infinity,
          margin: EdgeInsets.fromLTRB(
            isMobile ? 12 : 16,
            isMobile ? 12 : 16,
            isMobile ? 12 : 16,
            8,
          ),
          padding: EdgeInsets.all(isMobile ? 12 : 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isMobile) ...[
                employeeDropdown,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: statusDropdown),
                    const SizedBox(width: 8),
                    Expanded(child: monthDropdown),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(flex: 3, child: employeeDropdown),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: statusDropdown),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: monthDropdown),
                    if (hasActiveFilter) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'Reset Filters',
                        onPressed: () => setState(() {
                          _selectedEmployeeId = null;
                          _statusFilter = 'all';
                          _monthFilter = null;
                        }),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),

        // ── One-Click Payout Button ─────────────────────────────────
        if (_selectedEmployeeId != null && _monthFilter != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showBulkPayoutDialog(
                  context,
                  provider,
                  adminUid,
                  _selectedEmployeeId!,
                  _monthFilter!,
                ),
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: Text(
                  'Pay All Pending for ${_getEmployeeName(employees, _selectedEmployeeId!)} (${DateFormat.yMMM().format(DateTime.parse('$_monthFilter-01'))})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),

        // ── Commission List & Summaries ───────────────────────────
        Expanded(child: _buildCommissionStream(context, provider, scheme, isMobile)),
      ],
    );
  }

  Widget _buildCommissionStream(
    BuildContext context,
    AdminDashboardProvider provider,
    ColorScheme scheme,
    bool isMobile,
  ) {
    // Universal reactive commission stream
    final stream = provider.watchCommissions(
      employeeId: _selectedEmployeeId,
      statusFilter: _statusFilter,
      monthFilter: _monthFilter,
    );

    return StreamBuilder<List<EmployeeCommissionModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final commissions = snapshot.data ?? [];

        // Calculate summary
        final totalPending = commissions
            .where((c) => c.isPending)
            .fold<double>(0, (sum, c) => sum + c.amount);
        final totalPaid = commissions
            .where((c) => c.isPaid)
            .fold<double>(0, (sum, c) => sum + c.amount);

        if (commissions.isEmpty) {
          return AppEmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No commission records found',
            subtitle: _selectedEmployeeId != null || _monthFilter != null || _statusFilter != 'all'
                ? 'No commissions match your active filter criteria.'
                : 'Commissions are generated automatically when employee-enrolled businesses activate.',
          );
        }

        final summaryBadges = Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.receipt_outlined,
                label: 'Total',
                value: '${commissions.length}',
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: Icons.schedule_rounded,
                label: 'Pending',
                value: '₹${totalPending.toStringAsFixed(0)}',
                color: const Color(0xFFD97706),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: Icons.check_circle_outline_rounded,
                label: 'Paid',
                value: '₹${totalPaid.toStringAsFixed(0)}',
                color: const Color(0xFF059669),
              ),
            ),
          ],
        );

        final exportButton = FilledButton.icon(
          onPressed: commissions.isEmpty
              ? null
              : () => _showExportModal(context, commissions, provider.employees),
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Export Payout CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );

        return Column(
          children: [
            // Responsive Summary & Export Bar
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: 4,
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summaryBadges,
                        const SizedBox(height: 8),
                        exportButton,
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: summaryBadges),
                        const SizedBox(width: 16),
                        exportButton,
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 4),
                itemCount: commissions.length,
                itemBuilder: (context, index) {
                  final c = commissions[index];
                  return _CommissionCard(commission: c);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _getEmployeeName(List employees, String uid) {
    final emp = employees.where((e) => e.uid == uid);
    return emp.isNotEmpty ? emp.first.name : uid;
  }

  void _showBulkPayoutDialog(
    BuildContext context,
    AdminDashboardProvider provider,
    String adminUid,
    String employeeId,
    String month,
  ) {
    final payoutCtrl = TextEditingController();
    bool isProcessing = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AppModalDialog(
          icon: Icons.payments_rounded,
          iconColor: Colors.green,
          title: 'Bulk Payout — Mark as Paid',
          subtitle: 'Disburse all pending commissions for ${_getEmployeeName(provider.employees, employeeId)}.',
          maxWidth: 440,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.green, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Period: ${DateFormat.yMMM().format(DateTime.parse('$month-01'))}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: payoutCtrl,
                enabled: !isProcessing,
                decoration: const InputDecoration(
                  labelText: 'Payout Reference (UTR / Txn ID) *',
                  hintText: 'e.g. UTIB1234567890',
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 12),
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              onPressed: isProcessing
                  ? null
                  : () async {
                      final ref = payoutCtrl.text.trim();
                      if (ref.isEmpty) {
                        setDlgState(() => dialogError = 'Payout reference is required.');
                        return;
                      }
                      setDlgState(() {
                        isProcessing = true;
                        dialogError = null;
                      });
                      try {
                        final result = await provider.markCommissionsPaidBulk(
                          employeeId: employeeId,
                          month: month,
                          payoutReference: ref,
                          adminUid: adminUid,
                        );
                        final count = result['count'] ?? 0;
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ $count commissions marked as paid.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlgState(() {
                            isProcessing = false;
                            dialogError = 'Error: $e';
                          });
                        }
                      }
                    },
              child: isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Mark All as Paid'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED RESPONSIVE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _CommissionCard extends StatelessWidget {
  final EmployeeCommissionModel commission;
  const _CommissionCard({required this.commission});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPaid = commission.isPaid;
    final dateFormat = DateFormat('d MMM yyyy');
    final employeeName = context.watch<AdminDashboardProvider>().resolveEmployeeName(commission.employeeId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaid
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Status Icon + Business Name + Amount & Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPaid ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                    color: isPaid ? const Color(0xFF059669) : const Color(0xFFD97706),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        commission.businessName.isNotEmpty
                            ? commission.businessName
                            : 'Business #${commission.businessId.substring(0, commission.businessId.length > 8 ? 8 : commission.businessId.length)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded, size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              employeeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${commission.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isPaid ? const Color(0xFF059669) : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    AppBadge.commission(commission.status),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 6),
            // Bottom Info Row: Activation Date + Payout Reference
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (commission.createdAt != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_available_rounded, size: 13, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        'Activated: ${dateFormat.format(commission.createdAt!)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                if (isPaid && commission.payoutReference != null && commission.payoutReference!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_rounded, size: 12, color: Color(0xFF475569)),
                        const SizedBox(width: 4),
                        Text(
                          'Ref: ${commission.payoutReference}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
