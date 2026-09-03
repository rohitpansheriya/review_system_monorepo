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

class IndianPhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('91') && digits.length > 10) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length > 10) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class _PhoneFieldState extends State<PhoneField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  String? _validationError;

  static const String _prefix = '+91';
  static final RegExp _validDigits = RegExp(r'^[6-9]\d{9}$');

  static String _cleanDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('91') && digits.length > 10) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length > 10) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }
    return digits;
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    final clean = _cleanDigits(widget.initialValue);
    _ctrl = TextEditingController(text: clean);

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        final current = _cleanDigits(_ctrl.text);
        if (_ctrl.text != current) {
          _ctrl.text = current;
        }
        _onInputChanged(current);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      final clean = _cleanDigits(widget.initialValue);
      if (_ctrl.text != clean) {
        _ctrl.text = clean;
        _onInputChanged(clean);
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onInputChanged(String digits) {
    final clean = _cleanDigits(digits);
    String? err;
    if (clean.isEmpty) {
      err = null;
    } else if (clean.length < 10) {
      err = 'Phone number must be 10 digits (${clean.length}/10)';
    } else if (!_validDigits.hasMatch(clean)) {
      err = 'Enter a valid 10-digit number starting with 6–9';
    }
    setState(() => _validationError = err);
    // Emit E.164 (+91XXXXXXXXXX) when present, or empty string when blank
    widget.onChanged(clean.isEmpty ? '' : _prefix + clean);
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
                focusNode: _focusNode,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [IndianPhoneNumberFormatter()],
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
