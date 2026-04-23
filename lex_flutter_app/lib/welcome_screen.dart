import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Feature slide data
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureSlide {
  const _FeatureSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.accentColor,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Color accentColor;
}

const _slides = [
  _FeatureSlide(
    icon: Icons.mic_rounded,
    title: 'Real-Time',
    subtitle: 'Voice AI',
    description:
        'Have hands-free, natural\nconversations with Lex — your\nintelligent voice companion.',
    accentColor: Color(0xFF00E676),
  ),
  _FeatureSlide(
    icon: Icons.psychology_rounded,
    title: 'Personal',
    subtitle: 'Memory',
    description:
        'Lex remembers your preferences\nand sends smart reminders\ntailored just for you.',
    accentColor: Color(0xFFBB86FC),
  ),
  _FeatureSlide(
    icon: Icons.face_rounded,
    title: 'Anime',
    subtitle: 'Companion',
    description:
        'Interact with an expressive\nanime companion that reacts \nto your conversations.',
    accentColor: Color(0xFF40C4FF),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Welcome Screen
// ─────────────────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  int _currentSlide = 0;
  Timer? _autoSlideTimer;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;
  late final AnimationController _slideInController;

  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();

    // Fade animation for slide transitions
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.value = 1.0;

    // Glow pulse animation
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );

    // Initial slide-in animation
    _slideInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideInController.forward();

    // Auto-advance slides every 3.5 seconds
    _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      _advanceSlide();
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _fadeController.dispose();
    _glowController.dispose();
    _slideInController.dispose();
    super.dispose();
  }

  void _advanceSlide() {
    if (_isTransitioning) return;
    _isTransitioning = true;

    // Fade out current slide
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _currentSlide = (_currentSlide + 1) % _slides.length;
      });
      // Fade in new slide
      _fadeController.forward().then((_) {
        _isTransitioning = false;
      });
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final slide = _slides[_currentSlide];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background subtle gradient ──
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.6, -0.3),
                  radius: 1.2,
                  colors: [
                    slide.accentColor.withValues(alpha: 0.04),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          // ── Logo at top-left ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 25,
            left: 20,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'packages/flutter_plugin2/assets/UI image/lex_logo.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                Text(
                  'LEX',
                  style: GoogleFonts.manrope(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),

          // ── Welcome tagline ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 95,
            left: 22,
            right: size.width * 0.38,
            child: Text.rich(
              TextSpan(
                text: 'Welcome to ',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.50),
                  letterSpacing: 0.5,
                ),
                children: [
                  TextSpan(
                    text: 'LEX',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 1,
                    ),
                  ),
                  const TextSpan(text: ' — Your AI Personal Voice Assistant'),
                ],
              ),
            ),
          ),

          // ── Glassmorphism card on the left ──
          Positioned(
            left: 20,
            top: size.height * 0.22,
            width: size.width * 0.63,
            height: size.height * 0.48,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: slide.accentColor.withValues(
                          alpha: 0.08 + (_glowAnimation.value * 0.07),
                        ),
                        blurRadius: 30 + (_glowAnimation.value * 15),
                        spreadRadius: -5,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1.2,
                      ),
                    ),
                    padding: const EdgeInsets.all(28),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildSlideContent(slide),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Anime character on the right (top layer, overlaps card) ──
          Positioned(
            right: -21,
            top: size.height * 0.08,
            bottom: size.height * 0.21,
            child: Image.asset(
              'packages/flutter_plugin2/assets/UI image/start_character_image.png',
              fit: BoxFit.contain,
            ),
          ),

          // ── Bottom section: dots + buttons ──
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPad + 16,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.5),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _slideInController,
                curve: Curves.easeOutCubic,
              )),
              child: Column(
                children: [
                  // Pagination dots
                  _buildPaginationDots(slide.accentColor),
                  const SizedBox(height: 28),
                  // LOGIN button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) => const LoginScreen(),
                              transitionsBuilder: (_, animation, __, child) {
                                return FadeTransition(
                                    opacity: animation, child: child);
                              },
                              transitionDuration:
                                  const Duration(milliseconds: 400),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        child: const Text('LOGIN'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // SIGNUP button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) => const SignupScreen(),
                              transitionsBuilder: (_, animation, __, child) {
                                return FadeTransition(
                                    opacity: animation, child: child);
                              },
                              transitionDuration:
                                  const Duration(milliseconds: 400),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                            color: Colors.white54,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        child: const Text('SIGNUP'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Slide Content (inside glass card)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSlideContent(_FeatureSlide slide) {
    return Column(
      key: ValueKey(slide.title),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon with glow
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: slide.accentColor.withValues(alpha: 0.12),
            boxShadow: [
              BoxShadow(
                color: slide.accentColor.withValues(alpha: 0.25),
                blurRadius: 20,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Icon(
            slide.icon,
            color: slide.accentColor,
            size: 28,
          ),
        ),
        const SizedBox(height: 28),
        // Title
        Text(
          slide.title,
          style: GoogleFonts.manrope(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        // Subtitle with accent
        Text(
          slide.subtitle,
          style: GoogleFonts.manrope(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: slide.accentColor.withValues(alpha: 0.9),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 20),
        // Description
        Text(
          slide.description,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.55),
            height: 1.6,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        // Decorative accent line
        Container(
          width: 40,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: [
                slide.accentColor.withValues(alpha: 0.7),
                slide.accentColor.withValues(alpha: 0.1),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pagination Dots
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPaginationDots(Color activeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_slides.length, (index) {
        final isActive = index == _currentSlide;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive ? activeColor : Colors.white.withValues(alpha: 0.2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: -1,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
