// lib/core/phone_field.dart
//
// Reusable India-only phone/WhatsApp input widget.
//
// UI:    fixed "+91" prefix | 10-digit input
// Store: E.164 "+91XXXXXXXXXX"  (what is passed via onChanged)
// Valid: leading digit 6–9, exactly 10 digits
//
// wa.me compatibility note:
//   Stored values look like "+91XXXXXXXXXX".
//   The review page JS strips the leading "+" before building the wa.me URL
//   (see public/r/index.html) → produces "91XXXXXXXXXX" which wa.me requires.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneField extends StatefulWidget {
  /// Label shown above the field.
  final String label;

  /// Helper text shown below the field.
  final String? helperText;

  /// Initial E.164 value (e.g. "+919876543210").
  /// The widget strips the "+91" prefix for display.
  final String initialValue;

  /// Called with the full E.164 string every time the value changes.
  final ValueChanged<String> onChanged;

  /// Whether to show the error state (red border + message).
  final bool showError;

  /// Override the default "required" error text.
  final String? errorText;

  const PhoneField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialValue = '',
    this.helperText,
    this.showError = false,
    this.errorText,
  });

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late final TextEditingController _ctrl;
  String? _validationError;

  static const String _prefix = '+91';
  static final RegExp _validDigits = RegExp(r'^[6-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    // Strip "+91" prefix from initial value for display
    final raw = widget.initialValue;
    final display = raw.startsWith(_prefix)
        ? raw.substring(_prefix.length)
        : raw;
    _ctrl = TextEditingController(text: display);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onInputChanged(String digits) {
    final clean = digits.trim();
    String? err;
    if (clean.isEmpty) {
      err = null; // empty handled by showError path below
    } else if (!_validDigits.hasMatch(clean)) {
      err = 'Enter a valid 10-digit number starting with 6–9';
    }
    setState(() => _validationError = err);
    // Always emit E.164 — even if partially typed — so provider state stays live
    widget.onChanged(_prefix + clean);
  }

  String? get _errorText {
    if (widget.showError && _ctrl.text.trim().isEmpty) {
      return widget.errorText ?? '${widget.label} is required';
    }
    return _validationError;
  }

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final hasError = _errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Input row ─────────────────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // +91 prefix box — matches input field height/border exactly
            Container(
              height: 52, // aligns with input contentPadding 14 + border
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border.all(
                  color: hasError
                      ? cs.error
                      : cs.outline.withValues(alpha: 0.5),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft:    Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Text(
                  _prefix,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // 10-digit input — removes left radius so it joins the prefix box
            Expanded(
              child: TextFormField(
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: _onInputChanged,
                decoration: InputDecoration(
                  labelText: widget.label,
                  helperText: widget.helperText,
                  errorText: _errorText,
                  counterText: '',      // hide the maxLength counter
                  hintText: '98765 43210',
                  // Override border radius to join the prefix box
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight:    Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    borderSide: BorderSide(
                      color: hasError
                          ? cs.error
                          : cs.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight:    Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight:    Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    borderSide: BorderSide(color: cs.error),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.only(
                      topRight:    Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    borderSide: BorderSide(color: cs.error, width: 2),
                  ),
                  // No left border — prefix box provides it
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.only(
                      topRight:    Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
