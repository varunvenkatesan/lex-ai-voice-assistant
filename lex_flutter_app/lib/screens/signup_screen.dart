import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/supabase_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sign Up Screen – Easy-to-customise layout constants
// ─────────────────────────────────────────────────────────────────────────────

/// ── Screen-level layout ──
const double kSignupHeaderRatio = 0.20; // Header height as % of screen
const double kSignupFormContainerRadiusTL = 60.0; // Top-left corner
const double kSignupFormContainerRadiusTR = 0.0; // Top-right corner
const Color kSignupFormContainerColor = Color(0xFFF5F5F7);
const EdgeInsets kSignupFormPadding =
    EdgeInsets.symmetric(horizontal: 28, vertical: 32);

/// ── Logo ──
const double kSignupLogoSize = 60.0;
const double kSignupLogoRadius = 14.0;
const double kSignupLogoTextSize = 24.0;
const double kSignupLogoTextSpacing = 2.0;

/// ── Character image ──
const double kSignupCharacterHeightRatio = 0.92; // % of header
const double kSignupCharacterBottomOffset = -150.0;

/// ── Title ──
const double kSignupTitleFontSize = 28.0;
const FontWeight kSignupTitleFontWeight = FontWeight.w800;

/// ── Input fields ──
const double kSignupFieldSpacing = 18.0;

/// ── Button ──
const double kSignupButtonHeight = 56.0;
const double kSignupButtonRadius = 16.0;
const double kSignupButtonFontSize = 16.0;

/// ── Footer text ──
const double kSignupFooterFontSize = 14.0;

// ─────────────────────────────────────────────────────────────────────────────
// Sign Up Screen
// ─────────────────────────────────────────────────────────────────────────────

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (fullName.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showSnackbar('Please fill in all fields', isError: true);
      return;
    }
    if (password.length < 8) {
      _showSnackbar('Password must be at least 8 characters', isError: true);
      return;
    }
    if (password != confirmPassword) {
      _showSnackbar('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await SupabaseService.signUp(
        fullName: fullName,
        email: email,
        password: password,
      );

      if (!mounted) return;
      _showSnackbar('Account created! Please log in.');

      // Navigate to login screen
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _goToLogin();
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackbar(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFE53935) : const Color(0xFF43A047),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final size = MediaQuery.of(context).size;

    final headerHeight = size.height * kSignupHeaderRatio;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Layer 1: Header background + form container (Column) ──
          Column(
            children: [
              // Black header area (just the background space)
              SizedBox(
                height: headerHeight,
                width: double.infinity,
              ),

              // White / light-grey form container
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: kSignupFormContainerColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(kSignupFormContainerRadiusTL),
                      topRight: Radius.circular(kSignupFormContainerRadiusTR),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: kSignupFormPadding,
                    child: _buildForm(),
                  ),
                ),
              ),
            ],
          ),

          // ── Layer 2: Logo ──
          Positioned(
            top: topPadding + 20,
            left: 20,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(kSignupLogoRadius),
                  child: Image.asset(
                    'packages/flutter_plugin2/assets/UI image/lex_logo.png',
                    width: kSignupLogoSize,
                    height: kSignupLogoSize,
                    fit: BoxFit.cover,
                  ),
                ),
                //const SizedBox(width: 10),
                Text(
                  'LEX',
                  style: GoogleFonts.manrope(
                    fontSize: kSignupLogoTextSize,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: kSignupLogoTextSpacing,
                  ),
                ),
              ],
            ),
          ),

          // ── Layer 3 (TOP): Character image — overlaps form container ──
          Positioned(
            top: headerHeight +
                kSignupCharacterBottomOffset -
                (headerHeight * kSignupCharacterHeightRatio) +
                headerHeight,
            left: 110,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Image.asset(
                  'packages/flutter_plugin2/assets/UI image/login_character.png',
                  height: headerHeight * kSignupCharacterHeightRatio,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Form
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          'Sign Up',
          style: GoogleFonts.manrope(
            fontSize: kSignupTitleFontSize,
            fontWeight: kSignupTitleFontWeight,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 24),

        // Full name
        CustomTextField(
          label: 'Full name',
          hintText: 'Leo Dass',
          controller: _fullNameController,
        ),
        SizedBox(height: kSignupFieldSpacing),

        // Email
        CustomTextField(
          label: 'Email',
          hintText: 'example@gmail.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: kSignupFieldSpacing),

        // Password
        CustomTextField(
          label: 'Password',
          hintText: 'Min. 8 characters',
          isPassword: true,
          controller: _passwordController,
        ),
        SizedBox(height: kSignupFieldSpacing),

        // Confirm password
        CustomTextField(
          label: 'Confirm password',
          hintText: 'Repeat your password',
          isPassword: true,
          controller: _confirmPasswordController,
        ),
        const SizedBox(height: 28),

        // Create Account button
        PrimaryButton(
          label: _isLoading ? 'Creating...' : 'Create Account',
          height: kSignupButtonHeight,
          borderRadius: kSignupButtonRadius,
          fontSize: kSignupButtonFontSize,
          onPressed: _isLoading ? null : _handleSignUp,
        ),
        const SizedBox(height: 24),

        // OR divider
        _buildOrDivider(),
        const SizedBox(height: 24),

        // Footer — Sign In link
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Already have an account? ',
                style: GoogleFonts.manrope(
                  fontSize: kSignupFooterFontSize,
                  color: Colors.grey.shade600,
                ),
              ),
              GestureDetector(
                onTap: _goToLogin,
                child: Text(
                  'Sign In',
                  style: GoogleFonts.manrope(
                    fontSize: kSignupFooterFontSize,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OR divider
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade400,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
      ],
    );
  }
}
