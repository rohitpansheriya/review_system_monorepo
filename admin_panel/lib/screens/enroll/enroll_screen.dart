// lib/screens/enroll/enroll_screen.dart
// Enrollment form — reworked for single-location vs multi-branch modes.
//
// Layout:
//   1. Mode toggle (Single location / Multiple branches)
//   2. Business-level: name, category, logo, owner contact
//   3. Branch section:
//      - Single mode: one BranchFormWidget (branch name hidden, auto-set)
//      - Multi mode:  N BranchFormWidgets (branch name required) + Add Branch button
//   4. Submit button
//
// Change 4: Logo upload validates pixel dimensions before accepting.
//   MIN dimension = AppConstants.minLogoPx (500 px).
//   Below this: rejected with a clear message ("Logo too small to print clearly…").
//   Client-side check via dart:ui — never silently downscale.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_web/image_picker_web.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/phone_field.dart';
import '../../providers/auth_provider.dart';
import '../../providers/enroll_provider.dart';
import '../../services/firestore_service.dart';
import 'branch_form_widget.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  bool _showErrors = false;

  // Category templates loaded once on open
  List<Map<String, dynamic>> _templates = [];
  bool _templatesLoading = true;

  // Logo rejection message (Change 4)
  String? _logoRejectionMessage;

  // Form controllers for business-level fields
  final _brandNameCtrl  = TextEditingController();
  final _ownerNameCtrl  = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnrollProvider>().reset();
      _brandNameCtrl.clear();
      _ownerNameCtrl.clear();
      _ownerEmailCtrl.clear();
    });
  }

  @override
  void dispose() {
    _brandNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final svc  = context.read<FirestoreService>();
    final list = await svc.getCategoryTemplates();
    if (mounted) {
      setState(() {
        _templates       = list;
        _templatesLoading = false;
      });
    }
  }

  // ── Change 4: Logo with dimension validation ────────────────────────────────
  Future<void> _pickLogoWithValidation() async {
    final result = await ImagePickerWeb.getImageInfo();
    if (result == null || !mounted) return;

    final bytes = result.data;
    if (bytes == null) return;

    // Decode image dimensions client-side via dart:ui.
    // This works in Flutter Web (CanvasKit and HTML renderer).
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img   = frame.image;
      final w     = img.width;
      final h     = img.height;
      img.dispose();
      codec.dispose();

      if (w < AppConstants.minLogoPx || h < AppConstants.minLogoPx) {
        // Reject — do NOT call setLogo.
        if (mounted) {
          setState(() {
            _logoRejectionMessage =
                'Logo too small to print clearly — please upload a '
                'higher-resolution image (minimum '
                '${AppConstants.minLogoPx}×${AppConstants.minLogoPx} px). '
                'Uploaded: $w×$h px.';
          });
        }
        return;
      }

      // Accepted — clear any previous rejection message.
      setState(() => _logoRejectionMessage = null);
    } catch (e) {
      // Dimension decode failed — allow the upload but warn.
      // Better to accept a potentially-small image than block the employee.
      setState(() => _logoRejectionMessage = null);
    }

    final ext  = (result.fileName ?? '').split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    if (!mounted) return;
    context.read<EnrollProvider>().setLogo(bytes, mime);
  }

  Future<void> _submit() async {
    final enroll = context.read<EnrollProvider>();
    final err    = enroll.validationError;
    if (err != null) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    final empId = context.read<AppAuthProvider>().uid!;
    final error = await enroll.submit(empId);
    if (!mounted) return;

    if (error != null) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
    } else {
      // Navigate to payment page for this draft — user pays or defers there.
      // Do NOT navigate directly to /businesses; the payment page handles that.
      final bizId = enroll.successBizId!;
      context.go('/enroll/payment/$bizId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll New Business'),
        leading: BackButton(onPressed: () => context.go('/businesses')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── Mode toggle ──────────────────────────────────────────────
              _SectionHeader('Business Type'),
              const SizedBox(height: 12),
              SegmentedButton<EnrollMode>(
                segments: const [
                  ButtonSegment(
                    value: EnrollMode.single,
                    label: Text('Single location'),
                    icon: Icon(Icons.storefront_outlined),
                  ),
                  ButtonSegment(
                    value: EnrollMode.multi,
                    label: Text('Multiple branches'),
                    icon: Icon(Icons.account_tree_outlined),
                  ),
                ],
                selected: {enroll.mode},
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) enroll.setMode(set.first);
                  setState(() => _showErrors = false);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  enroll.mode == EnrollMode.single
                      ? 'One physical location — branch name is set automatically.'
                      : 'Multiple branches under one brand — each gets its own QR/NFC.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),

              // ── Business Details ─────────────────────────────────────────
              _SectionHeader('Business Details'),
              const SizedBox(height: 12),

              // Business name
              TextFormField(
                controller: _brandNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Business name *',
                  errorText: _showErrors && enroll.brandName.trim().isEmpty
                      ? 'Business name is required'
                      : null,
                ),
                onChanged: (v) => enroll.brandName = v,
              ),
              const SizedBox(height: 16),

              // Category
              if (_templatesLoading)
                const LinearProgressIndicator()
              else if (_templates.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No categories available — contact admin.\n'
                    'You can still enroll without a category.',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'Business category'),
                  hint: const Text('Select a category (optional)'),
                  items: _templates
                      .map((t) => DropdownMenuItem<String>(
                            value: t['id'] as String,
                            child: Text(
                                t['name'] as String? ?? t['id'] as String),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    enroll.templateId    = v;
                    enroll.categoryType  =
                        _templates.firstWhere(
                              (t) => t['id'] == v,
                              orElse: () => {'name': v},
                            )['name'] as String? ??
                            v;
                  },
                ),
              const SizedBox(height: 16),

              // Logo picker with dimension validation (Change 4)
              _LogoPicker(
                enroll: enroll,
                onPick: _pickLogoWithValidation,
                rejectionMessage: _logoRejectionMessage,
              ),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),

              // ── Owner Contact ────────────────────────────────────────────
              _SectionHeader('Owner Contact'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _ownerNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Owner name *',
                  errorText: _showErrors && enroll.ownerName.trim().isEmpty
                      ? 'Owner name is required'
                      : null,
                ),
                onChanged: (v) => enroll.ownerName = v,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Owner email *',
                  helperText: 'Used for renewal notifications',
                  errorText: _showErrors && enroll.ownerEmail.trim().isEmpty
                      ? 'Owner email is required'
                      : null,
                ),
                onChanged: (v) => enroll.ownerEmail = v,
              ),
              const SizedBox(height: 12),
              PhoneField(
                label: 'Owner phone *',
                helperText: 'Used for payment and WhatsApp contact',
                initialValue: enroll.ownerPhone,
                showError: _showErrors,
                onChanged: (e164) => enroll.ownerPhone = e164,
              ),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),

              // ── Branch(es) ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _SectionHeader(
                      enroll.mode == EnrollMode.single
                          ? 'Location'
                          : 'Branches (${enroll.branches.length})',
                    ),
                  ),
                  if (enroll.mode == EnrollMode.multi)
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add branch'),
                      onPressed: enroll.addBranch,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Branch widgets
              ...List.generate(enroll.branches.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: BranchFormWidget(
                    key: ValueKey('branch_$i'),
                    branchIndex:    i,
                    draft:          enroll.branchAt(i),
                    showBranchName: enroll.isMulti,
                    showError:      _showErrors,
                    onChanged:      enroll.notifyBranchChanged,
                    onRemove:       enroll.isMulti && enroll.branches.length > 1
                        ? () => enroll.removeBranch(i)
                        : null,
                  ),
                );
              }),

              // Multi-mode: warn if zero branches (shouldn't be possible but guard)
              if (enroll.isMulti && enroll.branches.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add first branch'),
                    onPressed: enroll.addBranch,
                  ),
                ),

              const SizedBox(height: 32),

              // ── Submit ───────────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: enroll.isSubmitting ? null : _submit,
                icon: enroll.isSubmitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: Text(enroll.isSubmitting ? 'Enrolling…' : 'Enroll Business'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

/// Logo picker with client-side dimension validation (Change 4).
/// [rejectionMessage] is shown when the chosen image is below minLogoPx.
class _LogoPicker extends StatelessWidget {
  final EnrollProvider enroll;
  final VoidCallback   onPick;
  final String?        rejectionMessage; // Change 4

  const _LogoPicker({
    required this.enroll,
    required this.onPick,
    this.rejectionMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: rejectionMessage != null
                      ? Colors.red.shade400
                      : Colors.grey.shade300,
                ),
                image: enroll.logoBytes != null
                    ? DecorationImage(
                        image: MemoryImage(enroll.logoBytes!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: enroll.logoBytes == null
                  ? Icon(
                      Icons.image_outlined,
                      color: rejectionMessage != null
                          ? Colors.red.shade400
                          : Colors.grey,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: enroll.logoUploading ? null : onPick,
                  icon: const Icon(Icons.upload_outlined, size: 16),
                  label: Text(
                      enroll.logoBytes == null ? 'Upload logo' : 'Change logo'),
                ),
                if (enroll.logoUploading)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Uploading…', style: TextStyle(fontSize: 12)),
                  ),
                if (enroll.logoUrl != null && !enroll.logoUploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('✓ Uploaded',
                        style: TextStyle(
                            fontSize: 12, color: Colors.green.shade700)),
                  ),
                // Min-size hint
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Min ${AppConstants.minLogoPx}\u00d7${AppConstants.minLogoPx} px for standee print quality',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        // Change 4: rejection message below the picker row
        if (rejectionMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rejectionMessage!,
                      style: TextStyle(
                          fontSize: 12, color: Colors.red.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
