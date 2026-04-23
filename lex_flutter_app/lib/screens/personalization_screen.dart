import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Personalization Screen — AI personality settings
// ─────────────────────────────────────────────────────────────────────────────

class PersonalizationScreen extends StatefulWidget {
  const PersonalizationScreen({super.key});

  @override
  State<PersonalizationScreen> createState() => _PersonalizationScreenState();
}

class _PersonalizationScreenState extends State<PersonalizationScreen> {
  String _tone = 'Friendly';
  String _responseStyle = 'Balanced';
  String _companion = 'Female';

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Column(
        children: [
          SizedBox(height: topPad),
          _buildTopBar(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const SizedBox(height: 24),
                _buildSectionLabel('ASSISTANT TONE'),
                const SizedBox(height: 10),
                _buildChoiceGroup(
                  ['Friendly', 'Professional', 'Casual', 'Motivational'],
                  _tone,
                  (v) => setState(() => _tone = v),
                ),
                const SizedBox(height: 28),
                _buildSectionLabel('RESPONSE STYLE'),
                const SizedBox(height: 10),
                _buildChoiceGroup(
                  ['Concise', 'Balanced', 'Detailed'],
                  _responseStyle,
                  (v) => setState(() => _responseStyle = v),
                ),
                const SizedBox(height: 28),
                _buildSectionLabel('DEFAULT COMPANION'),
                const SizedBox(height: 10),
                _buildChoiceGroup(
                  ['Female', 'Male'],
                  _companion,
                  (v) => setState(() => _companion = v),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Personalization',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: GoogleFonts.manrope(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildChoiceGroup(
      List<String> options, String selected, ValueChanged<String> onSelect) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isActive = option == selected;
        return GestureDetector(
          onTap: () => onSelect(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF7C4DFF).withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF7C4DFF)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              option,
              style: GoogleFonts.manrope(
                color: isActive
                    ? const Color(0xFFBB86FC)
                    : Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
