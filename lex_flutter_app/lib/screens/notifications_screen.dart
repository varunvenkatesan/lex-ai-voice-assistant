import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/reminder_models.dart';
import '../services/reminder_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  ReminderNotificationPreferences _preferences =
      const ReminderNotificationPreferences.defaults();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences =
        await ReminderService.instance.loadNotificationPreferences();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _isLoading = false;
    });
  }

  Future<void> _updatePreferences(
    ReminderNotificationPreferences preferences,
  ) async {
    setState(() {
      _preferences = preferences;
    });
    await ReminderService.instance.saveNotificationPreferences(preferences);
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
          Expanded(
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white24,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      const SizedBox(height: 24),
                      _buildInfoCard(),
                      const SizedBox(height: 22),
                      _buildSectionLabel('REMINDER DELIVERY'),
                      const SizedBox(height: 12),
                      _buildToggle(
                        icon: Icons.record_voice_over_rounded,
                        label: 'Popup with voice notification',
                        subtitle:
                            'Show the reminder popup and let Lex speak the reminder aloud.',
                        value: _preferences.popupWithVoice,
                        onChanged: (value) {
                          _updatePreferences(
                            _preferences.copyWith(popupWithVoice: value),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildToggle(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Popup with text notification',
                        subtitle:
                            'Show the reminder popup with the reminder text only.',
                        value: _preferences.popupWithText,
                        onChanged: (value) {
                          _updatePreferences(
                            _preferences.copyWith(popupWithText: value),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'High-priority Android reminder notifications still fire at the scheduled time even if the app is in the background. These switches control how the in-app Lex popup behaves when the reminder is delivered.',
                        style: GoogleFonts.manrope(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 36),
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
                'Notifications',
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF8BD8FF).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.alarm_rounded,
              color: Color(0xFF8BD8FF),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reminder alarms',
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reminders created from Talk or Chat are stored in Supabase, listed in the sidebar, and delivered through a high-priority reminder flow.',
                  style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.46),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildToggle({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.74), size: 22),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF7C4DFF),
            thumbColor: WidgetStateProperty.all(Colors.white),
            inactiveThumbColor: Colors.white.withValues(alpha: 0.3),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }
}
