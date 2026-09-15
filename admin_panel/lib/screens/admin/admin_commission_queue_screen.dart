import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
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

        // ── Commission List & Summaries ───────────────────────────
        Expanded(child: _buildCommissionStream(context, provider, scheme, isMobile, adminUid)),
      ],
    );
  }

  Widget _buildCommissionStream(
    BuildContext context,
    AdminDashboardProvider provider,
    ColorScheme scheme,
    bool isMobile,
    String adminUid,
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

        Widget? bulkPayButton;
        if (_selectedEmployeeId != null) {
          final empName = _getEmployeeName(provider.employees, _selectedEmployeeId!);
          final empPendingList = commissions.where((c) => c.isPending && (c.employeeId == _selectedEmployeeId)).toList();
          final empPendingCount = empPendingList.length;
          final empPendingAmount = empPendingList.fold<double>(0, (sum, c) => sum + c.amount);

          bulkPayButton = SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: empPendingCount == 0
                  ? null
                  : () => _showBulkPayoutDialog(
                        context: context,
                        provider: provider,
                        adminUid: adminUid,
                        employeeId: _selectedEmployeeId!,
                        month: _monthFilter ?? (empPendingList.isNotEmpty && empPendingList.first.activationMonth.isNotEmpty ? empPendingList.first.activationMonth : DateFormat('yyyy-MM').format(DateTime.now())),
                        commissions: commissions,
                        pendingAmount: empPendingAmount,
                        pendingCount: empPendingCount,
                      ),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: Text(
                empPendingCount > 0
                    ? 'Pay All Pending (₹${empPendingAmount.toStringAsFixed(0)} • $empPendingCount ${empPendingCount == 1 ? "branch" : "branches"}) for $empName'
                    : 'All Commissions Paid for $empName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFF1F5F9),
                disabledForegroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          );
        }

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
                        if (bulkPayButton != null) ...[
                          const SizedBox(height: 8),
                          bulkPayButton,
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: summaryBadges),
                            const SizedBox(width: 16),
                            exportButton,
                          ],
                        ),
                        if (bulkPayButton != null) ...[
                          const SizedBox(height: 8),
                          bulkPayButton,
                        ],
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

  void _showBulkPayoutDialog({
    required BuildContext context,
    required AdminDashboardProvider provider,
    required String adminUid,
    required String employeeId,
    required String month,
    double? pendingAmount,
    int? pendingCount,
    List<EmployeeCommissionModel>? commissions,
  }) {
    final payoutCtrl = TextEditingController();
    bool isProcessing = false;
    String? dialogError;

    final employee = provider.employees.where((e) => e.uid == employeeId).firstOrNull;
    final empName = employee?.name ?? _getEmployeeName(provider.employees, employeeId);
    final monthDate = DateTime.tryParse('$month-01') ?? DateTime.now();
    final monthFormatted = (month.isNotEmpty && month != 'all')
        ? DateFormat.yMMMM().format(monthDate)
        : DateFormat.yMMMM().format(DateTime.now());

    final commList = commissions ?? [];
    final pendingList = commList
        .where((c) =>
            c.isPending &&
            (employeeId.isEmpty || c.employeeId == employeeId))
        .toList();

    final actualCount = pendingList.isNotEmpty
        ? pendingList.length
        : (pendingCount ?? 0);
    final actualAmount = pendingList.isNotEmpty
        ? pendingList.fold<double>(0, (s, c) => s + c.amount)
        : (pendingAmount ?? (actualCount * AppConstants.commissionAmountPerActivation));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AppModalDialog(
          icon: Icons.payments_rounded,
          iconColor: const Color(0xFF059669),
          title: 'Disburse Batch Payout',
          subtitle: 'Verify bank beneficiary details and submit the transaction reference ID.',
          maxWidth: 520,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Employee Info & KYC Badge Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF059669),
                        child: Text(
                          empName.isNotEmpty ? empName[0].toUpperCase() : 'E',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              empName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              employee?.phone ?? employee?.email ?? 'ID: ${employeeId.substring(0, employeeId.length > 8 ? 8 : employeeId.length)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      if (employee != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: employee.documentsVerified == 'verified'
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: employee.documentsVerified == 'verified'
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                employee.documentsVerified == 'verified'
                                    ? Icons.verified_rounded
                                    : Icons.pending_rounded,
                                size: 12,
                                color: employee.documentsVerified == 'verified'
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFD97706),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                employee.documentsVerified == 'verified' ? 'KYC Verified' : 'KYC Pending',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: employee.documentsVerified == 'verified'
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Unified Summary Metrics Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Row: Payout Period & Activations
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF475569)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Payout Period',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        monthFormatted,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F172A)),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFFE2E8F0), margin: const EdgeInsets.symmetric(horizontal: 8)),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.storefront_rounded, size: 14, color: Color(0xFF475569)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Activations',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$actualCount ${actualCount == 1 ? "branch" : "branches"}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F172A)),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Bottom Highlighted Payout Amount Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.account_balance_wallet_rounded, size: 16, color: Color(0xFF059669)),
                                SizedBox(width: 6),
                                Text(
                                  'Total Payout Amount',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                                ),
                              ],
                            ),
                            Text(
                              '₹${actualAmount.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF047857)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Beneficiary Payout Destination Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance_rounded, size: 15, color: Color(0xFF334155)),
                              SizedBox(width: 6),
                              Text(
                                'Beneficiary Bank / UPI Details',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF334155)),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              employee?.payoutMethod.label ?? 'Bank IMPS',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (employee != null && employee.bankAccountNo != null && employee.bankAccountNo!.isNotEmpty) ...[
                        _buildCopyableDetailRow(
                          context: context,
                          label: 'Account No',
                          value: employee.bankAccountNo!,
                        ),
                        const SizedBox(height: 8),
                        _buildCopyableDetailRow(
                          context: context,
                          label: 'IFSC Code',
                          value: employee.bankIfsc ?? '—',
                        ),
                      ],
                      if (employee != null && employee.upiId != null && employee.upiId!.isNotEmpty) ...[
                        if (employee.bankAccountNo != null && employee.bankAccountNo!.isNotEmpty)
                          const SizedBox(height: 8),
                        _buildCopyableDetailRow(
                          context: context,
                          label: 'UPI VPA',
                          value: employee.upiId!,
                        ),
                      ],
                      if (employee == null ||
                          ((employee.bankAccountNo == null || employee.bankAccountNo!.isEmpty) &&
                              (employee.upiId == null || employee.upiId!.isEmpty))) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFD97706)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'No bank account or UPI details configured in profile.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Payment Reference Form Input
                TextField(
                  controller: payoutCtrl,
                  enabled: !isProcessing,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Payout Reference (UTR / IMPS / Txn ID) *',
                    hintText: 'e.g. UTIB20260914992 or 423984029381',
                    prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                    helperText: 'Permanent audit record for all $actualCount commission items.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                isProcessing ? 'Recording…' : 'Mark as Paid (₹${actualAmount.toStringAsFixed(0)})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: isProcessing
                  ? null
                  : () async {
                      final ref = payoutCtrl.text.trim();
                      if (ref.isEmpty) {
                        setDlgState(() => dialogError = 'Please enter the transaction reference / UTR number.');
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
                              content: Text('✅ $count commissions marked as paid (Ref: $ref).'),
                              backgroundColor: const Color(0xFF059669),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyableDetailRow({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          const Text(' : ', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
          const SizedBox(width: 2),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📋 Copied $label: $value'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1E293B),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 12, color: Color(0xFF4F46E5)),
                  SizedBox(width: 4),
                  Text(
                    'Copy',
                    style: TextStyle(fontSize: 11, color: Color(0xFF4F46E5), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                              maxLines: 1,
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
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
