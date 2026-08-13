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
// BUG FIXES (this version):
//   Bug 1 — On validation failure, FocusNode.requestFocus() + Scrollable.ensureVisible()
//            on the first invalid field so the user is taken to the problem.
//   Bug 2 — Logo upload control always rendered (whether logo_url is set or not).
//            Uses the same ImagePickerWeb + dart:ui dimension-check pattern as enroll.
//   Bug 3 — After save, calls MyBusinessesProvider.replaceLocal(updatedModel) BEFORE
//            navigating, so the list and any cached detail view update instantly.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_web/image_picker_web.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/phone_field.dart';
import '../../core/theme.dart';
import '../../models/branch_draft.dart';
import '../../models/branch_model.dart';
import '../../models/business_model.dart';
import '../../providers/my_businesses_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../enroll/branch_form_widget.dart';

class BusinessEditScreen extends StatefulWidget {
  final BusinessModel business;
  const BusinessEditScreen({super.key, required this.business});

  @override
  State<BusinessEditScreen> createState() => _BusinessEditScreenState();
}

class _BusinessEditScreenState extends State<BusinessEditScreen> {
  // ── Scroll controller (Bug 1) ────────────────────────────────────────────
  final _scrollCtrl = ScrollController();

  // ── Form controllers ─────────────────────────────────────────────────────
  final _formKey        = GlobalKey<FormState>();
  late final TextEditingController _brandNameCtrl;
  late final TextEditingController _ownerNameCtrl;
  late final TextEditingController _ownerEmailCtrl;
  String _ownerPhoneE164 = '';

  // ── FocusNodes (Bug 1) ───────────────────────────────────────────────────
  final _brandNameFocus  = FocusNode();
  final _ownerNameFocus  = FocusNode();
  final _ownerEmailFocus = FocusNode();

  // ── Template / category ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _templates = [];
  bool   _templatesLoading = true;
  String _selectedCategoryType = '';
  String? _selectedTemplateId;

  // ── Logo — Bug 2: always rendered, upload wired via StorageService ────────
  String     _logoUrl          = '';
  Uint8List? _logoBytes;
  String?    _logoMimeType;
  bool       _logoUploading    = false;
  String?    _logoRejection;   // dimension / decode error message

  // ── Branches ─────────────────────────────────────────────────────────────
  List<BranchDraft> _branchDrafts = [];
  List<String>      _branchIds    = [];
  bool   _branchesLoading = true;
  bool   _showErrors      = false;

  // ── Save ─────────────────────────────────────────────────────────────────
  bool    _saving    = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final biz = widget.business;
    _brandNameCtrl        = TextEditingController(text: biz.brandName);
    _ownerNameCtrl        = TextEditingController(text: biz.ownerName  ?? '');
    _ownerEmailCtrl       = TextEditingController(text: biz.ownerEmail ?? '');
    _ownerPhoneE164       = biz.ownerPhone ?? '';
    _selectedCategoryType = biz.categoryType;
    _logoUrl              = biz.logoUrl;
    _loadTemplates();
    _loadBranches();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _brandNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _brandNameFocus.dispose();
    _ownerNameFocus.dispose();
    _ownerEmailFocus.dispose();
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadTemplates() async {
    final svc       = context.read<FirestoreService>();
    final templates = await svc.getCategoryTemplates();
    if (!mounted) return;
    setState(() {
      _templates        = templates;
      _templatesLoading = false;
      if (widget.business.defaultCategoryTemplateId != null) {
        final match = templates.where(
          (t) => t['id'] == widget.business.defaultCategoryTemplateId,
        );
        if (match.isNotEmpty) {
          _selectedTemplateId   = match.first['id'] as String?;
          _selectedCategoryType = match.first['name'] as String? ?? _selectedCategoryType;
        }
      }
    });
  }

  Future<void> _loadBranches() async {
    final svc      = context.read<FirestoreService>();
    final branches = await svc.getBranches(widget.business.id);
    if (!mounted) return;
    setState(() {
      _branchIds       = branches.map((b) => b.id).toList();
      _branchDrafts    = branches.map(_branchToDraft).toList();
      _branchesLoading = false;
    });
  }

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

  // ── Logo — Bug 2: pick + dimension check (same pattern as enroll_screen) ──

