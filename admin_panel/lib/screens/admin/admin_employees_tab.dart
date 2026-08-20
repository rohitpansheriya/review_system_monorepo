// lib/screens/admin/admin_employees_tab.dart
//
// Employee Management Tab for Platform Admin (Doc 04).
// Features:
//   - Create employee Auth accounts & profiles.
//   - List employees with enrollment metrics, managed businesses, and commission summary.
//   - Employee Offboarding: Deactivating bulk-reassigns businesses to "admin" (preserving enrolled_by_original).
//   - Document & Payout Verification: Admin marks documents_verified = "verified" / "rejected".

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/employee_profile_model.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminEmployeesTab extends StatelessWidget {
  const AdminEmployeesTab({super.key});

  void _showCreateEmployeeDialog(BuildContext context, AdminDashboardProvider provider) {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Employee Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A password-setup email will be sent automatically so the employee sets their own secure password.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email Address *'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone Number (+91)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            onPressed: () async {
              if (emailCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all required fields (Name and Email).')),
                );
                return;
              }
              final email = emailCtrl.text.trim();
              final name = nameCtrl.text.trim();
              Navigator.of(ctx).pop();
              try {
                await provider.createEmployee(
                  email: email,
                  displayName: name,
                  phone: phoneCtrl.text.trim(),
                  address: addressCtrl.text.trim(),
                );
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (successCtx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.mark_email_read, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Employee Created'),
                        ],
                      ),
                      content: Text(
                        'Employee account for "$name" was created successfully!\n\n'
                        'A password-setup email has been sent to:\n$email\n\n'
                        'The employee can click the link in the email to set their password and log in.',
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.of(successCtx).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            label: const Text('Create & Send Setup Email'),
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
    final employees = provider.employees;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employee Management',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage sales reps, track enrollments, review KYC, and offboarding.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showCreateEmployeeDialog(context, provider),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (employees.isEmpty)
            const Center(child: Text('No employees found.'))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: employees.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final emp = employees[index];
                final businesses = provider.employeeBusinesses[emp.uid] ?? [];
                final comms = provider.employeeCommissionSummaries[emp.uid] ?? {'pending': 0, 'paid': 0};

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: emp.isActive ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                      child: Icon(
                        emp.isActive ? Icons.person : Icons.person_off,
                        color: emp.isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      emp.name.isNotEmpty ? emp.name : emp.email,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      '${emp.email} • Phone: ${emp.phone.isNotEmpty ? emp.phone : "N/A"} • Status: ${emp.status.toUpperCase()}',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: emp.documentsVerified == 'verified'
                            ? Colors.green.withValues(alpha: 0.15)
                            : (emp.documentsVerified == 'rejected' ? Colors.red.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Docs: ${emp.documentsVerified}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: emp.documentsVerified == 'verified'
                              ? Colors.green
                              : (emp.documentsVerified == 'rejected' ? Colors.red : Colors.orange),
                        ),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Metrics row
                            Row(
                              children: [
                                _buildMetricBox(context, 'Total Enrollments', '${provider.employeeTotalEnrollments[emp.uid] ?? 0}'),
                                const SizedBox(width: 12),
                                _buildMetricBox(context, 'This Month', '${provider.employeeThisMonthEnrollments[emp.uid] ?? 0}'),
                                const SizedBox(width: 12),
                                _buildMetricBox(context, 'Managed', '${provider.employeeManagedCount[emp.uid] ?? 0}'),
                                const SizedBox(width: 12),
                                _buildMetricBox(context, 'Pending Commission', '₹${comms['pending']?.toStringAsFixed(0) ?? '0'}'),
                                const SizedBox(width: 12),
                                _buildMetricBox(context, 'Paid Commission', '₹${comms['paid']?.toStringAsFixed(0) ?? '0'}'),
                              ],
                            ),
                            const Divider(height: 32),

                            // Document & Payout Verification Action
                            Row(
                              children: [
                                Text(
                                  'KYC Document Status: ${emp.documentsVerified.toUpperCase()}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await provider.verifyEmployeeDocuments(
                                      employeeUid: emp.uid,
                                      status: 'rejected',
                                    );
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                  label: const Text('Reject KYC Docs'),
                                  style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await provider.verifyEmployeeDocuments(
                                      employeeUid: emp.uid,
                                      status: 'verified',
                                    );
                                  },
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Verify KYC Docs'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                ),
                              ],
                            ),

                            const Divider(height: 32),

                            // Managed Businesses List
                            Text(
                              'Managed Businesses (${businesses.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (businesses.isEmpty)
                              const Text('No active businesses currently managed by this employee.')
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: businesses.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 6),
                                itemBuilder: (context, bIdx) {
                                  final biz = businesses[bIdx];
                                  return ListTile(
                                    dense: true,
                                    title: Text(biz.brandName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('Status: ${biz.subscriptionStatus} • Category: ${biz.categoryType}'),
                                    trailing: const Icon(Icons.chevron_right, size: 20),
                                    onTap: () => context.push('/business/${biz.id}', extra: biz),
                                  );
                                },
                              ),

                            const SizedBox(height: 24),

                            // Offboarding / Deactivate Action
                            if (emp.isActive)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _confirmOffboard(context, provider, emp),
                                  icon: const Icon(Icons.person_off),
                                  label: const Text('Offboard Employee'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colorScheme.error,
                                    side: BorderSide(color: colorScheme.error),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMetricBox(BuildContext context, String label, String value) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _confirmOffboard(BuildContext context, AdminDashboardProvider provider, EmployeeProfileModel emp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Offboard ${emp.name}?'),
        content: Text(
          'Deactivating ${emp.name} will bulk-update all their managed businesses to currently_managed_by="admin".\n\nOriginal enrollment records (enrolled_by_original) are preserved per system rules. No other employee will inherit their accounts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.deactivateEmployee(emp.uid);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${emp.name} offboarded. Managed businesses reassigned to Admin.')),
                );
              }
            },
            child: const Text('Confirm Offboard'),
          ),
        ],
      ),
    );
  }
}
