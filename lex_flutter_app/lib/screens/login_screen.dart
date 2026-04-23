import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/supabase_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import 'signup_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Login Screen – Easy-to-customise layout constants
// ─────────────────────────────────────────────────────────────────────────────

/// ── Screen-level layout ──
const double kLoginHeaderRatio = 0.28; // Header height as % of screen
const double kLoginFormContainerRadiusTL = 60.0; // Top-left corner
const double kLoginFormContainerRadiusTR = 0.0; // Top-right corner
const Color kLoginFormContainerColor = Color(0xFFF5F5F7);
const EdgeInsets kLoginFormPadding =
    EdgeInsets.symmetric(horizontal: 28, vertical: 32);

/// ── Logo ──
const double kLoginLogoSize = 60.0;
const double kLoginLogoRadius = 14.0;
const double kLoginLogoTextSize = 24.0;
const double kLoginLogoTextSpacing = 2.0;

/// ── Character image ──
const double kLoginCharacterHeightRatio = 0.92; // % of header
const double kLoginCharacterBottomOffset = -210.0;

/// ── Title ──
const double kLoginTitleFontSize = 28.0;
const FontWeight kLoginTitleFontWeight = FontWeight.w800;

/// ── Input fields ──
const double kLoginFieldSpacing = 20.0;

/// ── Button ──
const double kLoginButtonHeight = 56.0;
const double kLoginButtonRadius = 16.0;
const double kLoginButtonFontSize = 16.0;

/// ── Footer text ──
const double kLoginFooterFontSize = 14.0;

// ─────────────────────────────────────────────────────────────────────────────
// Login Screen
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackbar('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await SupabaseService.signIn(email: email, password: password);
      final fullName = await SupabaseService.currentUserFullName();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LexHomePage(userName: fullName),
        ),
        (route) => false,
      );
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

  void _goToSignUp() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const SignupScreen(),
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

    final headerHeight = size.height * kLoginHeaderRatio;

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
                    color: kLoginFormContainerColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(kLoginFormContainerRadiusTL),
                      topRight: Radius.circular(kLoginFormContainerRadiusTR),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: kLoginFormPadding,
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
                  borderRadius: BorderRadius.circular(kLoginLogoRadius),
                  child: Image.asset(
                    'packages/flutter_plugin2/assets/UI image/lex_logo.png',
                    width: kLoginLogoSize,
                    height: kLoginLogoSize,
                    fit: BoxFit.cover,
                  ),
                ),
                //const SizedBox(width: 10),
                Text(
                  'LEX',
                  style: GoogleFonts.manrope(
                    fontSize: kLoginLogoTextSize,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: kLoginLogoTextSpacing,
                  ),
                ),
              ],
            ),
          ),

          // ── Layer 3 (TOP): Character image — overlaps form container ──
          Positioned(
            top: headerHeight +
                kLoginCharacterBottomOffset -
                (headerHeight * kLoginCharacterHeightRatio) +
                headerHeight,
            left: 100,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Image.asset(
                  'packages/flutter_plugin2/assets/UI image/login_character.png',
                  height: headerHeight * kLoginCharacterHeightRatio,
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
          'Login',
          style: GoogleFonts.manrope(
            fontSize: kLoginTitleFontSize,
            fontWeight: kLoginTitleFontWeight,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 28),

        // Email
        CustomTextField(
          label: 'Email',
          hintText: 'example@gmail.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: kLoginFieldSpacing),

        // Password
        CustomTextField(
          label: 'Password',
          hintText: 'Enter your password',
          isPassword: true,
          controller: _passwordController,
        ),
        const SizedBox(height: 8),

        // Forgot password
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              // TODO: Implement forgot password
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Forgot password?',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Login button
        PrimaryButton(
          label: _isLoading ? 'Logging in...' : 'Login  →',
          height: kLoginButtonHeight,
          borderRadius: kLoginButtonRadius,
          fontSize: kLoginButtonFontSize,
          onPressed: _isLoading ? null : _handleLogin,
        ),
        const SizedBox(height: 24),

        // OR divider
        _buildOrDivider(),
        const SizedBox(height: 24),

        // Footer — Sign Up link
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Don't have an account? ",
                style: GoogleFonts.manrope(
                  fontSize: kLoginFooterFontSize,
                  color: Colors.grey.shade600,
                ),
              ),
              GestureDetector(
                onTap: _goToSignUp,
                child: Text(
                  'Sign Up',
                  style: GoogleFonts.manrope(
                    fontSize: kLoginFooterFontSize,
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
