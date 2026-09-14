// lib/screens/admin/admin_leads_tab.dart
//
// Inbound Website Leads CRM Tab for Platform Admin.
// Real-time Firestore stream displaying leads captured from the public landing page.
// Features:
//   - KPI Metrics (Total, New Uncontacted, Contacted, Converted)
//   - Real-time Firestore stream listener
//   - 1-Click WhatsApp Chat with pre-filled greeting message
//   - 1-Click Phone Call
//   - Quick Status updating (New -> Contacted -> Converted -> Archived)
//   - 1-Click "Enroll as Business" trigger
//   - Delete spam lead action

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/lead_model.dart';
import '../../widgets/app_animated_loader.dart';
import '../../widgets/app_badge.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_kpi_card.dart';
import '../../widgets/app_search_bar.dart';

class AdminLeadsTab extends StatefulWidget {
  const AdminLeadsTab({super.key});

  @override
  State<AdminLeadsTab> createState() => _AdminLeadsTabState();
}

class _AdminLeadsTabState extends State<AdminLeadsTab>
    with AutomaticKeepAliveClientMixin {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'lead', 'contacted', 'converted', 'archived'
  late final Stream<QuerySnapshot> _leadsStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _leadsStream = FirebaseFirestore.instance
        .collection('leads')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _openWhatsApp(LeadModel lead) {
    var phone = lead.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('0')) phone = phone.substring(1);
    if (phone.length == 10) phone = '91$phone';

    final greeting = Uri.encodeComponent(
      'Hi ${lead.name}, thanks for requesting an AppNexa 5-Star Google Review Standee for ${lead.businessName} (${lead.city})! We would love to share your custom standee design preview.',
    );
    final url = 'https://wa.me/$phone?text=$greeting';
    html.window.open(url, '_blank');
  }

  void _callPhone(LeadModel lead) {
    final clean = lead.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    html.window.open('tel:$clean', '_self');
  }

  Future<void> _updateLeadStatus(String leadId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('leads').doc(leadId).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lead marked as ${_statusLabel(newStatus)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update lead: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteLead(LeadModel lead) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppModalDialog(
        icon: Icons.delete_outline_rounded,
        iconColor: Colors.red,
        title: 'Delete Lead',
        subtitle: 'Permanent removal of inbound lead',
        maxWidth: 440,
        content: Text(
          'Are you sure you want to permanently delete the lead for "${lead.businessName}" (${lead.name})?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Lead'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('leads').doc(lead.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lead deleted.')),
        );
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'lead':
        return 'New Lead';
      case 'contacted':
        return 'Contacted';
      case 'converted':
        return 'Converted';
      case 'archived':
        return 'Archived';
      default:
        return status;
    }
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: _leadsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: AppAnimatedLoader.card(message: 'Loading Inbound Leads...'));
        }

        final docs = snapshot.data?.docs ?? [];
        final allLeads = docs.map((d) => LeadModel.fromDoc(d)).toList();

        // Compute KPIs
        final totalCount = allLeads.length;
        final newCount = allLeads.where((l) => l.status == 'lead').length;
        final contactedCount = allLeads.where((l) => l.status == 'contacted').length;
        final convertedCount = allLeads.where((l) => l.status == 'converted').length;

        // Filter leads
        final filteredLeads = allLeads.where((lead) {
          if (_statusFilter != 'all' && lead.status != _statusFilter) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final match = lead.name.toLowerCase().contains(q) ||
                lead.businessName.toLowerCase().contains(q) ||
                lead.phone.toLowerCase().contains(q) ||
                lead.city.toLowerCase().contains(q) ||
                lead.message.toLowerCase().contains(q);
            if (!match) return false;
          }
          return true;
        }).toList();

        return SingleChildScrollView(
          key: const PageStorageKey<String>('admin_leads_scroll_view'),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flash_on, color: Color(0xFFF59E0B), size: 28),
                          const SizedBox(width: 8),
                          Text(
                            'Website Inbound Leads (CRM)',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live inbound enquiries submitted from the public landing page & 3D Standee customizer.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // KPI Metric Cards
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 220,
                    child: AppKpiCard(
                      compact: true,
                      label: 'Total Inquiries',
                      value: '$totalCount',
                      icon: Icons.contact_page_rounded,
                      color: const Color(0xFF4F46E5),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: AppKpiCard(
                      compact: true,
                      label: 'New / Uncontacted',
                      value: '$newCount',
                      icon: Icons.fiber_new_rounded,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: AppKpiCard(
                      compact: true,
                      label: 'Contacted / In Progress',
                      value: '$contactedCount',
                      icon: Icons.phone_in_talk_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: AppKpiCard(
                      compact: true,
                      label: 'Converted Clients',
                      value: '$convertedCount',
                      icon: Icons.verified_rounded,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Search & Filter Controls
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 700;
                      final searchField = AppSearchBar(
                        hintText: 'Search by business, name, phone, city...',
                        initialValue: _searchQuery,
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      );

                      final filters = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _filterChip('all', 'All ($totalCount)'),
                          _filterChip('lead', 'New ($newCount)'),
                          _filterChip('contacted', 'Contacted ($contactedCount)'),
                          _filterChip('converted', 'Converted ($convertedCount)'),
                          _filterChip('archived', 'Archived'),
                        ],
                      );

                      return isWide
                          ? Row(
                              children: [
                                Expanded(flex: 2, child: searchField),
                                const SizedBox(width: 16),
                                Expanded(flex: 3, child: filters),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchField,
                                const SizedBox(height: 12),
                                filters,
                              ],
                            );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Leads List / Table
              if (filteredLeads.isEmpty)
                AppEmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'No leads found',
                  subtitle: _searchQuery.isNotEmpty || _statusFilter != 'all'
                      ? 'No leads match your active search or filter criteria.'
                      : 'No inbound inquiries have been submitted yet.',
                  actionLabel: _searchQuery.isNotEmpty || _statusFilter != 'all' ? 'Clear Filters' : null,
                  onAction: _searchQuery.isNotEmpty || _statusFilter != 'all'
                      ? () => setState(() {
                            _searchQuery = '';
                            _statusFilter = 'all';
                          })
                      : null,
                )
              else
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredLeads.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final lead = filteredLeads[index];
                      return _buildLeadTile(lead, scheme);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(String status, String label) {
    final active = _statusFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _statusFilter = status),
      selectedColor: const Color(0xFF4F46E5),
      labelStyle: TextStyle(
        color: active ? Colors.white : const Color(0xFF475569),
        fontWeight: active ? FontWeight.bold : FontWeight.w500,
        fontSize: 12,
      ),
    );
  }

  Widget _buildLeadTile(LeadModel lead, ColorScheme scheme) {
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(lead.createdAt);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;

        final coreInfo = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFEEF2FF),
              child: const Icon(Icons.storefront, color: Color(0xFF4F46E5), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        lead.businessName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      AppBadge(
                        label: lead.city,
                        backgroundColor: const Color(0xFFF1F5F9),
                        foregroundColor: const Color(0xFF475569),
                        fontSize: 11,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            lead.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            lead.phone,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (lead.message.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '“${lead.message}”',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Received: $dateStr • Source: ${lead.source}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: lead.status,
              underline: const SizedBox.shrink(),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(14),
              elevation: 8,
              icon: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Color(0xFF6B7A99),
                ),
              ),
              items: [
                DropdownMenuItem<String>(value: 'lead', child: AppBadge.lead('lead')),
                DropdownMenuItem<String>(value: 'contacted', child: AppBadge.lead('contacted')),
                DropdownMenuItem<String>(value: 'converted', child: AppBadge.lead('converted')),
                DropdownMenuItem<String>(value: 'archived', child: AppBadge.lead('archived')),
              ],
              onChanged: (val) {
                if (val != null) _updateLeadStatus(lead.id, val);
              },
            ),
            IconButton.filledTonal(
              onPressed: () => _openWhatsApp(lead),
              icon: const Icon(Icons.chat, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                foregroundColor: const Color(0xFF128C7E),
              ),
              tooltip: 'WhatsApp Lead',
            ),
            IconButton.filledTonal(
              onPressed: () => _callPhone(lead),
              icon: const Icon(Icons.phone, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                foregroundColor: const Color(0xFF4F46E5),
              ),
              tooltip: 'Call Phone',
            ),
            FilledButton.icon(
              onPressed: () => context.go('/admin?tab=enroll'),
              icon: const Icon(Icons.add_business, size: 16),
              label: const Text('Enroll'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
            IconButton(
              onPressed: () => _deleteLead(lead),
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
              tooltip: 'Delete Lead',
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.all(16),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: coreInfo),
                    const SizedBox(width: 16),
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    coreInfo,
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    actions,
                  ],
                ),
        );
      },
    );
  }

}
