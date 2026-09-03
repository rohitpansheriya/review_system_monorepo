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
import '../../widgets/app_animated_loader.dart';

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
    final anchor = html.AnchorElement(href: url)
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

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.file_download_outlined, color: Color(0xFF4F46E5)),
                SizedBox(width: 10),
                Text('Export Bulk Payout CSV'),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
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
            ),
            actions: [
              TextButton(
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

    // Generate month options (last 12 months)
    final now = DateTime.now();
    final months = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - i);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });

    return Column(
      children: [
        // ── Filters & Actions ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Employee filter
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        value: _selectedEmployeeId,
                        decoration: const InputDecoration(
                          labelText: 'Employee',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Employees'),
                          ),
                          ...employees.map(
                            (e) => DropdownMenuItem<String?>(
                              value: e.uid,
                              child: Text(e.name),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedEmployeeId = v),
                      ),
                    ),
                    // Status filter
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'pending', child: Text('Pending')),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                        ],
                        onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                      ),
                    ),
                    // Month filter
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String?>(
                        value: _monthFilter,
                        decoration: const InputDecoration(
                          labelText: 'Month',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
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
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── One-Click Payout Button ─────────────────────────────────
        if (_selectedEmployeeId != null && _monthFilter != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    () => _showBulkPayoutDialog(
                      context,
                      provider,
                      adminUid,
                      _selectedEmployeeId!,
                      _monthFilter!,
                    ),
                icon: const Icon(Icons.payments),
                label: Text(
                  'Pay All Pending for ${_getEmployeeName(employees, _selectedEmployeeId!)} — '
                  '${DateFormat.yMMM().format(DateTime.parse('$_monthFilter-01'))}',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

        const SizedBox(height: 8),

        // ── Commission List ───────────────────────────────────────
        Expanded(child: _buildCommissionStream(context, provider, scheme)),
      ],
    );
  }

  Widget _buildCommissionStream(
    BuildContext context,
    AdminDashboardProvider provider,
    ColorScheme scheme,
  ) {
    // Choose the right stream based on filters
    final Stream<List<EmployeeCommissionModel>> stream;
    if (_selectedEmployeeId != null) {
      stream = provider.watchEmployeeCommissions(
        _selectedEmployeeId!,
        statusFilter: _statusFilter == 'all' ? null : _statusFilter,
        monthFilter: _monthFilter,
      );
    } else {
      if (_statusFilter == 'pending') {
        stream = provider.watchAllPendingCommissions(monthFilter: _monthFilter);
      } else {
        // For 'all' or 'paid' without employee selection, we need to
        // use a broader query. Use pending stream for now and filter client-side.
        stream = provider.watchAllPendingCommissions(monthFilter: _monthFilter);
      }
    }

    return StreamBuilder<List<EmployeeCommissionModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 64,
                  color: scheme.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No commission records found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Commissions are created when employee-enrolled businesses activate.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Summary badges & Export Action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 16,
                    children: [
                      _SummaryBadge(
                        label: 'Total Records',
                        value: '${commissions.length}',
                        color: scheme.primary,
                      ),
                      _SummaryBadge(
                        label: 'Pending Payout',
                        value: '₹${totalPending.toStringAsFixed(0)}',
                        color: Colors.orange,
                      ),
                      _SummaryBadge(
                        label: 'Paid Out',
                        value: '₹${totalPaid.toStringAsFixed(0)}',
                        color: Colors.green,
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: commissions.isEmpty
                        ? null
                        : () => _showExportModal(context, commissions, provider.employees),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Export Payout CSV'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Bulk Payout — Mark All Pending as Paid'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee: ${_getEmployeeName(provider.employees, employeeId)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Month: ${DateFormat.yMMM().format(DateTime.parse('$month-01'))}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: payoutCtrl,
                  enabled: !isProcessing,
                  decoration: const InputDecoration(
                    labelText: 'Payout Reference (UTR / Transaction ID)',
                    hintText: 'e.g., UTIB1234567890',
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
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
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
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _CommissionCard extends StatelessWidget {
  final EmployeeCommissionModel commission;
  const _CommissionCard({required this.commission});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPaid = commission.isPaid;
    final dateFormat = DateFormat.yMMMd();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color:
              isPaid
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isPaid
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.15),
          child: Icon(
            isPaid ? Icons.check_circle : Icons.schedule,
            color: isPaid ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        title: Text(
          commission.businessName.isNotEmpty
              ? commission.businessName
              : commission.businessId,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee: ${context.watch<AdminDashboardProvider>().resolveEmployeeName(commission.employeeId)}',
            ),
            if (commission.createdAt != null)
              Text('Activated: ${dateFormat.format(commission.createdAt!)}'),
            if (isPaid && commission.payoutReference != null)
              Text(
                'UTR: ${commission.payoutReference}',
                style: const TextStyle(fontSize: 11),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${commission.amount.toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isPaid ? Colors.green : scheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isPaid
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isPaid ? 'PAID' : 'PENDING',
                style: TextStyle(
                  color: isPaid ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryBadge({
    required this.label,
    required this.value,
    required this.color,
  });

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
          Text('$label: ', style: TextStyle(fontSize: 12, color: color)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
