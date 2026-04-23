import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/supabase_service.dart';
import 'appearance_screen.dart';
import 'about_screen.dart';
import 'personalization_screen.dart';
import 'general_screen.dart';
import 'notifications_screen.dart';
import '../welcome_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Settings Screen — full-page settings & profile
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.userName,
    required this.userEmail,
    this.onBack,
  });

  final String userName;
  final String userEmail;
  /// Optional callback for back navigation. When provided, the back button
  /// calls this instead of [Navigator.pop]. This enables state-based
  /// rendering from the Home screen, avoiding route compositing issues
  /// with native PlatformViews.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      // Pure black background as a fallback — ensures no transparency
      // bleed-through from the underlying Home screen during transitions.
      backgroundColor: Colors.black,
      body: Container(
        color: const Color(0xFF111111),
        child: Column(
          children: [
            SizedBox(height: topPad),

            // ── Top bar ──
            _buildTopBar(context),

            // ── Scrollable content ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 20),

                  // ── Profile card ──
                  _buildProfileCard(context),
                  const SizedBox(height: 28),

                  // ── MY CHATGPT section ──
                  _buildSectionLabel('MY CHATGPT'),
                  const SizedBox(height: 8),
                  _buildMenuItem(
                    context,
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Personalization',
                    onTap: () =>
                        _pushScreen(context, const PersonalizationScreen()),
                  ),
                  const SizedBox(height: 24),

                  // ── ACCOUNT section ──
                  _buildSectionLabel('ACCOUNT'),
                  const SizedBox(height: 8),
                  _buildMenuItem(
                    context,
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    subtitle: userEmail,
                    onTap: () {},
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context,
                    icon: Icons.brightness_6_rounded,
                    label: 'Appearance',
                    subtitle: 'System (Default)',
                    onTap: () => _pushScreen(context, const AppearanceScreen()),
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context,
                    icon: Icons.settings_rounded,
                    label: 'General',
                    onTap: () => _pushScreen(context, const GeneralScreen()),
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context,
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifications',
                    onTap: () =>
                        _pushScreen(context, const NotificationsScreen()),
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context,
                    icon: Icons.info_outline_rounded,
                    label: 'About',
                    onTap: () => _pushScreen(context, const AboutScreen()),
                  ),
                  const SizedBox(height: 32),

                  // ── Log out ──
                  _buildLogoutButton(context),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Top bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () {
              if (onBack != null) {
                onBack!();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                'Settings',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // balance the back button
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Profile card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProfileCard(BuildContext context) {
    return Column(
      children: [
        // Avatar
        CircleAvatar(
          radius: 40,
          backgroundColor: const Color(0xFF7C4DFF),
          child: Text(
            _getInitials(userName),
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Name
        Text(
          userName.split(' ').first.toUpperCase(),
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),

        // Email
        Text(
          userEmail,
          style: GoogleFonts.manrope(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),

        // Edit profile button
        OutlinedButton(
          onPressed: () {
            // TODO: Edit profile screen
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          ),
          child: Text(
            'Edit profile',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section label
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Menu item
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMenuItem(
    BuildContext context, {
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
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.25),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Log out
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLogoutButton(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () async {
          await SupabaseService.signOut();
          if (!context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: Colors.red.shade300, size: 20),
              const SizedBox(width: 8),
              Text(
                'Log out',
                style: GoogleFonts.manrope(
                  color: Colors.red.shade300,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _pushScreen(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
