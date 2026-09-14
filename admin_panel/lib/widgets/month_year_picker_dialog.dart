// lib/widgets/month_year_picker_dialog.dart
//
// A modern, tactile, grid-based Month & Year selector dialog.
// Replaces cluttered dropdowns with an interactive visual calendar grid,
// year navigation, and one-tap presets (This Month, Last Month, All Time, Custom Range).

import 'package:flutter/material.dart';

class MonthYearPickerDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final bool isAllTime;

  const MonthYearPickerDialog({
    super.key,
    required this.initialYear,
    required this.initialMonth,
    this.isAllTime = false,
  });

  static Future<void> show({
    required BuildContext context,
    required int initialYear,
    required int initialMonth,
    required bool isAllTime,
    required void Function(int year, int month) onMonthSelected,
    required VoidCallback onAllTimeSelected,
    required VoidCallback onCustomRangeSelected,
  }) async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => MonthYearPickerDialog(
        initialYear: initialYear,
        initialMonth: initialMonth,
        isAllTime: isAllTime,
      ),
    );

    if (result == null) return;

    if (result == 'all') {
      onAllTimeSelected();
    } else if (result == 'custom') {
      onCustomRangeSelected();
    } else if (result is Map<String, int>) {
      onMonthSelected(result['year']!, result['month']!);
    }
  }

  @override
  State<MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<MonthYearPickerDialog> {
  late int _selectedYear;
  late int _selectedMonth;
  late final DateTime _now;

  final List<String> _monthNames = const [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'
  ];

  final List<String> _monthShortNames = const [
    'Jan', 'Feb', 'Mar', 'Apr',
    'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _selectedYear = widget.initialYear;
    _selectedMonth = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header & Close Button ────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.calendar_month_rounded, size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Period',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Filter business enrollments by month',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Quick Presets ────────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _PresetChip(
                      icon: Icons.flash_on_rounded,
                      label: 'This Month',
                      isSelected: !widget.isAllTime &&
                          _selectedYear == _now.year &&
                          _selectedMonth == _now.month,
                      onTap: () {
                        Navigator.of(context).pop({'year': _now.year, 'month': _now.month});
                      },
                    ),
                    const SizedBox(width: 6),
                    _PresetChip(
                      icon: Icons.history_rounded,
                      label: 'Last Month',
                      isSelected: false,
                      onTap: () {
                        final lastMonthDate = DateTime(_now.year, _now.month - 1, 1);
                        Navigator.of(context).pop({
                          'year': lastMonthDate.year,
                          'month': lastMonthDate.month,
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    _PresetChip(
                      icon: Icons.all_inclusive_rounded,
                      label: 'All Time',
                      isSelected: widget.isAllTime,
                      onTap: () => Navigator.of(context).pop('all'),
                    ),
                    const SizedBox(width: 6),
                    _PresetChip(
                      icon: Icons.date_range_rounded,
                      label: 'Custom Range…',
                      isSelected: false,
                      onTap: () => Navigator.of(context).pop('custom'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 14),

              // ── Year Navigator ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: 'Previous Year',
                      onPressed: () => setState(() => _selectedYear--),
                    ),
                    Row(
                      children: [
                        Text(
                          '$_selectedYear',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (_selectedYear == _now.year) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Current',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: 'Next Year',
                      onPressed: () => setState(() => _selectedYear++),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── 4x3 Interactive Month Grid ───────────────────────────────
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.7,
                ),
                itemCount: 12,
                itemBuilder: (ctx, index) {
                  final monthNum = index + 1;
                  final isCurrentMonth = _selectedYear == _now.year && monthNum == _now.month;
                  final isSelected = !widget.isAllTime &&
                      _selectedYear == widget.initialYear &&
                      monthNum == widget.initialMonth;

                  return _MonthTile(
                    shortName: _monthShortNames[index],
                    fullName: _monthNames[index],
                    isCurrent: isCurrentMonth,
                    isSelected: isSelected,
                    onTap: () {
                      Navigator.of(context).pop({
                        'year': _selectedYear,
                        'month': monthNum,
                      });
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Preset Chip Widget ────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Month Tile Widget ─────────────────────────────────────────────────────────

class _MonthTile extends StatelessWidget {
  final String shortName;
  final String fullName;
  final bool isCurrent;
  final bool isSelected;
  final VoidCallback onTap;

  const _MonthTile({
    required this.shortName,
    required this.fullName,
    required this.isCurrent,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color bgColor = isSelected
        ? scheme.primary
        : isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35);

    final Color textColor = isSelected
        ? scheme.onPrimary
        : scheme.onSurface;

    final Color subTextColor = isSelected
        ? scheme.onPrimary.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;

    final BorderSide borderSide = isSelected
        ? BorderSide.none
        : isCurrent
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.4), width: 1.5)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5));

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: borderSide,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shortName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected || isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (isCurrent && !isSelected) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: subTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
