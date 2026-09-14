// lib/screens/owner/owner_star_routing_tab.dart
//
// Star-Routing Overview Tab for Business Owner (Read-Only).
// Displays the active 1-5 star routing configuration and explains
// how 1-3★ negative feedback is routed privately while 4-5★ reviews
// are directed to Google Reviews. Read-only to prevent accidental misconfigurations.

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/branch_model.dart';
import '../../providers/owner_dashboard_provider.dart';

class OwnerStarRoutingTab extends StatefulWidget {
  const OwnerStarRoutingTab({super.key});

  @override
  State<OwnerStarRoutingTab> createState() => _OwnerStarRoutingTabState();
}

class _OwnerStarRoutingTabState extends State<OwnerStarRoutingTab> {
  String? _selectedBranchId;

  @override
  void initState() {
    super.initState();
  }

  void _onBranchChanged(String? newId) {
    if (newId == null || newId == _selectedBranchId) return;
    setState(() {
      _selectedBranchId = newId;
    });
  }

  void _openWhatsAppSupport() {
    const supportUrl =
        'https://wa.me/918866390389?text=Hello%20AppNexa%20Support,%20I%20would%20like%20to%20request%20a%20change%20to%20my%20review%20routing%20configuration.';
    html.window.open(supportUrl, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OwnerDashboardProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final branches = provider.branches;

    if (branches.isEmpty) {
      return const Center(
        child: Text('No branch available for star routing overview.'),
      );
    }

    _selectedBranchId ??= branches.first.id;
    final currentBranch = branches.firstWhere(
      (b) => b.id == _selectedBranchId,
      orElse: () => branches.first,
    );

    final isDesktop = MediaQuery.of(context).size.width > 700;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Review Routing Overview',
                style: (isDesktop
                        ? theme.textTheme.headlineMedium
                        : theme.textTheme.titleLarge)
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'View how customer ratings (1–5 stars) are routed from your Smart Standee QR code.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // ── Security & Reputation Shield Notice ───────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFF0284C7),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'AppNexa Reputation Shield',
                                style: GoogleFonts.outfit(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFBAE6FD)),
                                ),
                                child: Text(
                                  'Protected & Verified',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0369A1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'To protect your business from accidental misconfigurations and public negative reviews, star routing is managed securely. 1–3★ ratings are intercepted privately on WhatsApp, and 4–5★ happy customers are directed straight to Google Reviews.',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: const Color(0xFF475569),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Multi-branch selector if > 1 branch
              if (branches.length > 1) ...[
                Text(
                  'Select Branch Location',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value:         currentBranch.id,
                  dropdownColor: Colors.white,
                  borderRadius:  BorderRadius.circular(14),
                  elevation:     8,
                  icon:          const Icon(Icons.keyboard_arrow_down_rounded),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.storefront_outlined),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: branches
                      .map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.branchName),
                          ))
                      .toList(),
                  onChanged: _onBranchChanged,
                ),
                const SizedBox(height: 20),
              ],

              // ── Star Routing Breakdown Cards ──────────────────────────────
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isDesktop ? 22.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.route_outlined,
                              color: colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Active Star Routing Map',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Current action triggered when customers tap each star rating:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // List 5 stars down to 1 star (or 1 to 5)
                      ...List.generate(5, (index) {
                        final starNum = 5 - index; // 5, 4, 3, 2, 1
                        final starKey = '$starNum';
                        final routeAction = currentBranch
                                .starRoutingConfig[starKey] ??
                            (starNum >= 4
                                ? AppConstants.routingGoogle
                                : AppConstants.routingWhatsapp);

                        return _buildStarRouteRow(
                          context,
                          starNum: starNum,
                          routeAction: routeAction,
                          branch: currentBranch,
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── WhatsApp Private Feedback Live Preview ────────────────────
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
                            child: const Icon(Icons.chat_rounded,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live WhatsApp Private Resolution Preview',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF14532D),
                                  ),
                                ),
                                Text(
                                  'What you receive on +91 ${currentBranch.whatsappNumber} when a 1–3★ customer shares feedback',
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
                                constraints:
                                    const BoxConstraints(maxWidth: 480),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
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
                                      color:
                                          Colors.black.withValues(alpha: 0.06),
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
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF1E293B),
                                          height: 1.4),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFFFECACA)),
                                      ),
                                      child: const Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Issue: ⏳ Long Wait Time, 🍽️ Food Quality',
                                            style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF991B1B)),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Details: "Food was cold and took 30 mins to arrive."',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontStyle: FontStyle.italic,
                                                color: Color(0xFF7F1D1D)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Align(
                                      alignment: Alignment.bottomRight,
                                      child: Text(
                                        'Just now • Sent via AppNexa Smart QR',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF94A3B8)),
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

              const SizedBox(height: 24),

              // ── Request Changes / Contact Support Card ────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.help_outline_rounded,
                        color: Color(0xFF64748B), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Need to adjust your review routing threshold?',
                            style: GoogleFonts.outfit(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Our team can review and update your routing settings anytime upon request.',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _openWhatsAppSupport,
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Contact Support'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        textStyle: GoogleFonts.outfit(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarRouteRow(
    BuildContext context, {
    required int starNum,
    required String routeAction,
    required BranchModel branch,
  }) {
    final isGoogle = routeAction == AppConstants.routingGoogle;
    final isWhatsApp = routeAction == AppConstants.routingWhatsapp;

    Color badgeBg;
    Color badgeBorder;
    Color badgeText;
    String badgeLabel;
    IconData actionIcon;
    String actionTitle;
    String actionDesc;

    if (isGoogle) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeBorder = const Color(0xFFFDE68A);
      badgeText = const Color(0xFF92400E);
      badgeLabel = 'PUBLIC GOOGLE REVIEW';
      actionIcon = Icons.star_rounded;
      actionTitle = 'Google Reviews (Public Listing)';
      actionDesc =
          'Pre-fills high-rating phrases & directly opens Google Maps review posting screen to increase public 5★ rating.';
    } else if (isWhatsApp) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeBorder = const Color(0xFFBBF7D0);
      badgeText = const Color(0xFF166534);
      badgeLabel = 'PRIVATE WHATSAPP RESOLUTION';
      actionIcon = Icons.chat_rounded;
      actionTitle = 'WhatsApp Private Feedback (+91 ${branch.whatsappNumber})';
      actionDesc =
          'Redirects customer to your private WhatsApp chat with pre-selected problem tags to resolve complaints directly.';
    } else {
      badgeBg = const Color(0xFFF1F5F9);
      badgeBorder = const Color(0xFFE2E8F0);
      badgeText = const Color(0xFF475569);
      badgeLabel = 'PRIVATE THANK-YOU SCREEN';
      actionIcon = Icons.favorite_rounded;
      actionTitle = 'Thank-You Screen Only';
      actionDesc =
          'Displays an on-screen thank you card without directing to public review sites.';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isGoogle
            ? const Color(0xFFFFFBEB)
            : (isWhatsApp ? const Color(0xFFF8FAFC) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGoogle
              ? const Color(0xFFFDE68A)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Star Label Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$starNum',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.star_rounded,
                  color: AppColors.star,
                  size: 16,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Destination Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      actionIcon,
                      size: 16,
                      color: isGoogle
                          ? const Color(0xFFD97706)
                          : (isWhatsApp
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        actionTitle,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: badgeBorder),
                      ),
                      child: Text(
                        badgeLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: badgeText,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  actionDesc,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
