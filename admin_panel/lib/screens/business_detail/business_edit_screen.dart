// lib/screens/business_detail/business_edit_screen.dart
//
// Inline edit of an enrolled business's detail fields.
// Reuses BranchFormWidget (from enrollment) for branch editing — no fork.
//
// EDITABLE (employee):
//   Business: brand_name, logo_url, category_type, default_category_template_id,
//             owner_name, owner_email, owner_phone
//   Branch:   branch_name, address, whatsapp_number, whatsapp_monitored_by,
//             place_id, star_routing_config, category_override_id, standee_status
//
// NOT EDITABLE (payment/lifecycle owned):
//   subscription_status, renewal_date, grace_period_ends,
//   enrolled_by, enrolled_by_original, owner_auth_uid,
//   qr_code_id, nfc_tag_id (generated on activation)
//
// Works for BOTH pending_payment and active businesses — restriction is on
// which FIELDS, not on status.


import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/phone_field.dart';
import '../../models/branch_draft.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../enroll/branch_form_widget.dart';

class BusinessEditScreen extends StatefulWidget {
  final BusinessModel business;
  const BusinessEditScreen({super.key, required this.business});

  @override
  State<BusinessEditScreen> createState() => _BusinessEditScreenState();
}

class _BusinessEditScreenState extends State<BusinessEditScreen> {
  // ── Form state ──────────────────────────────────────────────────────────
  final _formKey        = GlobalKey<FormState>();
  late final TextEditingController _brandNameCtrl;
  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _ownerEmailCtrl;
  // _ownerPhoneCtrl replaced by PhoneField — value stored in _ownerPhoneE164
  String _ownerPhoneE164 = '';

  // ── Template / category ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _templates = [];
  bool   _templatesLoading = true;
  String _selectedCategoryType = '';
  String? _selectedTemplateId;

  // ── Logo ─────────────────────────────────────────────────────────────────
  String _logoUrl = '';
  // _uploadingLogo / _logoRejection removed — logo upload is stubbed (StorageService not wired)

  // ── Branches ─────────────────────────────────────────────────────────────
  List<BranchDraft> _branchDrafts = [];
  List<String>      _branchIds    = [];
  bool   _branchesLoading = true;
  bool   _showErrors      = false;

  // ── Save ─────────────────────────────────────────────────────────────────
  bool    _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final biz = widget.business;
    _brandNameCtrl  = TextEditingController(text: biz.brandName);
    _ownerNameCtrl  = TextEditingController(text: biz.ownerName  ?? '');
    _ownerEmailCtrl = TextEditingController(text: biz.ownerEmail ?? '');
    // _ownerPhoneCtrl removed — PhoneField initialises from _ownerPhoneE164
    _ownerPhoneE164 = biz.ownerPhone ?? '';
    _selectedCategoryType = biz.categoryType;
    _selectedTemplateId   = null;
    _logoUrl              = biz.logoUrl;

