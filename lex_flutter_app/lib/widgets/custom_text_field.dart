import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reusable text field with label, rounded border, and optional
/// password-visibility toggle.
///
/// All visual properties (width, height, border radius, font sizes, padding)
/// are exposed as optional parameters with sensible defaults so the caller
/// can easily adjust them without touching internal code.
class CustomTextField extends StatefulWidget {
  const CustomTextField({
    super.key,
    required this.label,
    this.hintText,
    this.isPassword = false,
    this.controller,
    this.keyboardType,
    // ── Customisable dimensions & styling ──
    this.width,
    this.height,
    this.borderRadius = 14.0,
    this.labelFontSize = 14.0,
    this.inputFontSize = 15.0,
    this.hintFontSize = 15.0,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.fillColor,
    this.borderColor,
    this.focusBorderColor,
    this.labelColor,
    this.inputColor,
    this.hintColor,
  });

  final String label;
  final String? hintText;
  final bool isPassword;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  /// Fixed width for the field. `null` = fills available space.
  final double? width;

  /// Fixed height for the input area (excludes the label).
  final double? height;

  /// Border radius of the input box.
  final double borderRadius;

  /// Font size for the label above the input.
  final double labelFontSize;

  /// Font size for the typed text inside the input.
  final double inputFontSize;

  /// Font size for the hint text.
  final double hintFontSize;

  /// Inner padding of the input area.
  final EdgeInsetsGeometry contentPadding;

  /// Background fill colour of the input area.
  final Color? fillColor;

  /// Border colour when enabled (idle).
  final Color? borderColor;

  /// Border colour when focused.
  final Color? focusBorderColor;

  /// Colour of the label text.
  final Color? labelColor;

  /// Colour of typed text.
  final Color? inputColor;

  /// Colour of hint text.
  final Color? hintColor;

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final effectiveFillColor = widget.fillColor ?? Colors.grey.shade50;
    final effectiveBorderColor = widget.borderColor ?? Colors.grey.shade200;
    final effectiveFocusBorderColor = widget.focusBorderColor ?? Colors.black54;
    final effectiveLabelColor = widget.labelColor ?? Colors.black87;
    final effectiveInputColor = widget.inputColor ?? Colors.black87;
    final effectiveHintColor = widget.hintColor ?? Colors.grey.shade400;

    Widget field = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: GoogleFonts.manrope(
            fontSize: widget.labelFontSize,
            fontWeight: FontWeight.w600,
            color: effectiveLabelColor,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: TextFormField(
            controller: widget.controller,
            obscureText: widget.isPassword && _obscured,
            keyboardType: widget.keyboardType,
            style: GoogleFonts.manrope(
              fontSize: widget.inputFontSize,
              color: effectiveInputColor,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: GoogleFonts.manrope(
                fontSize: widget.hintFontSize,
                color: effectiveHintColor,
              ),
              filled: true,
              fillColor: effectiveFillColor,
              contentPadding: widget.contentPadding,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                borderSide: BorderSide(color: effectiveBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                borderSide: BorderSide(color: effectiveBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                borderSide:
                    BorderSide(color: effectiveFocusBorderColor, width: 1.5),
              ),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: effectiveHintColor,
                        size: 22,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );

    // Wrap in a SizedBox when an explicit width is provided.
    if (widget.width != null) {
      field = SizedBox(width: widget.width, child: field);
    }

    return field;
  }
}
