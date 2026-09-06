// lib/screens/enroll/branch_form_widget.dart
//
// Reusable stateful widget for ONE branch's enrollment data.
// Used in both single and multi-branch modes:
//   - Single: showBranchName = false, no remove button
//   - Multi:  showBranchName = true, remove button shown
//
// Design:
//   - Place search (business name + city) → 2-3 candidates → confirms pre-fills
//     address + Place ID but does NOT lock them. User can always edit both.
//   - Address field and Place ID field are ALWAYS visible and editable.
//   - Manual fallback is always available regardless of search state.
//   - Star routing 5 rows (required).
//
// Changes:
//   Change 5 — whatsapp_monitored_by field added immediately after the
//               WhatsApp number field. Required in both single and multi modes.
//               Uses the same widget, no forking.
//
// The widget writes directly to the BranchDraft object (passed by reference
// from EnrollProvider) and calls onChanged() to trigger a provider rebuild.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/phone_field.dart';
import '../../core/string_utils.dart';
import '../../core/theme.dart';
import '../../models/branch_draft.dart';
import '../../providers/enroll_provider.dart';
import '../../services/places_service.dart';
import 'star_routing_widget.dart';

class BranchFormWidget extends StatefulWidget {
  final int branchIndex;
  final BranchDraft draft;
  final bool showBranchName;  // false in single mode, true in multi
  final bool showError;        // true after submit attempt
  final VoidCallback? onRemove; // null = remove button hidden
  final VoidCallback onChanged; // call when any field changes
  final String? ownerPhone;
  final String? ownerName;

  const BranchFormWidget({
    super.key,
    required this.branchIndex,
    required this.draft,
    required this.showBranchName,
    required this.onChanged,
    this.showError = false,
    this.onRemove,
    this.ownerPhone,
    this.ownerName,
  });

  @override
  State<BranchFormWidget> createState() => _BranchFormWidgetState();
}

class _BranchFormWidgetState extends State<BranchFormWidget> {
  // ── Local text controllers synced to draft ────────────────────────────────
  late final TextEditingController _nameCtrl;
  late final TextEditingController _whatsappMonitoredByCtrl; // Change 5
  late final TextEditingController _addressCtrl;
  late final TextEditingController _placeIdCtrl;
  late final TextEditingController _searchNameCtrl;
  late final TextEditingController _searchCityCtrl;

  // ── FocusNodes for programmatic focus ─────────────────────────────────────
  late final FocusNode _nameFocus;
  late final FocusNode _addressFocus;
  late final FocusNode _whatsappMonitoredByFocus; // Change 5
  late final FocusNode _placeIdFocus;
  late final FocusNode _searchNameFocus;
  late final FocusNode _searchCityFocus;

  String? _searchNameError;
  String? _searchCityError;

