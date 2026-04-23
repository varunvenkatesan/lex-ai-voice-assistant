import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// General Settings Screen
// ─────────────────────────────────────────────────────────────────────────────

class GeneralScreen extends StatefulWidget {
  const GeneralScreen({super.key});

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  String _language = 'English';

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
                _buildMenuItem(
                  icon: Icons.language_rounded,
                  label: 'Language',
                  subtitle: _language,
                  onTap: () => _showLanguagePicker(),
                ),
                const SizedBox(height: 6),
                _buildMenuItem(
                  icon: Icons.data_usage_rounded,
                  label: 'Data Usage',
                  subtitle: 'Manage data preferences',
                  onTap: () {},
                ),
                const SizedBox(height: 6),
                _buildMenuItem(
                  icon: Icons.storage_rounded,
                  label: 'Storage Management',
                  subtitle: 'Clear cache and data',
                  onTap: () {},
                ),
                const SizedBox(height: 6),
                _buildMenuItem(
                  icon: Icons.restore_rounded,
                  label: 'Reset Preferences',
                  subtitle: 'Restore default settings',
                  onTap: () => _showResetDialog(),
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
                'General',
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

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.manrope(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.25), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    final languages = ['English', 'Tamil', 'Hindi', 'Spanish', 'French'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: languages.map((lang) {
              final isActive = lang == _language;
              return ListTile(
                title: Text(
                  lang,
                  style: GoogleFonts.manrope(
                    color: isActive ? const Color(0xFF7C4DFF) : Colors.white,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isActive
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF7C4DFF), size: 20)
                    : null,
                onTap: () {
                  setState(() => _language = lang);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'Reset Preferences?',
          style: GoogleFonts.manrope(color: Colors.white),
        ),
        content: Text(
          'This will restore all settings to their defaults.',
          style:
              GoogleFonts.manrope(color: Colors.white.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Preferences reset')),
              );
            },
            child: Text('Reset',
                style: GoogleFonts.manrope(color: Colors.red.shade300)),
          ),
        ],
      ),
    );
  }
}
