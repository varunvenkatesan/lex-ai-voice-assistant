import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-width rounded black button used on Login / Sign Up screens.
///
/// All visual properties (width, height, border radius, font size, colours)
/// are exposed as optional parameters with sensible defaults so the caller
/// can easily adjust them without touching internal code.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    // ── Customisable dimensions & styling ──
    this.width = double.infinity,
    this.height = 56.0,
    this.borderRadius = 16.0,
    this.fontSize = 16.0,
    this.fontWeight = FontWeight.w700,
    this.backgroundColor = Colors.black,
    this.foregroundColor = Colors.white,
    this.elevation = 2.0,
    this.shadowColor = Colors.black26,
    this.padding,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Button width. Defaults to `double.infinity` (full available width).
  final double width;

  /// Button height. Defaults to `56`.
  final double height;

  /// Corner radius. Defaults to `16`.
  final double borderRadius;

  /// Label font size. Defaults to `16`.
  final double fontSize;

  /// Label font weight. Defaults to `FontWeight.w700`.
  final FontWeight fontWeight;

  /// Button background colour. Defaults to `Colors.black`.
  final Color backgroundColor;

  /// Label text colour. Defaults to `Colors.white`.
  final Color foregroundColor;

  /// Button elevation. Defaults to `2`.
  final double elevation;

  /// Shadow colour. Defaults to `Colors.black26`.
  final Color shadowColor;

  /// Optional inner padding override.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: elevation,
          shadowColor: shadowColor,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
