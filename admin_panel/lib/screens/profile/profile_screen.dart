// lib/screens/profile/profile_screen.dart
//
// My Profile / My Details screen (Screen 5 of 03-employee-panel.md).
// Employees maintain their personal details, payout preferences (Bank/UPI),
// and upload KYC / identification documents.
//
// VERIFICATION SAFEGUARD:
// Changing payout details or uploading/removing documents resets
// documents_verified to "pending" to prevent commission redirection fraud.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_web/image_picker_web.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/logout_helper.dart';
import '../../models/employee_profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── Controllers ──────────────────────────────────────────────────────────
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  late final TextEditingController _bankAccountCtrl;
  late final TextEditingController _bankIfscCtrl;
  late final TextEditingController _upiIdCtrl;

  PayoutMethod _selectedPayoutMethod = PayoutMethod.bank;
  String _selectedDocType = 'Aadhaar Card';

  bool _initialized = false;
  String? _profileMsg;
  String? _payoutMsg;
  String? _docMsg;

  static const _docTypes = [
    'Aadhaar Card',
    'PAN Card',
    'Bank Passbook / Cheque',
    'Driving License',
    'Voter ID',
    'Other KYC Document',
  ];

  @override
  void initState() {
    super.initState();
    _fullNameCtrl    = TextEditingController();
    _emailCtrl       = TextEditingController();
    _phoneCtrl       = TextEditingController();
    _addressCtrl     = TextEditingController();
    _bankAccountCtrl = TextEditingController();
    _bankIfscCtrl    = TextEditingController();
    _upiIdCtrl       = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AppAuthProvider>().uid;
      if (uid != null) {
        context.read<ProfileProvider>().startListening(uid);
      }
    });
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    _upiIdCtrl.dispose();
    super.dispose();
  }

  void _syncFromProfile(EmployeeProfileModel profile) {
    if (_initialized) return;
    _initialized         = true;
    _fullNameCtrl.text   = profile.fullName;
    _emailCtrl.text      = profile.email;
    _phoneCtrl.text      = profile.phone;
    _addressCtrl.text    = profile.address;
    _bankAccountCtrl.text = profile.bankAccountNo ?? '';
    _bankIfscCtrl.text   = profile.bankIfsc ?? '';
    _upiIdCtrl.text      = profile.upiId ?? '';
    _selectedPayoutMethod = profile.payoutMethod;
  }

  Future<void> _saveProfile() async {
    setState(() => _profileMsg = null);
    final provider = context.read<ProfileProvider>();
    final err = await provider.saveProfile(
      fullName: _fullNameCtrl.text,
      email:    _emailCtrl.text,
      phone:    _phoneCtrl.text,
      address:  _addressCtrl.text,
    );
    if (mounted) {
      if (err != null) {
        setState(() => _profileMsg = err);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile details updated'),
            backgroundColor: AppColors.activeFg,
          ),
        );
      }
    }
  }

  Future<void> _savePayout() async {
    setState(() => _payoutMsg = null);
    final provider = context.read<ProfileProvider>();
    final err = await provider.savePayoutDetails(
      payoutMethod:  _selectedPayoutMethod,
      bankAccountNo: _bankAccountCtrl.text,
      bankIfsc:      _bankIfscCtrl.text,
      upiId:         _upiIdCtrl.text,
    );
    if (mounted) {
      if (err != null) {
        setState(() => _payoutMsg = err);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Payout details updated (status reset to pending verification)'),
            backgroundColor: AppColors.pendingFg,
          ),
        );
      }
    }
  }

  Future<void> _uploadDoc() async {
    setState(() => _docMsg = null);
    final media = await ImagePickerWeb.getImageInfo();
    if (media == null || media.data == null || !mounted) return;

    final bytes    = media.data!;
    final fileName = media.fileName ?? 'document.jpg';
    final ext      = fileName.split('.').last.toLowerCase();
    final mime     = ext == 'pdf' ? 'application/pdf' : 'image/jpeg';

    final provider = context.read<ProfileProvider>();
    final err = await provider.uploadDocument(
      bytes:        bytes,
      mimeType:     mime,
      documentType: _selectedDocType,
    );

    if (mounted) {
      if (err != null) {
        setState(() => _docMsg = err);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Document uploaded successfully'),
            backgroundColor: AppColors.activeFg,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final profile  = provider.profile;
    final scheme   = Theme.of(context).colorScheme;

    _syncFromProfile(profile);

    final isVerified   = profile.isVerified;
    final statusBg     = isVerified ? AppColors.activeBg : AppColors.pendingBg;
    final statusFg     = isVerified ? AppColors.activeFg : AppColors.pendingFg;
    final statusLabel  = isVerified ? 'Verified' : 'Pending Verification';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile & Payout Details'),
        leading: BackButton(onPressed: () => context.go('/businesses')),
        actions: [
          IconButton(
            icon:    const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => confirmAndSignOut(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Verification Status Card ────────────────────────────────
                Card(
                  color: statusBg.withValues(alpha: 0.2),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          isVerified
                              ? Icons.verified_user_outlined
                              : Icons.gavel_outlined,
                          size: 32,
                          color: statusFg,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Account Status:',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(AppRadius.full),
                                      border: Border.all(color: statusFg.withValues(alpha: 0.5)),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: statusFg),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isVerified
                                    ? 'Your payout account and KYC documents are verified by admin.'
                                    : 'Payout is blocked until admin verifies your details and documents.\n'
                                      'Any change to payout or documents resets status to pending.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── 1. Profile Information ──────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal Details',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Divider(),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _fullNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full Name *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email Address *',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Mobile Phone *',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _addressCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Residential Address *',
                            prefixIcon: Icon(Icons.home_outlined),
                          ),
                        ),
                        if (_profileMsg != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_profileMsg!,
                              style: TextStyle(color: scheme.error, fontSize: 12)),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: provider.isSaving ? null : _saveProfile,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save Personal Details'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── 2. Payout Details ───────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commission Payout Account',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Select your preferred payment method for commission payouts.',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Divider(),
                        const SizedBox(height: AppSpacing.sm),
                        SegmentedButton<PayoutMethod>(
                          segments: const [
                            ButtonSegment(
                              value: PayoutMethod.bank,
                              label: Text('Bank Transfer'),
                              icon: Icon(Icons.account_balance_outlined),
                            ),
                            ButtonSegment(
                              value: PayoutMethod.upi,
                              label: Text('UPI Handle'),
                              icon: Icon(Icons.qr_code_outlined),
                            ),
                          ],
                          selected: {_selectedPayoutMethod},
                          onSelectionChanged: (s) {
                            if (s.isNotEmpty) {
                              setState(() => _selectedPayoutMethod = s.first);
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_selectedPayoutMethod == PayoutMethod.bank) ...[
                          TextFormField(
                            controller: _bankAccountCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bank Account Number *',
                              prefixIcon: Icon(Icons.numbers_outlined),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _bankIfscCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bank IFSC Code *',
                              prefixIcon: Icon(Icons.code_outlined),
                              hintText: 'e.g. SBIN0001234',
                            ),
                          ),
                        ] else ...[
                          TextFormField(
                            controller: _upiIdCtrl,
                            decoration: const InputDecoration(
                              labelText: 'VPA / UPI ID *',
                              prefixIcon: Icon(Icons.alternate_email_outlined),
                              hintText: 'name@upi or mobile@paytm',
                            ),
                          ),
                        ],
                        if (_payoutMsg != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_payoutMsg!,
                              style: TextStyle(color: scheme.error, fontSize: 12)),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: provider.isSaving ? null : _savePayout,
                            icon: const Icon(Icons.payment_outlined),
                            label: const Text('Save Payout Details'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── 3. KYC Documents ────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KYC & Verification Documents',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Upload valid ID/KYC documents for commission verification.',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Divider(),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedDocType,
                                decoration: const InputDecoration(
                                  labelText: 'Document Type',
                                  isDense: true,
                                ),
                                items: _docTypes
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _selectedDocType = v);
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            ElevatedButton.icon(
                              onPressed: provider.uploading ? null : _uploadDoc,
                              icon: provider.uploading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.upload_file_outlined),
                              label: Text(provider.uploading ? 'Uploading…' : 'Upload Document'),
                            ),
                          ],
                        ),
                        if (_docMsg != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_docMsg!,
                              style: TextStyle(color: scheme.error, fontSize: 12)),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        if (profile.documents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                            child: Center(
                              child: Text(
                                'No documents uploaded yet.',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: profile.documents.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
                            itemBuilder: (context, index) {
                              final doc = profile.documents[index];
                              final dateStr = doc.uploadedAt != null
                                  ? DateFormat('d MMM yyyy, HH:mm').format(doc.uploadedAt!)
                                  : 'Just now';
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  doc.storagePath.endsWith('.pdf')
                                      ? Icons.picture_as_pdf_outlined
                                      : Icons.image_outlined,
                                  color: scheme.primary,
                                ),
                                title: Text(doc.documentType,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Uploaded: $dateStr · ${doc.storagePath}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.open_in_new, size: 18),
                                      tooltip: 'View Document',
                                      onPressed: () async {
                                        final url = await provider.getDocumentUrl(doc.storagePath);
                                        if (url != null) {
                                          html.window.open(url, '_blank');
                                        } else {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: const Text('Failed to load document URL'),
                                                backgroundColor: scheme.error,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          size: 18, color: scheme.error),
                                      tooltip: 'Remove',
                                      onPressed: () => provider.removeDocument(doc.storagePath),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── Admin Verification STUB Notice ─────────────────────────
                Card(
                  color: scheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            '📌 STUB Notice: Admin Verification UI (Doc 04) is pending build.\n'
                            'Admin will verify employee KYC & payout changes via Firestore console or the admin panel.',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
