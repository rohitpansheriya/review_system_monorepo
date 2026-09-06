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

class AdminLeadsTab extends StatefulWidget {
  const AdminLeadsTab({super.key});

  @override
  State<AdminLeadsTab> createState() => _AdminLeadsTabState();
}

class _AdminLeadsTabState extends State<AdminLeadsTab> {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'lead', 'contacted', 'converted', 'archived'

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
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Lead'),
        content: Text('Are you sure you want to permanently delete lead for "${lead.businessName}" (${lead.name})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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

  Color _statusColor(String status) {
    switch (status) {
      case 'lead':
        return const Color(0xFFEF4444); // Red / Hot
      case 'contacted':
        return const Color(0xFFF59E0B); // Amber
      case 'converted':
        return const Color(0xFF10B981); // Emerald
      case 'archived':
        return const Color(0xFF64748B); // Slate
      default:
        return const Color(0xFF4F46E5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leads')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
                  _buildKpiCard('Total Inquiries', '$totalCount', Icons.contact_page, const Color(0xFF4F46E5)),
                  _buildKpiCard('New / Uncontacted', '$newCount', Icons.fiber_new, const Color(0xFFEF4444)),
                  _buildKpiCard('Contacted / In Progress', '$contactedCount', Icons.phone_in_talk, const Color(0xFFF59E0B)),
                  _buildKpiCard('Converted Clients', '$convertedCount', Icons.verified, const Color(0xFF10B981)),
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
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          onChanged: (v) => setState(() => _searchQuery = v.trim()),
                          decoration: InputDecoration(
                            hintText: 'Search by business, name, phone, city...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          _filterChip('all', 'All ($totalCount)'),
                          _filterChip('lead', 'New ($newCount)'),
                          _filterChip('contacted', 'Contacted ($contactedCount)'),
                          _filterChip('converted', 'Converted ($convertedCount)'),
                          _filterChip('archived', 'Archived'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Leads List / Table
              if (filteredLeads.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox, size: 48, color: scheme.primary.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                            'No leads found matching current filter',
                            style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
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

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Business Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFEEF2FF),
            child: const Icon(Icons.storefront, color: Color(0xFF4F46E5), size: 24),
          ),
          const SizedBox(width: 16),

          // Core Lead Info
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      lead.businessName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        lead.city,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      lead.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      lead.phone,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
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
          const SizedBox(width: 16),

          // Status Badge / Dropdown
          DropdownButton<String>(
            value: lead.status,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(12),
            items: [
              _statusDropdownItem('lead', 'New Lead', _statusColor('lead')),
              _statusDropdownItem('contacted', 'Contacted', _statusColor('contacted')),
              _statusDropdownItem('converted', 'Converted', _statusColor('converted')),
              _statusDropdownItem('archived', 'Archived', _statusColor('archived')),
            ],
            onChanged: (val) {
              if (val != null) _updateLeadStatus(lead.id, val);
            },
          ),
          const SizedBox(width: 16),

          // Action Buttons: WhatsApp, Call, Enroll, Delete
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // WhatsApp Button
              IconButton.filledTonal(
                onPressed: () => _openWhatsApp(lead),
                icon: const Icon(Icons.chat, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF128C7E),
                ),
                tooltip: 'WhatsApp Lead',
              ),
              const SizedBox(width: 8),

              // Call Button
              IconButton.filledTonal(
                onPressed: () => _callPhone(lead),
                icon: const Icon(Icons.phone, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFF4F46E5),
                ),
                tooltip: 'Call Phone',
              ),
              const SizedBox(width: 8),

              // 1-Click Enroll Button
              FilledButton.icon(
                onPressed: () {
                  // Direct to Enroll tab with pre-fill info
                  context.go('/admin?tab=enroll');
                },
                icon: const Icon(Icons.add_business, size: 16),
                label: const Text('Enroll'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),

              // Delete button
              IconButton(
                onPressed: () => _deleteLead(lead),
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                tooltip: 'Delete Lead',
              ),
            ],
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _statusDropdownItem(String value, String label, Color color) {
    return DropdownMenuItem<String>(
      value: value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 4, backgroundColor: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
