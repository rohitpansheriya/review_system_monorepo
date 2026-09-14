// lib/widgets/app_search_bar.dart
//
// Modern reusable search bar with clear button, subtle shadow, and rounded styling.

import 'package:flutter/material.dart';

class AppSearchBar extends StatefulWidget {
  final String? initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final double? width;
  final double height;
  final TextEditingController? controller;

  const AppSearchBar({
    super.key,
    this.initialValue,
    this.hintText = 'Search…',
    required this.onChanged,
    this.onClear,
    this.width,
    this.height = 42,
    this.controller,
  });

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  late final TextEditingController _ctrl;
  bool _internalCtrl = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _ctrl = widget.controller!;
    } else {
      _ctrl = TextEditingController(text: widget.initialValue ?? '');
      _internalCtrl = true;
    }
  }

  @override
  void dispose() {
    if (_internalCtrl) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget bar = Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00458B).withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: _ctrl,
        onChanged: (val) {
          setState(() {});
          widget.onChanged(val);
        },
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 19,
            color: colorScheme.primary,
          ),
          suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.cancel_rounded,
                    size: 17,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _ctrl.clear();
                    setState(() {});
                    widget.onChanged('');
                    widget.onClear?.call();
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );

    if (widget.width != null) {
      return SizedBox(width: widget.width, child: bar);
    }
    return bar;
  }
}
