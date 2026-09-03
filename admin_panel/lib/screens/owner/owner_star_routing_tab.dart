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
                      if (provider.isGracePeriod)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEF4444)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock_clock, color: Color(0xFFDC2626), size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Star-routing editing is locked during grace period. Renew your subscription to modify settings.',
                                  style: TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: (_saving || provider.isGracePeriod) ? null : _saveStarRouting,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            provider.isGracePeriod
                                ? 'Locked (Grace Period Active)'
                                : (_saving ? 'Saving...' : 'Save Star-Routing Config'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Interactive WhatsApp Private Resolution Live Preview ─────────
              Card(
                elevation: 0,
                color: const Color(0xFFF0FDF4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFBBF7D0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live WhatsApp Private Feedback Preview',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF14532D),
                                  ),
                                ),
                                Text(
                                  'What you receive on +91 ${currentBranch.whatsappNumber} when a 1–3★ customer submits feedback',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF166534),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Smartphone Chat Mockup
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5DDD5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // WhatsApp Chat Bubble
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 480),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(14),
                                    bottomLeft: Radius.circular(14),
                                    bottomRight: Radius.circular(14),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hello, I visited ${provider.business?.brandName ?? 'your store'} (${currentBranch.branchName}) today and would like to share private feedback.',
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.4),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFFECACA)),
                                      ),
                                      child: const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Issue: ⏳ Long Wait Time, 🍽️ Food Quality',
                                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Details: "Food was cold and took 30 mins to arrive."',
                                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF7F1D1D)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Align(
                                      alignment: Alignment.bottomRight,
                                      child: Text(
                                        'Just now • Sent via AppNexa Smart QR',
                                        style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
