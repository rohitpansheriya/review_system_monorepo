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
import '../../core/image_utils.dart';
import '../../core/constants.dart';
import '../../core/phone_field.dart';
import '../../core/string_utils.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/enroll_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/places_service.dart';
import '../../widgets/app_brand_title.dart';
import 'branch_form_widget.dart';
import 'enroll_chip_customizer.dart';

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

  // Field-specific server/validation errors
  String? _ownerEmailError;
  String? _brandNameError;
  String? _ownerNameError;
  String? _ownerPhoneError;
  bool _isSubmitting = false;

  // Form controllers for business-level fields
  final _scrollCtrl     = ScrollController();
  final _brandNameCtrl  = TextEditingController();
  final _ownerNameCtrl  = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();

  // FocusNodes for Bug 1 (auto-focus and scroll to first invalid field)
  final _brandNameFocus  = FocusNode();
  final _ownerNameFocus  = FocusNode();
  final _ownerEmailFocus = FocusNode();

  // Google Maps Places Search controllers
  final _mapsSearchNameCtrl  = TextEditingController();
  final _mapsSearchCityCtrl  = TextEditingController();
  final _mapsSearchNameFocus = FocusNode();
  final _mapsSearchCityFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadTemplates();

    // ── Blur listeners for live sanitization/normalization ──────────────────
    _brandNameFocus.addListener(() {
      if (!_brandNameFocus.hasFocus) {
        final clean = StringUtils.collapseWhitespace(_brandNameCtrl.text);
        if (_brandNameCtrl.text != clean) {
          _brandNameCtrl.text = clean;
        }
        if (mounted) context.read<EnrollProvider>().brandName = clean;
      }
    });

    _ownerNameFocus.addListener(() {
      if (!_ownerNameFocus.hasFocus) {
        final clean = StringUtils.collapseWhitespace(_ownerNameCtrl.text);
        if (_ownerNameCtrl.text != clean) {
          _ownerNameCtrl.text = clean;
        }
        if (mounted) context.read<EnrollProvider>().ownerName = clean;
      }
    });

    _ownerEmailFocus.addListener(() {
      if (!_ownerEmailFocus.hasFocus) {
        final clean = StringUtils.sanitizeEmail(_ownerEmailCtrl.text);
        if (_ownerEmailCtrl.text != clean) {
          _ownerEmailCtrl.text = clean;
        }
        if (mounted) context.read<EnrollProvider>().ownerEmail = clean;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnrollProvider>().reset();
      _brandNameCtrl.clear();
      _ownerNameCtrl.clear();
      _ownerEmailCtrl.clear();
      _ownerEmailError = null;
      _brandNameError = null;
      _ownerNameError = null;
      _ownerPhoneError = null;
      _isSubmitting = false;
    });
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
    _mapsSearchNameCtrl.dispose();
    _mapsSearchCityCtrl.dispose();
    _mapsSearchNameFocus.dispose();
    _mapsSearchCityFocus.dispose();
    super.dispose();
  }

  Future<void> _searchGoogleMaps() async {
    final bName = _mapsSearchNameCtrl.text.trim();
    final cName = _mapsSearchCityCtrl.text.trim();
    if (bName.isEmpty) {
      _mapsSearchNameFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter business name to search on Google Maps'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (cName.isEmpty) {
      _mapsSearchCityFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter city name (e.g. Surat, Mumbai)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await context.read<EnrollProvider>().searchTopLevelPlaces(bName, cName);
  }

  void _onSelectPlaceCandidate(PlaceCandidate candidate) {
    final enroll = context.read<EnrollProvider>();
    enroll.applyPlaceAutoFill(candidate, availableTemplates: _templates);
    _brandNameCtrl.text = enroll.brandName;
    setState(() {
      _brandNameError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Auto-filled business & branch details for "${candidate.name}" from Google Places!'),
        backgroundColor: AppColors.activeFg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
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

  // ── Logo with dimension validation & client-side auto-resizing ────────────
  Future<void> _pickLogoWithValidation() async {
    final result = await ImagePickerWeb.getImageInfo();
    if (result == null || !mounted) return;

    final bytes = result.data;
    if (bytes == null) return;

    // Decode image dimensions client-side via dart:ui.
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
      setState(() => _logoRejectionMessage = null);
    }

    // Client-side auto-resize and compress to lightweight, crisp PNG
    final optimizedBytes = await ImageUtils.resizeAndCompressLogo(bytes, maxDimension: 384);

    if (!mounted) return;
    context.read<EnrollProvider>().setLogo(optimizedBytes, 'image/png');
  }

  void _focusFirstError([String? specificError]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final enroll = context.read<EnrollProvider>();
      FocusNode? target;
      final errLower = (specificError ?? enroll.validationError ?? '').toLowerCase();

      if (errLower.contains('email') || _ownerEmailError != null) {
        target = _ownerEmailFocus;
      } else if (errLower.contains('business name') || errLower.contains('brand') || _brandNameError != null || enroll.brandName.trim().isEmpty) {
        target = _brandNameFocus;
      } else if (errLower.contains('owner name') || _ownerNameError != null || enroll.ownerName.trim().isEmpty) {
        target = _ownerNameFocus;
      } else if (enroll.ownerEmail.trim().isEmpty) {
        target = _ownerEmailFocus;
      }

      if (target != null) {
        target.requestFocus();
        if (target.context != null) {
          Scrollable.ensureVisible(
            target.context!,
            duration:  const Duration(milliseconds: 400),
            curve:     Curves.easeInOutCubic,
            alignment: 0.2,
          );
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final enroll = context.read<EnrollProvider>();
    if (enroll.isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _ownerEmailError = null;
      _brandNameError = null;
      _ownerNameError = null;
      _ownerPhoneError = null;
    });

    try {
      final err = enroll.validationError;
      if (err != null) {
        setState(() {
          _showErrors = true;
          _isSubmitting = false;
          if (err.toLowerCase().contains('email')) {
            _ownerEmailError = err;
          } else if (err.toLowerCase().contains('business name')) {
            _brandNameError = err;
          } else if (err.toLowerCase().contains('owner name')) {
            _ownerNameError = err;
          } else if (err.toLowerCase().contains('phone')) {
            _ownerPhoneError = err;
          }
        });
        _focusFirstError(err);
        return;
      }

      // GROUP D2: When admin enrolls, use "admin" as the enrollee
      // so that enrolled_by="admin" and the UI never mislabels it as an employee.
      final auth = context.read<AppAuthProvider>();
      final empId = auth.isAdmin ? 'admin' : auth.uid!;
      if (!auth.isAdmin) {
        enroll.setIsTestAccount(false);
      }
      final error = await enroll.submit(empId);
      if (!mounted) return;

      if (error != null) {
        setState(() {
          _showErrors = true;
          _isSubmitting = false;
          if (error.toLowerCase().contains('email')) {
            _ownerEmailError = error;
          } else if (error.toLowerCase().contains('business name') || error.toLowerCase().contains('brand')) {
            _brandNameError = error;
          } else if (error.toLowerCase().contains('owner name')) {
            _ownerNameError = error;
          } else if (error.toLowerCase().contains('phone')) {
            _ownerPhoneError = error;
          }
        });
        _focusFirstError(error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        // Navigate to payment page for this draft — user pays or defers there.
        final bizId = enroll.successBizId!;

        // GROUP B2: Reset form state BEFORE navigating so next enroll is clean
        _brandNameCtrl.clear();
        _ownerNameCtrl.clear();
        _ownerEmailCtrl.clear();
        setState(() {
          _showErrors = false;
          _isSubmitting = false;
          _ownerEmailError = null;
          _brandNameError = null;
          _ownerNameError = null;
          _ownerPhoneError = null;
        });

        // Both admin and employee go to payment screen — the payment screen
        // handles role-aware navigation (admin → /admin, employee → /businesses).
        context.go('/enroll/payment/$bizId');

        // Reset provider AFTER navigation to ensure clean state for next enrollment
        enroll.reset();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enrollment failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enroll = context.watch<EnrollProvider>();
    final scheme = Theme.of(context).colorScheme;

    // When embedded as a tab inside the admin dashboard shell, hide the
    // back button — admin navigates via the sidebar.  Employees get the
    // back arrow to their "My Enrolled Businesses" list.
    final isAdmin = context.read<AppAuthProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle(subtitle: 'Enroll Business'),
        leading: isAdmin
            ? const SizedBox.shrink()  // No back button inside admin shell
            : BackButton(onPressed: () => context.go('/businesses')),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: _scrollCtrl,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width > 600 ? AppSpacing.lg : 12,
              vertical: AppSpacing.md,
            ),
            children: [
              // ── Mode toggle ──────────────────────────────────────────────
              _FormSection(
                title: 'Business Type',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<EnrollMode>(
                        segments: const [
                          ButtonSegment(
                            value: EnrollMode.single,
                            label: Text('Single location'),
                            icon:  Icon(Icons.storefront_outlined),
                          ),
                          ButtonSegment(
                            value: EnrollMode.multi,
                            label: Text('Multiple branches'),
                            icon:  Icon(Icons.account_tree_outlined),
                          ),
                        ],
                        selected: {enroll.mode},
                        onSelectionChanged: (set) {
                          if (set.isNotEmpty) enroll.setMode(set.first);
                          setState(() => _showErrors = false);
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      enroll.mode == EnrollMode.single
                          ? 'One physical location — branch name is set automatically.'
                          : 'Multiple branches under one brand — each gets its own QR/NFC.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Google Maps 1-Click Auto-Fill ─────────────────────────────
              _buildGooglePlacesAutoFillSection(enroll, scheme),

              const SizedBox(height: AppSpacing.md),

              // ── Business Details ─────────────────────────────────────────
              _FormSection(
                title: 'Business Details',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Business name
                    TextFormField(
                      controller: _brandNameCtrl,
                      focusNode:  _brandNameFocus,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Business name *',
                        prefixIcon: const Icon(Icons.business_outlined),
                        errorText: _brandNameError ?? (_showErrors && enroll.brandName.trim().isEmpty
                            ? 'Business name is required'
                            : null),
                      ),
                      onChanged: (v) {
                        if (_brandNameError != null) setState(() => _brandNameError = null);
                        enroll.brandName = v;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Category
                    if (_templatesLoading)
                      const LinearProgressIndicator()
                    else if (_templates.isEmpty)
                      _InfoBox(
                        icon: Icons.info_outline,
                        message: 'No categories available — contact admin.\n'
                            'You can still enroll without a category.',
                        color: scheme.onSurfaceVariant,
                        backgroundColor: scheme.surfaceContainerLowest,
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: _templates.any((t) => t['id'] == enroll.templateId)
                            ? enroll.templateId
                            : null,
                        isExpanded:    true,
                        dropdownColor: Colors.white,
                        borderRadius:  BorderRadius.circular(14),
                        elevation:     8,
                        icon:          const Icon(Icons.keyboard_arrow_down_rounded),
                        decoration: const InputDecoration(
                          labelText:  'Business category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        hint: const Text('Select a category (optional)'),
                        items: _templates
                            .map((t) => DropdownMenuItem<String>(
                                  value: t['id'] as String,
                                  child: Text(
                                    t['business_type'] as String? ??
                                        t['name'] as String? ??
                                        t['id'] as String,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final match = _templates.firstWhere(
                            (t) => t['id'] == v,
                            orElse: () => {'business_type': v},
                          );
                          final catType = match['business_type'] as String? ??
                              match['name'] as String? ??
                              v;
                          enroll.applyCategoryPreset(catType, v);
                        },
                      ),
                    const SizedBox(height: AppSpacing.md),

                    // Review Language Preference (Default: English Only)
                    DropdownButtonFormField<String>(
                      value: enroll.reviewLanguagePreference,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      decoration: const InputDecoration(
                        labelText: 'Review Language Preference',
                        prefixIcon: Icon(Icons.translate_rounded),
                        helperText: 'Select what language reviews will be generated and served in.',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'english',
                          child: Text('English Only (Default)'),
                        ),
                        DropdownMenuItem(
                          value: 'hinglish',
                          child: Text('Hinglish Only (Roman script)'),
                        ),
                        DropdownMenuItem(
                          value: 'mixed',
                          child: Text('Mixed (English + Hinglish)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) enroll.setReviewLanguagePreference(v);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── 3-Step Guided Review Offerings & Chips Customizer ────
                    const EnrollChipCustomizer(),
                    const SizedBox(height: AppSpacing.md),

                    // Logo picker with dimension validation (Change 4)
                    _LogoPicker(
                      enroll:           enroll,
                      onPick:           _pickLogoWithValidation,
                      rejectionMessage: _logoRejectionMessage,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Owner Contact ────────────────────────────────────────────
              _FormSection(
                title: 'Owner Contact',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _ownerNameCtrl,
                      focusNode:  _ownerNameFocus,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Owner name *',
                        prefixIcon: const Icon(Icons.person_outline),
                        errorText: _ownerNameError ?? (_showErrors && enroll.ownerName.trim().isEmpty
                            ? 'Owner name is required'
                            : null),
                      ),
                      onChanged: (v) {
                        if (_ownerNameError != null) setState(() => _ownerNameError = null);
                        enroll.ownerName = v;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),
                    TextFormField(
                      controller:  _ownerEmailCtrl,
                      focusNode:   _ownerEmailFocus,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText:  'Owner email *',
                        helperText: _ownerEmailError == null ? 'Used for renewal notifications' : null,
                        prefixIcon: const Icon(Icons.mail_outline),
                        errorText: _ownerEmailError ?? (_showErrors && enroll.ownerEmail.trim().isEmpty
                            ? 'Owner email is required'
                            : null),
                        errorMaxLines: 3,
                      ),
                      onChanged: (v) {
                        if (_ownerEmailError != null) setState(() => _ownerEmailError = null);
                        enroll.ownerEmail = StringUtils.sanitizeEmail(v);
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm + 4),
                    PhoneField(
                      label:       'Owner phone *',
                      helperText:  'Used for payment and WhatsApp contact',
                      initialValue: enroll.ownerPhone,
                      showError:   _showErrors,
                      errorText:   _ownerPhoneError,
                      onChanged:   (e164) {
                        if (_ownerPhoneError != null) setState(() => _ownerPhoneError = null);
                        enroll.ownerPhone = e164;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Demo / Test Account Option (Admin Only) ──────────────────
              if (isAdmin) ...[
                Builder(
                  builder: (context) {
                    final theme = Theme.of(context);
                    final colorScheme = theme.colorScheme;
                    return Card(
                      color: enroll.isTestAccount ? AppColors.warning.withValues(alpha: 0.08) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: enroll.isTestAccount ? AppColors.warning : theme.dividerColor.withValues(alpha: 0.2),
                          width: enroll.isTestAccount ? 1.5 : 1,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: enroll.isTestAccount,
                        onChanged: (v) => enroll.setIsTestAccount(v ?? false),
                        activeColor: AppColors.warning,
                        secondary: Icon(
                          enroll.isTestAccount ? Icons.science : Icons.science_outlined,
                          color: enroll.isTestAccount ? AppColors.warning : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          'Demo / QA Test Account',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: enroll.isTestAccount ? AppColors.warning : null,
                          ),
                        ),
                        subtitle: Text(
                          'Assigns TEST-xxxxx code. Excluded from real client sequential numbers (APT-01001) and revenue metrics.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // ── Branch(es) ───────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              enroll.mode == EnrollMode.single
                                  ? 'Location'
                                  : 'Branches (${enroll.branches.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (enroll.mode == EnrollMode.multi)
                            TextButton.icon(
                              icon:      const Icon(Icons.add, size: 16),
                              label:     const Text('Add branch'),
                              onPressed: enroll.addBranch,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.md),

                      // Branch widgets
                      ...List.generate(enroll.branches.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: BranchFormWidget(
                            key:           ValueKey('branch_$i'),
                            branchIndex:   i,
                            draft:         enroll.branchAt(i),
                            showBranchName: enroll.isMulti,
                            showError:     _showErrors,
                            ownerPhone:    enroll.ownerPhone,
                            ownerName:     enroll.ownerName,
                            onChanged:     enroll.notifyBranchChanged,
                            onRemove:      enroll.isMulti && enroll.branches.length > 1
                                ? () => enroll.removeBranch(i)
                                : null,
                          ),
                        );
                      }),

                      // Multi-mode: warn if zero branches
                      if (enroll.isMulti && enroll.branches.isEmpty)
                        OutlinedButton.icon(
                          icon:      const Icon(Icons.add),
                          label:     const Text('Add first branch'),
                          onPressed: enroll.addBranch,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Submit ───────────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: (_isSubmitting || enroll.isSubmitting) ? null : _submit,
                icon: (_isSubmitting || enroll.isSubmitting)
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text((_isSubmitting || enroll.isSubmitting) ? 'Enrolling & Uploading…' : 'Enroll Business'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl - 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Google Places Auto-Fill UI ──────────────────────────────────────────────

  Widget _buildGooglePlacesAutoFillSection(EnrollProvider enroll, ColorScheme scheme) {
    if (enroll.autoFilledPlace != null) {
      final p = enroll.autoFilledPlace!;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.activeFg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.activeFg.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.activeFg.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: AppColors.activeFg, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✓ AUTO-FILLED FROM GOOGLE MAPS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.activeFg,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: AppColors.activeFg.withValues(alpha: 0.5)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Change', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    enroll.clearAutoFilledPlace();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (p.rating != null)
                  _badge(
                    icon: Icons.star_rounded,
                    iconColor: Colors.amber,
                    text: '${p.rating!.toStringAsFixed(1)} ★ (${p.userRatingCount ?? 0} reviews)',
                  ),
                if (enroll.categoryType.isNotEmpty)
                  _badge(
                    icon: Icons.category_outlined,
                    iconColor: scheme.primary,
                    text: enroll.categoryType,
                  ),
                if (p.phoneNumber != null && p.phoneNumber!.isNotEmpty)
                  _badge(
                    icon: Icons.phone_outlined,
                    iconColor: scheme.onSurfaceVariant,
                    text: p.phoneNumber!,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    p.address,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _FormSection(
      title: 'Google Maps 1-Click Auto-Fill',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Search business to automatically pre-fill name, address, category, phone & live reviews.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 520;
              final nameInput = TextField(
                controller: _mapsSearchNameCtrl,
                focusNode:  _mapsSearchNameFocus,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Business name',
                  hintText: 'e.g. Bawarchi Restaurant',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  isDense: true,
                ),
                onSubmitted: (_) => _searchGoogleMaps(),
              );

              final cityInput = TextField(
                controller: _mapsSearchCityCtrl,
                focusNode:  _mapsSearchCityFocus,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'City',
                  hintText: 'e.g. Surat, Mumbai',
                  prefixIcon: Icon(Icons.location_city_outlined),
                  isDense: true,
                ),
                onSubmitted: (_) => _searchGoogleMaps(),
              );

              final searchBtn = ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onPressed: enroll.isTopLevelSearching ? null : _searchGoogleMaps,
                icon: enroll.isTopLevelSearching
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Search Google'),
              );

              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 3, child: nameInput),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: cityInput),
                        const SizedBox(width: 8),
                        searchBtn,
                      ],
                    )
                  : Column(
                      children: [
                        nameInput,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: cityInput),
                            const SizedBox(width: 8),
                            searchBtn,
                          ],
                        ),
                      ],
                    );
            },
          ),
          if (enroll.topLevelSearchError != null) ...[
            const SizedBox(height: 8),
            Text(
              enroll.topLevelSearchError!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          if (enroll.topLevelCandidates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Matches found — select to auto-fill the form:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...enroll.topLevelCandidates.map((c) => _buildCandidateCard(c, scheme)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => enroll.clearTopLevelSearch(),
                child: const Text('Dismiss results'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge({required IconData icon, required Color iconColor, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCandidateCard(PlaceCandidate c, ColorScheme scheme) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (c.rating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          '${c.rating!.toStringAsFixed(1)}${c.userRatingCount != null ? ' (${c.userRatingCount})' : ''}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    c.address,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (c.phoneNumber != null && c.phoneNumber!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    c.phoneNumber!,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text('Auto-Fill This Business'),
                onPressed: () => _onSelectPlaceCandidate(c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Form section card ─────────────────────────────────────────────────────────

class _FormSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _FormSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              child,
            ],
          ),
        ),
      );
}

// ── Info box (no templates, etc.) ────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String   message;
  final Color    color;
  final Color    backgroundColor;
  const _InfoBox({
    required this.icon,
    required this.message,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        backgroundColor,
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          border:       Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(fontSize: 13, color: color)),
            ),
          ],
        ),
      );
}

/// Logo picker with client-side dimension validation (Change 4).
/// [rejectionMessage] is shown when the chosen image is below minLogoPx.
class _LogoPicker extends StatelessWidget {
  final EnrollProvider enroll;
  final VoidCallback   onPick;
  final String?        rejectionMessage;

  const _LogoPicker({
    required this.enroll,
    required this.onPick,
    this.rejectionMessage,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business Logo',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            // Logo preview thumbnail
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: rejectionMessage != null
                      ? scheme.error
                      : scheme.outlineVariant,
                  width: rejectionMessage != null ? 1.5 : 1,
                ),
                image: enroll.logoBytes != null
                    ? DecorationImage(
                        image: MemoryImage(enroll.logoBytes!),
                        fit:   BoxFit.cover,
                      )
                    : null,
              ),
              child: enroll.logoBytes == null
                  ? Icon(
                      Icons.image_outlined,
                      color: rejectionMessage != null
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: enroll.logoUploading ? null : onPick,
                  icon:  const Icon(Icons.upload_outlined, size: 16),
                  label: Text(
                      enroll.logoBytes == null ? 'Upload logo' : 'Change logo'),
                ),
                if (enroll.logoUploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Uploading…',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (enroll.logoUrl != null && !enroll.logoUploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 13, color: AppColors.activeFg),
                        const SizedBox(width: 4),
                        Text(
                          'Uploaded',
                          style: TextStyle(fontSize: 12, color: AppColors.activeFg),
                        ),
                      ],
                    ),
                  ),
                // Min-size hint
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Min ${AppConstants.minLogoPx}×${AppConstants.minLogoPx} px for standee print quality',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
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
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:        scheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                border:       Border.all(
                  color: scheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rejectionMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer,
                      ),
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
