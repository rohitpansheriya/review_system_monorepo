// lib/widgets/category_template_visualizer.dart
//
// Interactive Live Mobile Smartphone Visualizer for Category Templates.
// Renders a realistic phone mockup showing the exact end-customer review experience
// with live category chips, AI generator, star rating routing, and review generation.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CategoryTemplateLiveVisualizer extends StatefulWidget {
  final String templateId;
  final String businessType;
  final List<String> categoryNames;
  final Map<String, List<String>> cachedPhrases;
  final VoidCallback? onRefresh;

  const CategoryTemplateLiveVisualizer({
    super.key,
    required this.templateId,
    required this.businessType,
    required this.categoryNames,
    required this.cachedPhrases,
    this.onRefresh,
  });

  @override
  State<CategoryTemplateLiveVisualizer> createState() =>
      _CategoryTemplateLiveVisualizerState();
}

class _CategoryTemplateLiveVisualizerState
    extends State<CategoryTemplateLiveVisualizer> {
  int _selectedRating = 5;
  String _selectedLang = 'en'; // 'en', 'hi', 'gu'
  final Set<String> _selectedCategories = {};
  final Map<String, String> _categoryPickedPhrase = {};
  final TextEditingController _reviewTextCtrl = TextEditingController();
  bool _copied = false;
  bool _aiGenerating = false;

  @override
  void initState() {
    super.initState();
    _initDefaultPhrases();
  }

  @override
  void didUpdateWidget(covariant CategoryTemplateLiveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.templateId != widget.templateId) {
      _selectedCategories.clear();
      _categoryPickedPhrase.clear();
      _reviewTextCtrl.clear();
      _initDefaultPhrases();
    } else {
      _rebuildReviewText();
    }
  }

  @override
  void dispose() {
    _reviewTextCtrl.dispose();
    super.dispose();
  }

  void _initDefaultPhrases() {
    if (widget.categoryNames.isNotEmpty) {
      // Pick first 2 categories by default for preview
      final firstCats = widget.categoryNames.take(2).toList();
      for (final cat in firstCats) {
        _selectedCategories.add(cat);
        _categoryPickedPhrase[cat] = _getPhraseForCategory(cat);
      }
      _rebuildReviewText();
    }
  }

  String _getPhraseForCategory(String category) {
    final pool = widget.cachedPhrases[category] ?? [];
    if (pool.isNotEmpty) {
      // Pick randomly or first
      return pool[math.Random().nextInt(pool.length)];
    }
    // Realistic fallback based on category name
    return 'Really loved the $category and great quality!';
  }

  void _toggleCategory(String cat) {
    setState(() {
      if (_selectedCategories.contains(cat)) {
        _selectedCategories.remove(cat);
        _categoryPickedPhrase.remove(cat);
      } else {
        _selectedCategories.add(cat);
        _categoryPickedPhrase[cat] = _getPhraseForCategory(cat);
      }
      _rebuildReviewText();
    });
  }

  void _rebuildReviewText() {
    final phrases = _selectedCategories
        .map((cat) => _categoryPickedPhrase[cat] ?? _getPhraseForCategory(cat))
        .where((p) => p.isNotEmpty)
        .toList();

    _reviewTextCtrl.text = phrases.join(' ');
  }

  void _triggerAiGeneration() {
    if (widget.categoryNames.isEmpty) return;
    setState(() {
      _aiGenerating = true;
      _selectedCategories.clear();
      _categoryPickedPhrase.clear();

      final shuffled = List<String>.from(widget.categoryNames)..shuffle();
      final count = math.min(shuffled.length, 2 + math.Random().nextInt(2));
      final selectedSubset = shuffled.take(count).toList();

      for (final cat in selectedSubset) {
        _selectedCategories.add(cat);
        _categoryPickedPhrase[cat] = _getPhraseForCategory(cat);
      }
      _rebuildReviewText();
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _aiGenerating = false);
    });
  }

  void _simulateCopy() {
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: const Color(0xFF334155), width: 4.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 32,
            spreadRadius: 2,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: Container(
          color: const Color(0xFFF8FAFC),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Phone Top Status Bar & Dynamic Island ───────────────
              _buildPhoneStatusBar(),

              // ── Phone Live Review Screen Content ────────────────────
              SizedBox(
                height: 580,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // Language Selector Bar
                      _buildLanguageBar(),
                      const SizedBox(height: 12),

                      // Business Brand Card Header
                      _buildBrandHeader(),
                      const SizedBox(height: 14),

                      // Star Rating Component
                      _buildStarRatingBar(),
                      const SizedBox(height: 16),

                      // 4-5 Stars Path vs 1-3 Stars Path
                      if (_selectedRating >= 4) ...[
                        // Category Chips Section
                        _buildCategoryChipsSection(),
                        const SizedBox(height: 14),

                        // Review Text Box with AI Button
                        _buildReviewTextBox(),
                        const SizedBox(height: 16),

                        // Google Maps Action Button
                        _buildGoogleMapsButton(),
                      ] else ...[
                        // Low Rating Private Feedback Routing
                        _buildLowRatingSection(),
                      ],

                      const SizedBox(height: 20),
                      // Integrity / Powered by Footer
                      Text(
                        '⚡ Verified Customer Review Experience',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),

              // ── Phone Home Bar ──────────────────────────────────────
              Container(
                width: 120,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStatusBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      color: const Color(0xFFF8FAFC),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '9:41',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          // Dynamic Island
          Container(
            width: 84,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.signal_cellular_alt, size: 12, color: Color(0xFF0F172A)),
              SizedBox(width: 4),
              Icon(Icons.wifi, size: 12, color: Color(0xFF0F172A)),
              SizedBox(width: 4),
              Icon(Icons.battery_full, size: 14, color: Color(0xFF0F172A)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _langButton('en', 'English'),
        const SizedBox(width: 6),
        _langButton('hi', 'हिंदी'),
        const SizedBox(width: 6),
        _langButton('gu', 'ગુજરાતી'),
      ],
    );
  }

  Widget _langButton(String code, String label) {
    final active = _selectedLang == code;
    return InkWell(
      onTap: () => setState(() => _selectedLang = code),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFEEF2FF),
            child: const Icon(Icons.storefront, color: Color(0xFF4F46E5), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.businessType,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Rate your experience below',
                  style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarRatingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final star = index + 1;
              final filled = star <= _selectedRating;
              return InkWell(
                onTap: () => setState(() => _selectedRating = star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 32,
                    color: filled ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedRating >= 4 ? '⭐️ Great experience!' : '⚠️ Private Feedback Mode',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _selectedRating >= 4 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChipsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'What did you like?',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              InkWell(
                onTap: _triggerAiGeneration,
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: _aiGenerating ? const Color(0xFF4F46E5) : const Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Magic AI Pick',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF7C3AED),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.categoryNames.isEmpty)
            Text(
              'No categories in this template.',
              style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.categoryNames.map((cat) {
                final selected = _selectedCategories.contains(cat);
                return InkWell(
                  onTap: () => _toggleCategory(cat),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? const Color(0xFF4F46E5) : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          const Icon(Icons.check_circle, size: 12, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          cat,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            color: selected ? const Color(0xFF4F46E5) : const Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildReviewTextBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Generated Review Preview',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
              Text(
                '${_reviewTextCtrl.text.split(' ').where((w) => w.isNotEmpty).length} words',
                style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _reviewTextCtrl,
            maxLines: 3,
            style: GoogleFonts.outfit(
              fontSize: 12,
              height: 1.4,
              color: const Color(0xFF1E293B),
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'Select tags above to build customer review text…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleMapsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _simulateCopy,
        style: ElevatedButton.styleFrom(
          backgroundColor: _copied ? const Color(0xFF10B981) : const Color(0xFF1A73E8),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_copied ? Icons.check_circle : Icons.copy, size: 16),
            const SizedBox(width: 8),
            Text(
              _copied ? 'Copied! Opens Google Maps…' : 'Copy & Open Google Maps',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowRatingSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 32),
          const SizedBox(height: 8),
          Text(
            'Private Feedback Routing',
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Reviews with 1-3 stars are gracefully routed to WhatsApp or private feedback, protecting Google Maps rating.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.chat, size: 14),
            label: const Text('Send to Owner on WhatsApp'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
