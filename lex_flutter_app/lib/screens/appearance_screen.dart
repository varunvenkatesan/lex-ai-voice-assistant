import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Appearance Screen — theme selector
// ─────────────────────────────────────────────────────────────────────────────

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  static const _key = 'theme_mode';
  String _selected = 'system'; // 'light', 'dark', 'system'

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selected = prefs.getString(_key) ?? 'system';
    });
  }

  Future<void> _setTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode);
    setState(() => _selected = mode);

    // Notify the app to rebuild with the new theme
    if (!mounted) return;
    final messenger = _ThemeChangeNotification(mode);
    messenger.dispatch(context);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Column(
        children: [
          SizedBox(height: topPad),
          _buildTopBar(context),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                _buildOption('System (Default)', 'system',
                    Icons.settings_suggest_rounded),
                const SizedBox(height: 6),
                _buildOption('Light Mode', 'light', Icons.light_mode_rounded),
                const SizedBox(height: 6),
                _buildOption('Dark Mode', 'dark', Icons.dark_mode_rounded),
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
                'Appearance',
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

  Widget _buildOption(String label, String value, IconData icon) {
    final isActive = _selected == value;
    return Material(
      color: isActive
          ? const Color(0xFF7C4DFF).withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _setTheme(value),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon,
                  color: isActive
                      ? const Color(0xFF7C4DFF)
                      : Colors.white.withValues(alpha: 0.6),
                  size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.8),
                    fontSize: 15,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (isActive)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF7C4DFF), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification that propagates up the tree to trigger theme changes.
class _ThemeChangeNotification extends Notification {
  _ThemeChangeNotification(this.mode);
  final String mode;
}
