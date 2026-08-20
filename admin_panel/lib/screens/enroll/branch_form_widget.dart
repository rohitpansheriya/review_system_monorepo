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
import '../../core/theme.dart';
import '../../models/branch_draft.dart';
import '../../providers/enroll_provider.dart';
import 'star_routing_widget.dart';

class BranchFormWidget extends StatefulWidget {
  final int branchIndex;
  final BranchDraft draft;
  final bool showBranchName;  // false in single mode, true in multi
  final bool showError;        // true after submit attempt
  final VoidCallback? onRemove; // null = remove button hidden
  final VoidCallback onChanged; // call when any field changes

  const BranchFormWidget({
    super.key,
    required this.branchIndex,
    required this.draft,
    required this.showBranchName,
    required this.onChanged,
    this.showError = false,
    this.onRemove,
  });

  @override
  State<BranchFormWidget> createState() => _BranchFormWidgetState();
}

class _BranchFormWidgetState extends State<BranchFormWidget> {
  // ── Local text controllers synced to draft ────────────────────────────────
  late final TextEditingController _nameCtrl;
  // _whatsappCtrl removed — PhoneField manages its own controller
  late final TextEditingController _whatsappMonitoredByCtrl; // Change 5
  late final TextEditingController _addressCtrl;
  late final TextEditingController _placeIdCtrl;
  late final TextEditingController _searchNameCtrl;
  late final TextEditingController _searchCityCtrl;

  final _nameFocus                 = FocusNode();
  final _whatsappMonitoredByFocus  = FocusNode();
  final _addressFocus              = FocusNode();

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _nameCtrl                 = TextEditingController(text: d.name);
    // _whatsappCtrl removed — PhoneField initialises from draft.whatsappNumber
    _whatsappMonitoredByCtrl  = TextEditingController(text: d.whatsappMonitoredBy);
    _addressCtrl              = TextEditingController(text: d.address);
    _placeIdCtrl              = TextEditingController(text: d.placeId ?? '');
    _searchNameCtrl           = TextEditingController();
    _searchCityCtrl           = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    // _whatsappCtrl not here — owned by PhoneField
    _whatsappMonitoredByCtrl.dispose();
    _addressCtrl.dispose();
    _placeIdCtrl.dispose();
    _searchNameCtrl.dispose();
    _searchCityCtrl.dispose();
    _nameFocus.dispose();
    _whatsappMonitoredByFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _search() {
    final bizName = _searchNameCtrl.text.trim();
    final city    = _searchCityCtrl.text.trim();
    if (bizName.isEmpty || city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both business name and city to search.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    context.read<EnrollProvider>().searchPlaces(
          widget.branchIndex, bizName, city);
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
    // Watch for searching/candidates changes
    context.watch<EnrollProvider>();
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
                final enroll = context.read<EnrollProvider>();
                if (enroll.ownerPhone.isNotEmpty) {
                  draft.whatsappNumber = enroll.ownerPhone;
                }
                final monitorName = enroll.ownerName.isNotEmpty
                    ? '${enroll.ownerName} (Owner)'
                    : 'Owner';
                draft.whatsappMonitoredBy = monitorName;
                _whatsappMonitoredByCtrl.text = monitorName;
                widget.onChanged();
                setState(() {});
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
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchNameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Business name (e.g. Brew Bar)',
                    prefixIcon: Icon(Icons.store_outlined),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCityCtrl,
                  decoration: const InputDecoration(
                    hintText: 'City (e.g. Mumbai)',
                    prefixIcon: Icon(Icons.location_city_outlined),
                    isDense: true,
                  ),
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

          // ── Place ID (always visible, always optional) ──────────────────
          TextFormField(
            controller: _placeIdCtrl,
            decoration: const InputDecoration(
              labelText: 'Google Place ID (optional)',
              hintText: 'ChIJN1t_tDeuEmsRUsoyG83frY4',
              helperText:
                  'Needed for Google review link. Find: Google Maps → Share → Copy place ID',
            ),
            onChanged: (v) {
              draft.setPlaceId(v);
              widget.onChanged();
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
