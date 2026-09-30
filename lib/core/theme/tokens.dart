// Generated from brand/tokens.json by tool/gen_tokens.dart.
// Do not edit by hand. Rerun the tool when the brand changes.

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

abstract final class OrionColors {
  static const bgPrimary = Color(0xFF09090B);
  static const bgSecondary = Color(0xFF0F0F12);
  static const bgCard = Color(0xFF111115);
  static const bgCardElevated = Color(0xFF16161C);
  static const bgHighlight = Color(0xFF1A2535);
  static const textWhite = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFF71717A);
  static const textFaint = Color(0xFF3F3F46);
  static const textCyan = Color(0xFFA8CCD8);
  static const textCyanSoft = Color(0xFF7CB8CE);
  static const borderSubtle = Color.fromRGBO(255, 255, 255, 0.06);
  static const borderSoft = Color.fromRGBO(255, 255, 255, 0.10);
  static const borderCyan = Color.fromRGBO(160, 210, 230, 0.20);
  static const accent = Color(0xFFA8CCD8);
  static const accentGlow = Color.fromRGBO(160, 210, 230, 1);
}

/// Alpha steps for the accent. It is light, not paint.
abstract final class OrionAlpha {
  static const double wash = 0.03;
  static const double ambient = 0.05;
  static const double fill = 0.1;
  static const double border = 0.2;
  static const double borderHover = 0.4;
  static const double glow = 0.5;
}

abstract final class OrionFonts {
  static const serif = 'Playfair Display';
  static const body = 'Source Serif 4';
  static const sans = 'Inter';
  static const mono = 'DM Mono';
  static const display = serif;
  static const document = body;
  static const ui = sans;
  static const machine = mono;
}

/// Fixed sizes in logical pixels. Fluid sizes ship as min and max.
abstract final class OrionFontSize {
  static const double monumentalMin = 120;
  static const double monumentalMax = 360;
  static const double heroMin = 32;
  static const double heroMax = 58;
  static const double sectionMin = 28;
  static const double sectionMax = 44;
  static const double cardTitle = 24;
  static const double leadMin = 14;
  static const double leadMax = 16;
  static const double body = 15;
  static const double ui = 14;
  static const double uiSmall = 12;
  static const double label = 10;
  static const double micro = 8;
}

abstract final class OrionFontWeight {
  static const light = FontWeight.w300;
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
}

abstract final class OrionLineHeight {
  static const double monumental = 0.9;
  static const double display = 1.08;
  static const double title = 1.2;
  static const double body = 1.65;
  static const double article = 1.75;
}

/// Tracking in em. Multiply by the font size for letterSpacing.
abstract final class OrionTracking {
  static const double monumental = -0.05;
  static const double display = -0.025;
  static const double tight = -0.02;
  static const double ui = 0.02;
  static const double label = 0.15;
  static const double eyebrow = 0.18;
  static const double micro = 0.22;
  static const double microWide = 0.28;
}

/// Spacing scale. The sN names mirror tokens.json, the rest are roles.
abstract final class Space {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s15 = 60;
  static const double s20 = 80;
  static const double s25 = 100;
  static const double s30 = 120;
  static const double xxs = s1;
  static const double xs = s2;
  static const double sm = s3;
  static const double md = s4;
  static const double lg = s6;
  static const double xl = s8;
  static const double xxl = s10;
}

abstract final class OrionContainer {
  static const double wide = 1400;
  static const double hero = 1360;
  static const double standard = 1200;
  static const double narrow = 968;
  static const double article = 800;
  static const double measure = 600;
  static const double form = 440;
}

abstract final class OrionBreakpoint {
  static const double lg = 968;
  static const double md = 768;
  static const double sm = 640;
}

abstract final class OrionRadius {
  static const double xs = 2;
  static const double sm = 8;
  static const double btn = 10;
  static const double card = 12;
  static const double lg = 14;
  static const double full = 9999;
}

abstract final class OrionMotion {
  static const easeBrand = Cubic(0.16, 1, 0.3, 1);
  static const easeUi = Cubic(0.22, 1, 0.36, 1);
  static const fast = Duration(milliseconds: 200);
  static const hover = Duration(milliseconds: 300);
  static const med = Duration(milliseconds: 400);
  static const keyframe = Duration(milliseconds: 700);
  static const reveal = Duration(milliseconds: 1400);
  static const fade = Duration(milliseconds: 1800);
  static const pulse = Duration(milliseconds: 2500);
  static const stagger = Duration(milliseconds: 100);
}

abstract final class OrionShadow {
  static const glowSm = BoxShadow(
    color: Color.fromRGBO(168, 204, 216, 0.5),
    blurRadius: 8,
  );
  static const glowMd = BoxShadow(
    color: Color.fromRGBO(168, 204, 216, 0.8),
    blurRadius: 16,
  );
  static const glowHover = BoxShadow(
    color: Color.fromRGBO(168, 204, 216, 0.1),
    blurRadius: 24,
  );
}

abstract final class OrionZ {
  static const int ambient = 0;
  static const int content = 1;
  static const int raised = 5;
  static const int nav = 50;
  static const int modal = 100;
}