    _loadTemplates();
    _loadBranches();
  }

  @override
  void dispose() {
    _brandNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    // _ownerPhoneCtrl removed — PhoneField owns its controller
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadTemplates() async {
    final svc = context.read<FirestoreService>();
    final templates = await svc.getCategoryTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _templatesLoading = false;
      // Try to match existing template by id
      if (widget.business.defaultCategoryTemplateId != null) {
        final match = templates.where(
          (t) => t['id'] == widget.business.defaultCategoryTemplateId,
        );
        if (match.isNotEmpty) {
          _selectedTemplateId = match.first['id'] as String?;
          _selectedCategoryType = match.first['name'] as String? ?? _selectedCategoryType;
        }
      }
    });
  }

  Future<void> _loadBranches() async {
    final svc = context.read<FirestoreService>();
    final branches = await svc.getBranches(widget.business.id);
    if (!mounted) return;
    setState(() {
      _branchIds = branches.map((b) => b.id).toList();
      _branchDrafts = branches.map(_branchToDraft).toList();
      _branchesLoading = false;
    });
  }

  /// Converts a Firestore BranchModel into an editable BranchDraft.
  BranchDraft _branchToDraft(BranchModel b) {
    final d = BranchDraft();
    d.name                = b.branchName;
    d.address             = b.address;
    d.whatsappNumber      = b.whatsappNumber;
    d.whatsappMonitoredBy = b.whatsappMonitoredBy;
    d.placeId             = b.placeId;
    d.googleReviewLink    = b.googleReviewLink;
    for (final entry in b.starRoutingConfig.entries) {
      d.starRouting[entry.key] = entry.value;
    }
    return d;
  }

  // ── Logo — upload not yet available (StorageService.uploadLogo pending) ────
  // No _pickLogo() method — upload button is intentionally removed from the UI
  // until StorageService is wired. Current logo URL is always preserved on save.

  // ── Validation ────────────────────────────────────────────────────────────

  /// Returns a human-readable reason save is blocked, or null if valid.
  String? get _validationError {
    if (_brandNameCtrl.text.trim().isEmpty) return 'Business name is required.';
    if (_ownerNameCtrl.text.trim().isEmpty) return 'Owner name is required.';
    if (_ownerEmailCtrl.text.trim().isEmpty) return 'Owner email is required.';
    // Category is optional — may be unset when no templates exist yet.
    if (_branchDrafts.isEmpty) return 'At least one branch is required.';
    final multiBranch = _branchDrafts.length > 1;
    for (int i = 0; i < _branchDrafts.length; i++) {
      final d = _branchDrafts[i];
      final label = multiBranch ? 'Branch ${i + 1}' : 'Branch';
      if (multiBranch && d.name.trim().isEmpty) return '$label: branch name is required.';
      if (d.whatsappNumber.trim().isEmpty) return '$label: WhatsApp number is required.';
      if (d.whatsappMonitoredBy.trim().isEmpty) return '$label: "Monitored by" is required.';
      if (d.address.trim().isEmpty) return '$label: address is required.';
      if (!d.starRoutingComplete) return '$label: set routing for all 5 star ratings.';
    }
    return null;
  }

  // ── Save ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() { _showErrors = true; _saveError = null; });
    final valErr = _validationError;
    if (valErr != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(valErr),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Duplicate Place ID check (excluding current business)
    final svc = context.read<FirestoreService>();
    for (final draft in _branchDrafts) {
      if (draft.placeId != null && draft.placeId!.isNotEmpty) {
        final exists = await svc.placeIdExistsForEdit(
          draft.placeId!, widget.business.id);
        if (exists && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Place ID "${draft.placeId}" is already registered to another business.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      // 1 — Update business-level fields
      await svc.updateBusiness(
        widget.business.id,
        brandName:    _brandNameCtrl.text.trim(),
        logoUrl:      _logoUrl,
        categoryType: _selectedCategoryType.trim(),
        templateId:   _selectedTemplateId,
        ownerName:    _ownerNameCtrl.text.trim(),
        ownerEmail:   _ownerEmailCtrl.text.trim(),
        ownerPhone:   _ownerPhoneE164.trim(),
      );

      // 2 — Update each branch
      for (int i = 0; i < _branchDrafts.length; i++) {
        if (i >= _branchIds.length) break; // safety — no new branches in edit
        final draft = _branchDrafts[i];
        await svc.updateBranch(
          widget.business.id,
          _branchIds[i],
          branchName:           draft.name.trim(),
          address:              draft.address.trim(),
          whatsappNumber:       draft.whatsappNumber.trim(),
          whatsappMonitoredBy:  draft.whatsappMonitoredBy.trim(),
          placeId:              draft.placeId,
          googleReviewLink:     draft.googleReviewLink,
          starRoutingConfig:    draft.starRoutingAsMap,
          categoryOverrideId:   null, // future: support category override edit
        );
      }

      if (mounted) {
        // Show snackbar BEFORE navigating — ScaffoldMessenger survives
        // GoRouter navigation so the message appears on the dashboard.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                const Text('Changes saved successfully'),
              ],
            ),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        context.go('/businesses');
      }
    } catch (e) {
      setState(() { _saveError = e.toString(); _saving = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPending = widget.business.subscriptionStatus ==
        AppConstants.statusPendingPayment;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${widget.business.brandName}'),
        actions: [
          if (!_saving)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _branchesLoading || _templatesLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Status banner (read-only) ──────────────────────────
                  if (isPending)
                    _InfoBanner(
                      icon: Icons.info_outline,
                      color: const Color(0xFF8B5CF6),
                      message: 'Draft — awaiting payment. '
                          'You can still fix any enrollment mistakes here.',
                    ),
                  if (!isPending)
                    _InfoBanner(
                      icon: Icons.check_circle_outline,
                      color: const Color(0xFF22C55E),
                      message: 'Active business — edits apply immediately. '
                          'Subscription fields are managed by admin.',
                    ),

                  const SizedBox(height: 20),

                  // ── Business section ───────────────────────────────────
                  _SectionHeader('Business details'),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _brandNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Business / Brand name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Category template dropdown
                  _templatesLoading
                      ? const CircularProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value: _selectedTemplateId,
                          decoration: const InputDecoration(
                            labelText: 'Category template',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          hint: const Text('Select a template'),
                          items: _templates.map((t) => DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(t['name'] as String? ?? t['id'] as String),
                          )).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedTemplateId = val;
                              if (val != null) {
                                final match = _templates.where((t) => t['id'] == val);
                                if (match.isNotEmpty) {
                                  _selectedCategoryType =
                                      match.first['name'] as String? ?? val;
                                }
                              }
                            });
                          },
                        ),

                  const SizedBox(height: 20),

                  // ── Logo (read-only until StorageService is wired) ──────
                  _SectionHeader('Logo'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Current logo thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _logoUrl.isNotEmpty
                            ? Image.network(
                                _logoUrl,
                                width: 72, height: 72, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Container(
                                      width: 72, height: 72,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.image_outlined, size: 32),
                                    ),
                              )
                            : Container(
                                width: 72, height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.image_outlined, size: 32),
                              ),
                      ),
                      const SizedBox(width: 16),
                      // Locked note — upload wired separately
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lock_outline, size: 14,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  'Logo replacement coming soon',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Logo changes will be available once Storage upload is wired.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Owner info ────────────────────────────────────────
                  _SectionHeader('Owner contact'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerNameCtrl,
                    decoration: const InputDecoration(labelText: 'Owner name *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerEmailCtrl,
                    decoration: const InputDecoration(labelText: 'Owner email *'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  PhoneField(
                    label: 'Owner phone *',
                    initialValue: _ownerPhoneE164,
                    showError: _showErrors,
                    onChanged: (e164) => setState(() => _ownerPhoneE164 = e164),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ── Branch section ────────────────────────────────────
                  _SectionHeader('Branches'),
                  const SizedBox(height: 12),

                  if (_branchDrafts.isEmpty)
                    const Text('No branches found.',
                        style: TextStyle(color: Colors.grey))
                  else
                    ...List.generate(_branchDrafts.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: BranchFormWidget(
                        key: ValueKey('branch_$i'),
                        branchIndex:   i,
                        draft:         _branchDrafts[i],
                        showBranchName: _branchDrafts.length > 1,
                        showError:     _showErrors,
                        onChanged: () => setState(() {}),
                        // No onRemove: don't allow adding/removing branches in edit
                        // (branch management is admin's job post-activation)
                      ),
                    )),

                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _saveError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ── Save button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   message;
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 13, color: color)),
            ),
          ],
        ),
      );
}