  Future<void> _pickLogoWithValidation() async {
    setState(() => _logoRejection = null);
    final result = await ImagePickerWeb.getImageInfo();
    if (result == null || !mounted) return;

    final bytes = result.data;
    if (bytes == null) return;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      image.dispose();
      codec.dispose();

      if (w < AppConstants.minLogoPx || h < AppConstants.minLogoPx) {
        if (mounted) {
          setState(() => _logoRejection =
              'Logo too small — minimum ${AppConstants.minLogoPx}×'
              '${AppConstants.minLogoPx} px. Uploaded: $w×$h px.');
        }
        return;
      }
    } catch (_) {
      // Dimension decode failed — allow the upload
    }

    final ext  = (result.fileName ?? '').split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    if (mounted) {
      setState(() {
        _logoBytes    = bytes;
        _logoMimeType = mime;
        _logoRejection = null;
      });
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────

  String? get _validationError {
    if (_brandNameCtrl.text.trim().isEmpty) return 'Business name is required.';
    if (_ownerNameCtrl.text.trim().isEmpty) return 'Owner name is required.';
    if (_ownerEmailCtrl.text.trim().isEmpty) return 'Owner email is required.';
    if (_branchDrafts.isEmpty) return 'At least one branch is required.';
    final multiBranch = _branchDrafts.length > 1;
    for (int i = 0; i < _branchDrafts.length; i++) {
      final d     = _branchDrafts[i];
      final label = multiBranch ? 'Branch ${i + 1}' : 'Branch';
      if (multiBranch && d.name.trim().isEmpty)     return '$label: branch name is required.';
      if (d.whatsappNumber.trim().isEmpty)          return '$label: WhatsApp number is required.';
      if (d.whatsappMonitoredBy.trim().isEmpty)     return '$label: "Monitored by" is required.';
      if (d.address.trim().isEmpty)                 return '$label: address is required.';
      if (!d.starRoutingComplete)                   return '$label: set routing for all 5 star ratings.';
    }
    return null;
  }

  // ── Bug 1: focus + scroll to first invalid field ─────────────────────────

  void _focusFirstError(String? error) {
    if (error == null) return;
    FocusNode? target;
    if (_brandNameCtrl.text.trim().isEmpty) {
      target = _brandNameFocus;
    } else if (_ownerNameCtrl.text.trim().isEmpty) {
      target = _ownerNameFocus;
    } else if (_ownerEmailCtrl.text.trim().isEmpty) {
      target = _ownerEmailFocus;
    }
    if (target?.context != null) {
      target!.requestFocus();
      Scrollable.ensureVisible(
        target.context!,
        duration:  const Duration(milliseconds: 300),
        curve:     Curves.easeInOut,
        alignment: 0.25,
      );
    }
  }

  // ── Save — Bug 2 (upload if staged) + Bug 3 (replaceLocal) ───────────────

  Future<void> _save() async {
    setState(() { _showErrors = true; _saveError = null; });
    final valErr = _validationError;
    if (valErr != null) {
      _focusFirstError(valErr); // Bug 1
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text(valErr),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior:        SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final svc        = context.read<FirestoreService>();
    final storageSvc = context.read<StorageService>();
    for (final draft in _branchDrafts) {
      if (draft.placeId != null && draft.placeId!.isNotEmpty) {
        final exists = await svc.placeIdExistsForEdit(
            draft.placeId!, widget.business.id);
        if (exists && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Place ID "${draft.placeId}" is already registered to another business.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ));
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      // Bug 2: upload staged logo bytes if the user picked a new logo
      String finalLogoUrl = _logoUrl;
      if (_logoBytes != null && _logoMimeType != null) {
        setState(() => _logoUploading = true);
        finalLogoUrl = await storageSvc.uploadLogo(_logoBytes!, _logoMimeType!);
        if (mounted) setState(() { _logoUrl = finalLogoUrl; _logoUploading = false; });
      }

      // 1 — Update business-level fields
      await svc.updateBusiness(
        widget.business.id,
        brandName:    _brandNameCtrl.text.trim(),
        logoUrl:      finalLogoUrl,
        categoryType: _selectedCategoryType.trim(),
        templateId:   _selectedTemplateId,
        ownerName:    _ownerNameCtrl.text.trim(),
        ownerEmail:   _ownerEmailCtrl.text.trim(),
        ownerPhone:   _ownerPhoneE164.trim(),
      );

      // 2 — Update each branch
      for (int i = 0; i < _branchDrafts.length; i++) {
        if (i >= _branchIds.length) break;
        final draft = _branchDrafts[i];
        await svc.updateBranch(
          widget.business.id,
          _branchIds[i],
          branchName:          draft.name.trim(),
          address:             draft.address.trim(),
          whatsappNumber:      draft.whatsappNumber.trim(),
          whatsappMonitoredBy: draft.whatsappMonitoredBy.trim(),
          placeId:             draft.placeId,
          googleReviewLink:    draft.googleReviewLink,
          starRoutingConfig:   draft.starRoutingAsMap,
          categoryOverrideId:  null,
        );
      }

      if (mounted) {
        // Bug 3: update the in-memory model so list + any cached detail view
        // reflect new values immediately — no page refresh needed.
        final updated = widget.business.copyWith(
          brandName:                 _brandNameCtrl.text.trim(),
          logoUrl:                   finalLogoUrl,
          categoryType:              _selectedCategoryType.trim(),
          defaultCategoryTemplateId: _selectedTemplateId,
          ownerName:                 _ownerNameCtrl.text.trim(),
          ownerEmail:                _ownerEmailCtrl.text.trim(),
          ownerPhone:                _ownerPhoneE164.trim(),
        );
        context.read<MyBusinessesProvider>().replaceLocal(updated);

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Changes saved successfully'),
            ],
          ),
          backgroundColor: AppColors.activeFg,
          behavior:        SnackBarBehavior.floating,
          duration:        const Duration(seconds: 4),
        ));
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${widget.business.brandName}'),
        actions: [
          if (!_saving)
            TextButton.icon(
              onPressed: _save,
              icon:  const Icon(Icons.save_outlined),
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
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Status banner ──────────────────────────────────────
                  if (isPending)
                    _InfoBanner(
                      icon:    Icons.info_outline,
                      color:   AppColors.pendingFg,
                      message: 'Draft — awaiting payment. '
                          'You can still fix any enrollment mistakes here.',
                    ),
                  if (!isPending)
                    _InfoBanner(
                      icon:    Icons.check_circle_outline,
                      color:   AppColors.activeFg,
                      message: 'Active business — edits apply immediately. '
                          'Subscription fields are managed by admin.',
                    ),

                  const SizedBox(height: 20),

                  // ── Business details ───────────────────────────────────
                  _SectionHeader('Business details'),
                  const SizedBox(height: 12),

                  // Bug 1: FocusNode on brand name
                  TextFormField(
                    controller: _brandNameCtrl,
                    focusNode:  _brandNameFocus,
                    decoration: const InputDecoration(
                      labelText:  'Business / Brand name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    validator:  (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged:  (_) => setState(() {}),
                  ),
                  if (_showErrors && _brandNameCtrl.text.trim().isEmpty)
                    _FieldError('Business name is required.'),
                  const SizedBox(height: 16),

                  // Category template dropdown
                  _templatesLoading
                      ? const CircularProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value:      _selectedTemplateId,
                          decoration: const InputDecoration(
                            labelText:  'Category template',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          hint:  const Text('Select a template'),
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

                  // ── Logo — Bug 2: always rendered ──────────────────────
                  _SectionHeader('Logo'),
                  const SizedBox(height: 12),
                  _LogoEditRow(
                    existingUrl:  _logoUrl,
                    stagedBytes:  _logoBytes,
                    uploading:    _logoUploading,
                    rejection:    _logoRejection,
                    onPick:       _pickLogoWithValidation,
                  ),

                  const SizedBox(height: 20),

                  // ── Owner info ─────────────────────────────────────────
                  _SectionHeader('Owner contact'),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _ownerNameCtrl,
                    focusNode:  _ownerNameFocus,
                    decoration: const InputDecoration(labelText: 'Owner name *'),
                    validator:  (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged:  (_) => setState(() {}),
                  ),
                  if (_showErrors && _ownerNameCtrl.text.trim().isEmpty)
                    _FieldError('Owner name is required.'),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller:   _ownerEmailCtrl,
                    focusNode:    _ownerEmailFocus,
                    decoration:   const InputDecoration(labelText: 'Owner email *'),
                    keyboardType: TextInputType.emailAddress,
                    validator:    (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                    onChanged:    (_) => setState(() {}),
                  ),
                  if (_showErrors && _ownerEmailCtrl.text.trim().isEmpty)
                    _FieldError('Owner email is required.'),
                  const SizedBox(height: 12),

                  PhoneField(
                    label:        'Owner phone *',
                    initialValue: _ownerPhoneE164,
                    showError:    _showErrors,
                    onChanged:    (e164) => setState(() => _ownerPhoneE164 = e164),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  // ── Branch section ────────────────────────────────────
                  _SectionHeader('Branches'),
                  const SizedBox(height: 12),

                  if (_branchDrafts.isEmpty)
                    Text(
                      'No branches found.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else
                    ...List.generate(_branchDrafts.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: BranchFormWidget(
                        key: ValueKey('branch_$i'),
                        branchIndex:    i,
                        draft:          _branchDrafts[i],
                        showBranchName: _branchDrafts.length > 1,
                        showError:      _showErrors,
                        onChanged:      () => setState(() {}),
                      ),
                    )),

                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:        scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _saveError!,
                        style: TextStyle(color: scheme.onErrorContainer),
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

// ── Logo edit row — Bug 2 ─────────────────────────────────────────────────────
// Always rendered. Shows:
//   • staged bytes preview  (in-memory pick, not yet uploaded)
//   • OR existing URL thumbnail
//   • OR placeholder
// Plus an upload / replace button.

class _LogoEditRow extends StatelessWidget {
  final String     existingUrl;
  final Uint8List? stagedBytes;
  final bool       uploading;
  final String?    rejection;
  final VoidCallback onPick;

  const _LogoEditRow({
    required this.existingUrl,
    required this.stagedBytes,
    required this.uploading,
    required this.rejection,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme      = Theme.of(context).colorScheme;
    final hasExisting = existingUrl.isNotEmpty;
    final hasStaged   = stagedBytes != null;
    final hasError    = rejection != null;

    Widget thumbnail;
    if (hasStaged) {
      thumbnail = Image.memory(
        stagedBytes!,
        width: 72, height: 72, fit: BoxFit.cover,
      );
    } else if (hasExisting) {
      thumbnail = Image.network(
        existingUrl,
        width: 72, height: 72, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(scheme),
      );
    } else {
      thumbnail = _placeholder(scheme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumbnail,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasStaged
                        ? '✓ New logo selected — will upload on save'
                        : hasExisting
                            ? 'Current logo'
                            : 'No logo yet',
                    style: TextStyle(
                      fontSize:   13,
                      color:      hasStaged ? AppColors.activeFg : scheme.onSurfaceVariant,
                      fontWeight: hasStaged ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Min ${AppConstants.minLogoPx}×${AppConstants.minLogoPx} px · JPEG or PNG',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  uploading
                      ? const Row(children: [
                          SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Uploading…', style: TextStyle(fontSize: 12)),
                        ])
                      : OutlinedButton.icon(
                          onPressed: onPick,
                          icon:  Icon(
                            hasExisting || hasStaged
                                ? Icons.swap_horiz_outlined
                                : Icons.upload_outlined,
                            size: 16,
                          ),
                          label: Text(
                            hasExisting || hasStaged ? 'Replace logo' : 'Upload logo',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            side: hasError
                                ? BorderSide(color: scheme.error, width: 1.5)
                                : null,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          _FieldError(rejection!),
        ],
      ],
    );
  }

  static Widget _placeholder(ColorScheme scheme) => Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color:        scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          Icons.add_a_photo_outlined,
          size:  28,
          color: scheme.onSurfaceVariant,
        ),
      );
}

// ── Inline field error ────────────────────────────────────────────────────────

class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 12),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
        ),
      );
}

// ── Section header ────────────────────────────────────────────────────────────

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

// ── Info banner ───────────────────────────────────────────────────────────────

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
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: color.withValues(alpha: 0.3)),
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