  bool get _hasInvalidPlaceIdFormat {
    final pid = widget.draft.placeId;
    if (pid == null || pid.trim().isEmpty) return false;
    return !StringUtils.isValidPlaceIdFormat(pid);
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl                = TextEditingController(text: widget.draft.name);
    _whatsappMonitoredByCtrl = TextEditingController(text: widget.draft.whatsappMonitoredBy);
    _addressCtrl             = TextEditingController(text: widget.draft.address);
    _placeIdCtrl             = TextEditingController(text: widget.draft.placeId ?? '');
    _searchNameCtrl          = TextEditingController();
    _searchCityCtrl          = TextEditingController();

    _nameFocus                = FocusNode();
    _addressFocus             = FocusNode();
    _whatsappMonitoredByFocus = FocusNode();
    _placeIdFocus             = FocusNode();
    _searchNameFocus          = FocusNode();
    _searchCityFocus          = FocusNode();

    // ── Live blur listeners for text normalization ─────────────────────────
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) {
        final clean = StringUtils.collapseWhitespace(_nameCtrl.text);
        if (_nameCtrl.text != clean) {
          _nameCtrl.text = clean;
        }
        widget.draft.name = clean;
        widget.onChanged();
      }
    });

    _whatsappMonitoredByFocus.addListener(() {
      if (!_whatsappMonitoredByFocus.hasFocus) {
        final clean = StringUtils.collapseWhitespace(_whatsappMonitoredByCtrl.text);
        if (_whatsappMonitoredByCtrl.text != clean) {
          _whatsappMonitoredByCtrl.text = clean;
        }
        widget.draft.whatsappMonitoredBy = clean;
        widget.onChanged();
      }
    });

    _addressFocus.addListener(() {
      if (!_addressFocus.hasFocus) {
        final clean = StringUtils.collapseWhitespace(_addressCtrl.text);
        if (_addressCtrl.text != clean) {
          _addressCtrl.text = clean;
        }
        widget.draft.address = clean;
        widget.onChanged();
      }
    });

    _placeIdFocus.addListener(() {
      if (!_placeIdFocus.hasFocus) {
        final clean = StringUtils.sanitizePlaceId(_placeIdCtrl.text);
        if (_placeIdCtrl.text != clean) {
          _placeIdCtrl.text = clean;
        }
        widget.draft.setPlaceId(clean);
        widget.onChanged();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(BranchFormWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.name != widget.draft.name &&
        _nameCtrl.text != widget.draft.name) {
      _nameCtrl.text = widget.draft.name;
    }
    if (oldWidget.draft.whatsappMonitoredBy != widget.draft.whatsappMonitoredBy &&
        _whatsappMonitoredByCtrl.text != widget.draft.whatsappMonitoredBy) {
      _whatsappMonitoredByCtrl.text = widget.draft.whatsappMonitoredBy;
    }
    if (oldWidget.draft.address != widget.draft.address &&
        _addressCtrl.text != widget.draft.address) {
      _addressCtrl.text = widget.draft.address;
    }
    if (oldWidget.draft.placeId != widget.draft.placeId &&
        _placeIdCtrl.text != (widget.draft.placeId ?? '')) {
      _placeIdCtrl.text = widget.draft.placeId ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _whatsappMonitoredByCtrl.dispose();
    _addressCtrl.dispose();
    _placeIdCtrl.dispose();
    _searchNameCtrl.dispose();
    _searchCityCtrl.dispose();

    _nameFocus.dispose();
    _addressFocus.dispose();
    _whatsappMonitoredByFocus.dispose();
    _placeIdFocus.dispose();
    _searchNameFocus.dispose();
    _searchCityFocus.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _search() async {
    setState(() {
      _searchNameError = null;
      _searchCityError = null;
    });

    final bizName = _searchNameCtrl.text.trim();
    final city    = _searchCityCtrl.text.trim();

    if (bizName.isEmpty) {
      setState(() => _searchNameError = 'Enter business name');
      _searchNameFocus.requestFocus();
      return;
    }

    if (city.isEmpty) {
      setState(() => _searchCityError = 'Enter city');
      _searchCityFocus.requestFocus();
      return;
    }

    setState(() {
      widget.draft.isSearching = true;
      widget.draft.searchError = null;
      widget.draft.candidates  = [];
    });

    try {
      final placesSvc = context.read<PlacesService>();
      final results   = await placesSvc.search(bizName, city);
      if (mounted) {
        setState(() {
          widget.draft.candidates  = results;
          widget.draft.searchError = results.isEmpty
              ? 'No matches found — try a different name or enter manually.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          widget.draft.candidates  = [];
          widget.draft.searchError = 'Search failed — use manual entry below.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          widget.draft.isSearching = false;
        });
      }
      widget.onChanged();
    }
  }

  void _confirmCandidate(dynamic candidate) {
    widget.draft.confirmCandidate(candidate);
    // Sync controllers to auto-filled values
    _addressCtrl.text = widget.draft.address;
    _placeIdCtrl.text = widget.draft.placeId ?? '';
    widget.onChanged();
  }

  void _clearSearch() {
    widget.draft.clearSearch();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = widget.draft;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row (label + remove button) ─────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.showBranchName
                      ? 'Branch ${widget.branchIndex + 1}'
                      : 'Location Details',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  tooltip: 'Remove branch',
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Branch name (multi mode only) ───────────────────────────────
          if (widget.showBranchName) ...[
            TextFormField(
              controller: _nameCtrl,
              focusNode:  _nameFocus,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Branch name *',
                hintText: 'e.g. Andheri Branch',
                errorText: widget.showError && draft.name.trim().isEmpty
                    ? 'Branch name is required'
                    : null,
              ),
              onChanged: (v) {
                draft.name = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 12),
          ],

          // ── WhatsApp number (PhoneField — E.164 +91XXXXXXXXXX) ───────────
          PhoneField(
            label: 'WhatsApp number *',
            helperText: 'Customer feedback messages go to this number',
            initialValue: draft.whatsappNumber,
            showError: widget.showError,
            onChanged: (e164) {
              draft.whatsappNumber = e164;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.copy_outlined, size: 14),
              label: const Text('Same as Owner WhatsApp & Contact', style: TextStyle(fontSize: 12)),
              onPressed: () {
                String phone = widget.ownerPhone ?? '';
                String name = widget.ownerName ?? '';
                if (phone.isEmpty && context.mounted) {
                  try {
                    final enroll = context.read<EnrollProvider>();
                    phone = enroll.ownerPhone;
                    if (name.isEmpty) name = enroll.ownerName;
                  } catch (_) {}
                }
                if (phone.isNotEmpty) {
                  var clean = phone.replaceAll(RegExp(r'\D'), '');
                  if (clean.startsWith('91') && clean.length > 10) clean = clean.substring(2);
                  if (clean.startsWith('0') && clean.length > 10) clean = clean.substring(1);
                  if (clean.length > 10) clean = clean.substring(0, 10);
                  draft.whatsappNumber = clean.isNotEmpty ? '+91$clean' : '';
                }
                final monitorName = name.trim().isNotEmpty
                    ? '${name.trim()} (Owner)'
                    : 'Owner';
                draft.whatsappMonitoredBy = monitorName;
                _whatsappMonitoredByCtrl.text = monitorName;
                widget.onChanged();
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 8),

          // ── Change 5: WhatsApp monitored by ─────────────────────────────
          // Who watches this WhatsApp channel for incoming 1–3 star feedback?
          // Required so the team always knows who handles negative messages,
          // even after staff changes.
          TextFormField(
            controller: _whatsappMonitoredByCtrl,
            focusNode:  _whatsappMonitoredByFocus,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'WhatsApp monitored by *',
              hintText: 'e.g. Owner / Manager Ravi / Front Desk',
              helperText: 'Person responsible for 1–3 star WhatsApp messages',
              errorText: widget.showError &&
                      draft.whatsappMonitoredBy.trim().isEmpty
                  ? 'WhatsApp monitor contact is required'
                  : null,
            ),
            onChanged: (v) {
              draft.whatsappMonitoredBy = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 20),

          // ── Place auto-search ───────────────────────────────────────────
          Text('Google Maps (optional — or skip and type address below)',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchNameCtrl,
                  focusNode:  _searchNameFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Business name (e.g. Brew Bar)',
                    prefixIcon: const Icon(Icons.store_outlined),
                    errorText: _searchNameError,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (_searchNameError != null) {
                      setState(() => _searchNameError = null);
                    }
                  },
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCityCtrl,
                  focusNode:  _searchCityFocus,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'City (e.g. Mumbai)',
                    prefixIcon: const Icon(Icons.location_city_outlined),
                    errorText: _searchCityError,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (_searchCityError != null) {
                      setState(() => _searchCityError = null);
                    }
                  },
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: draft.isSearching ? null : _search,
                child: draft.isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Search'),
              ),
            ],
          ),

          // ── Candidates ──────────────────────────────────────────────────
          if (draft.candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Select the correct business:',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            ...draft.candidates.map(
              (c) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined, size: 20),
                  title: Text(c.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13)),
                  subtitle: Text(c.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () => _confirmCandidate(c),
                    child: const Text('Use this'),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: _clearSearch,
              child: const Text('Clear results'),
            ),
          ],

          // Search error
          if (draft.searchError != null && !draft.isSearching)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                draft.searchError!,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),

          // Pre-filled badge
          if (draft.placePrefilled && draft.candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 14, color: AppColors.activeFg),
                  const SizedBox(width: 4),
                  Text(
                    'Auto-filled from Google Maps — you can still edit below.',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.activeFg),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── Address (always visible, always editable) ───────────────────
          TextFormField(
            controller: _addressCtrl,
            focusNode:  _addressFocus,
            decoration: InputDecoration(
              labelText: 'Full address *',
              hintText: '123 Main Street, Mumbai 400001',
              errorText: widget.showError && draft.address.trim().isEmpty
                  ? 'Address is required'
                  : null,
            ),
            maxLines: 2,
            onChanged: (v) {
              draft.address = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),

          // ── Place ID (required for Google review redirection) ──────────────────
          TextFormField(
            controller: _placeIdCtrl,
            focusNode:  _placeIdFocus,
            decoration: InputDecoration(
              labelText: 'Google Place ID *',
              hintText: 'ChIJN1t_tDeuEmsRUsoyG83frY4',
              helperText: _hasInvalidPlaceIdFormat
                  ? "⚠️ This doesn't look like a valid Place ID"
                  : 'Required for 5-star review redirection. Auto-filled from Maps search above.',
              helperStyle: _hasInvalidPlaceIdFormat
                  ? TextStyle(color: scheme.error, fontWeight: FontWeight.w500)
                  : null,
              errorText: widget.showError &&
                      (draft.placeId == null || draft.placeId!.trim().isEmpty)
                  ? 'Google Place ID is required for 5-star review routing'
                  : null,
            ),
            onChanged: (v) {
              final clean = StringUtils.sanitizePlaceId(v);
              if (v != clean) {
                _placeIdCtrl.value = TextEditingValue(
                  text: clean,
                  selection: TextSelection.collapsed(offset: clean.length),
                );
              }
              draft.setPlaceId(clean);
              widget.onChanged();
              setState(() {});
            },
          ),

          const SizedBox(height: 24),

          // ── Star routing ─────────────────────────────────────────────────
          StarRoutingWidget(
            draft:      draft,
            onChanged:  widget.onChanged,
            showError:  widget.showError,
          ),
        ],
      ),
    );
  }
}
