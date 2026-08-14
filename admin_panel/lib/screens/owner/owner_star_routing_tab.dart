// lib/screens/owner/owner_star_routing_tab.dart
//
// Star-Routing Config Tab for Business Owner.
// Editable table for stars 1-5 -> dropdowns (Thank-you / WhatsApp / Google review).
// Writes to branches/{id}.star_routing_config.
// REUSES StarRoutingWidget from enrollment.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/branch_draft.dart';
import '../../providers/owner_dashboard_provider.dart';
import '../enroll/star_routing_widget.dart';

class OwnerStarRoutingTab extends StatefulWidget {
  const OwnerStarRoutingTab({super.key});

  @override
  State<OwnerStarRoutingTab> createState() => _OwnerStarRoutingTabState();
}

class _OwnerStarRoutingTabState extends State<OwnerStarRoutingTab> {
  String? _selectedBranchId;
  BranchDraft? _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initDraft();
  }

  void _initDraft() {
    final provider = context.read<OwnerDashboardProvider>();
    if (provider.branches.isEmpty) return;

    _selectedBranchId ??= provider.branches.first.id;
    final branch = provider.branches.firstWhere(
      (b) => b.id == _selectedBranchId,
      orElse: () => provider.branches.first,
    );

    final d = BranchDraft();
    d.name = branch.branchName;
    d.whatsappNumber = branch.whatsappNumber;
    d.address = branch.address;

    branch.starRoutingConfig.forEach((k, v) {
      if (['1', '2', '3', '4', '5'].contains(k)) {
        d.setStarRoute(k, v);
      }
    });

    _draft = d;
  }

  void _onBranchChanged(String? newId) {
    if (newId == null || newId == _selectedBranchId) return;
    setState(() {
      _selectedBranchId = newId;
      _initDraft();
    });
  }

  Future<void> _saveStarRouting() async {
    if (_draft == null || !_draft!.starRoutingComplete || _selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select routing for all 5 stars.')),
      );
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<OwnerDashboardProvider>();

    try {
      await provider.updateStarRouting(
        _selectedBranchId!,
        _draft!.starRoutingAsMap,
      );

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Star-routing configuration saved successfully! Takes effect immediately.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save routing: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OwnerDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final branches = provider.branches;

    if (branches.isEmpty) {
      return const Center(child: Text('No branch available for star routing configuration.'));
    }

    final currentBranch = branches.firstWhere(
      (b) => b.id == _selectedBranchId,
      orElse: () => branches.first,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Star-Routing Configuration',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure what action is triggered when a customer taps 1–5 stars on the review page.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Multi-branch selector if > 1 branch
              if (branches.length > 1) ...[
                Text(
                  'Select Branch',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: currentBranch.id,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: branches
                      .map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.branchName),
                          ))
                      .toList(),
                  onChanged: _onBranchChanged,
                ),
                const SizedBox(height: 24),
              ],

              // Reused StarRoutingWidget from enrollment
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      if (_draft != null)
                        StarRoutingWidget(
                          draft: _draft!,
                          onChanged: () => setState(() {}),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveStarRouting,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: Text(_saving ? 'Saving...' : 'Save Star-Routing Config'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
