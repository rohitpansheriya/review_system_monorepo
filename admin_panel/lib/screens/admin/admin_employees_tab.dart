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
import '../../core/phone_field.dart';
import '../../models/employee_profile_model.dart';
import '../../providers/admin_dashboard_provider.dart';

class AdminEmployeesTab extends StatelessWidget {
  const AdminEmployeesTab({super.key});

  void _showCreateEmployeeDialog(BuildContext context, AdminDashboardProvider provider) {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String rawPhone = '';

    showDialog(
      context: context,
      builder: (ctx) {
        String? nameError;
        String? emailError;
        String? phoneError;
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Employee'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
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
                      decoration: InputDecoration(
                        labelText: 'Full Name *',
                        errorText: nameError,
                      ),
                      onChanged: (_) {
                        if (nameError != null) setDialogState(() => nameError = null);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: InputDecoration(
                        labelText: 'Email Address *',
                        errorText: emailError,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (emailError != null) setDialogState(() => emailError = null);
                      },
                    ),
                    const SizedBox(height: 12),
                    PhoneField(
                      label: 'Phone / WhatsApp Number (+91)',
                      initialValue: rawPhone,
                      helperText: '10-digit Indian mobile number',
                      showError: phoneError != null,
                      errorText: phoneError,
                      onChanged: (val) {
                        rawPhone = val;
                        if (phoneError != null) setDialogState(() => phoneError = null);
                      },
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
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final email = emailCtrl.text.trim();

                          setDialogState(() {
                            nameError = name.isEmpty ? 'Full Name is required.' : null;
                            emailError = email.isEmpty
                                ? 'Email Address is required.'
                                : (!email.contains('@') ? 'Enter a valid email address.' : null);

                            if (rawPhone.trim().isNotEmpty) {
                              final cleanDigits = rawPhone.replaceAll(RegExp(r'\D'), '');
                              final phoneDigits = cleanDigits.startsWith('91') && cleanDigits.length > 10
                                  ? cleanDigits.substring(2)
                                  : cleanDigits;
                              if (phoneDigits.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(phoneDigits)) {
                                phoneError = 'Enter a valid 10-digit phone number starting with 6–9.';
                              } else {
                                phoneError = null;
                              }
                            } else {
                              phoneError = null;
                            }
                          });

                          if (nameError != null || emailError != null || phoneError != null) {
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          try {
                            await provider.createEmployee(
                              email: email,
                              displayName: name,
                              phone: rawPhone.trim(),
                              address: addressCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
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
                            final errStr = e.toString();
                            setDialogState(() {
                              isSubmitting = false;
                              if (errStr.toLowerCase().contains('email')) {
                                emailError = errStr.replaceAll('Exception:', '').trim();
                              } else {
                                emailError = errStr.replaceAll('Exception:', '').trim();
                              }
                            });
                          }
                        },
                  label: Text(isSubmitting ? 'Creating…' : 'Create & Send Setup Email'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final employees = provider.employees;
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Employee Management',
                    style: (isDesktop ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage sales reps, track enrollments, review KYC, and offboarding.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showCreateEmployeeDialog(context, provider),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Employee'),
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
                        padding: EdgeInsets.all(isDesktop ? 20.0 : 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Metrics row
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _buildMetricBox(context, 'Total Enrollments', '${provider.employeeTotalEnrollments[emp.uid] ?? 0}'),
                                _buildMetricBox(context, 'This Month', '${provider.employeeThisMonthEnrollments[emp.uid] ?? 0}'),
                                _buildMetricBox(context, 'Managed', '${provider.employeeManagedCount[emp.uid] ?? 0}'),
                                _buildMetricBox(context, 'Pending Comm.', '₹${comms['pending']?.toStringAsFixed(0) ?? '0'}'),
                                _buildMetricBox(context, 'Paid Comm.', '₹${comms['paid']?.toStringAsFixed(0) ?? '0'}'),
                              ],
                            ),
                            const Divider(height: 32),

                            // Document & Payout Verification Action
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'KYC Document Status: ${emp.documentsVerified.toUpperCase()}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
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

                            // Actions Row (Resend Password Setup Email + Offboard)
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    try {
                                      await provider.sendPasswordResetLink(emp.email);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Password setup/reset email sent to ${emp.email}'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Failed to send email: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.lock_reset, size: 16),
                                  label: const Text('Resend Password Setup Link'),
                                ),
                                if (emp.isActive)
                                  OutlinedButton.icon(
                                    onPressed: () => _confirmOffboard(context, provider, emp),
                                    icon: const Icon(Icons.person_off, size: 16),
                                    label: const Text('Offboard Employee'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: colorScheme.error,
                                      side: BorderSide(color: colorScheme.error),
                                    ),
                                  ),
                              ],
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

    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _confirmOffboard(BuildContext context, AdminDashboardProvider provider, EmployeeProfileModel emp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Deactivate ${emp.name}?'),
        content: Text(
          'Deactivating ${emp.name} will disable their login and mark their profile inactive.\n\nAll their enrolled businesses remain intact and fully managed by Admin. Historical enrollment and commission records are preserved for payroll and audit.',
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
                  SnackBar(content: Text('${emp.name} deactivated. Enrolled businesses remain managed by Admin.')),
                );
              }
            },
            child: const Text('Confirm Deactivation'),
          ),
        ],
      ),
    );
  }
}
