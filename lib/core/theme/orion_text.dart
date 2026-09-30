import 'package:flutter/material.dart';

import 'tokens.dart';

/// Text styles named after brand/typography.md roles, never after sizes.
/// Mono roles expect uppercase input; MonoLabel does that for you.
class OrionText extends ThemeExtension<OrionText> {
  const OrionText({
    required this.display,
    required this.headline,
    required this.title,
    required this.metric,
    required this.lead,
    required this.body,
    required this.bodySmall,
    required this.ui,
    required this.button,
    required this.uiSmall,
    required this.label,
    required this.eyebrow,
    required this.micro,
    required this.mono,
  });

  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle metric;
  final TextStyle lead;
  final TextStyle body;
  final TextStyle bodySmall;
  final TextStyle ui;
  final TextStyle button;
  final TextStyle uiSmall;
  final TextStyle label;
  final TextStyle eyebrow;
  final TextStyle micro;
  final TextStyle mono;

  static const standard = OrionText(
    display: TextStyle(
      fontFamily: OrionFonts.serif,
      fontSize: 40,
      fontWeight: OrionFontWeight.medium,
      height: OrionLineHeight.display,
      letterSpacing: 40 * OrionTracking.display,
      color: OrionColors.textWhite,
    ),
    headline: TextStyle(
      fontFamily: OrionFonts.serif,
      fontSize: OrionFontSize.sectionMin,
      fontWeight: OrionFontWeight.medium,
      height: 1.1,
      letterSpacing: OrionFontSize.sectionMin * OrionTracking.tight,
      color: OrionColors.textWhite,
    ),
    title: TextStyle(
      fontFamily: OrionFonts.serif,
      fontSize: OrionFontSize.cardTitle,
      fontWeight: OrionFontWeight.medium,
      height: OrionLineHeight.title,
      letterSpacing: OrionFontSize.cardTitle * OrionTracking.tight,
      color: OrionColors.textWhite,
    ),
    metric: TextStyle(
      fontFamily: OrionFonts.serif,
      fontSize: OrionFontSize.heroMin,
      fontWeight: OrionFontWeight.regular,
      height: 1,
      letterSpacing: OrionFontSize.heroMin * OrionTracking.tight,
      color: OrionColors.textWhite,
    ),
    lead: TextStyle(
      fontFamily: OrionFonts.body,
      fontSize: OrionFontSize.leadMax,
      fontWeight: OrionFontWeight.regular,
      height: 1.7,
      color: OrionColors.textMuted,
    ),
    body: TextStyle(
      fontFamily: OrionFonts.body,
      fontSize: OrionFontSize.body,
      fontWeight: OrionFontWeight.regular,
      height: OrionLineHeight.body,
      color: OrionColors.textMuted,
    ),
    bodySmall: TextStyle(
      fontFamily: OrionFonts.body,
      fontSize: 13,
      fontWeight: OrionFontWeight.regular,
      height: 1.6,
      color: OrionColors.textMuted,
    ),
    ui: TextStyle(
      fontFamily: OrionFonts.sans,
      fontSize: OrionFontSize.ui,
      fontWeight: OrionFontWeight.regular,
      height: 1.4,
      letterSpacing: OrionFontSize.ui * OrionTracking.ui,
      color: OrionColors.textWhite,
    ),
    button: TextStyle(
      fontFamily: OrionFonts.sans,
      fontSize: OrionFontSize.ui,
      fontWeight: OrionFontWeight.medium,
      height: 1.2,
      letterSpacing: OrionFontSize.ui * OrionTracking.ui,
      color: OrionColors.textWhite,
    ),
    uiSmall: TextStyle(
      fontFamily: OrionFonts.sans,
      fontSize: OrionFontSize.uiSmall,
      fontWeight: OrionFontWeight.regular,
      height: 1.4,
      color: OrionColors.textMuted,
    ),
    label: TextStyle(
      fontFamily: OrionFonts.mono,
      fontSize: OrionFontSize.label,
      fontWeight: OrionFontWeight.regular,
      height: 1.4,
      letterSpacing: OrionFontSize.label * OrionTracking.label,
      color: OrionColors.textFaint,
    ),
    eyebrow: TextStyle(
      fontFamily: OrionFonts.mono,
      fontSize: OrionFontSize.label,
      fontWeight: OrionFontWeight.regular,
      height: 1.4,
      letterSpacing: OrionFontSize.label * OrionTracking.eyebrow,
      color: OrionColors.textCyanSoft,
    ),
    micro: TextStyle(
      fontFamily: OrionFonts.mono,
      fontSize: OrionFontSize.micro,
      fontWeight: OrionFontWeight.regular,
      height: 1.4,
      letterSpacing: OrionFontSize.micro * OrionTracking.micro,
      color: OrionColors.textFaint,
    ),
    mono: TextStyle(
      fontFamily: OrionFonts.mono,
      fontSize: OrionFontSize.uiSmall,
      fontWeight: OrionFontWeight.light,
      height: 1.5,
      color: OrionColors.textCyanSoft,
    ),
  );

  @override
  OrionText copyWith() => this;

  @override
  OrionText lerp(OrionText? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
