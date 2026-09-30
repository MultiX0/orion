import 'package:flutter/material.dart';

import 'orion_text.dart';
import 'tokens.dart';

/// The one ThemeData. Dark only, the brand never designed a light theme.
/// Screens never set a color literal; they read this or OrionText.
ThemeData buildOrionTheme() {
  const scheme = ColorScheme.dark(
    primary: OrionColors.textCyan,
    onPrimary: OrionColors.bgPrimary,
    secondary: OrionColors.textCyanSoft,
    onSecondary: OrionColors.bgPrimary,
    surface: OrionColors.bgPrimary,
    onSurface: OrionColors.textWhite,
    surfaceContainerLow: OrionColors.bgSecondary,
    surfaceContainer: OrionColors.bgCard,
    surfaceContainerHigh: OrionColors.bgCardElevated,
    surfaceContainerHighest: OrionColors.bgHighlight,
    onSurfaceVariant: OrionColors.textMuted,
    outline: OrionColors.borderSoft,
    outlineVariant: OrionColors.borderSubtle,
    // The brand has no status hue. Errors read as white on the neutral ramp.
    error: OrionColors.textWhite,
    onError: OrionColors.bgPrimary,
  );
  const text = OrionText.standard;
  const accentSelection = Color.fromRGBO(168, 204, 216, OrionAlpha.border);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: OrionColors.bgPrimary,
    canvasColor: OrionColors.bgPrimary,
    fontFamily: OrionFonts.sans,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    extensions: const [text],
    textTheme: TextTheme(
      displayLarge: text.display,
      displayMedium: text.headline,
      headlineLarge: text.headline,
      headlineMedium: text.title,
      titleLarge: text.title,
      titleMedium: text.ui,
      bodyLarge: text.lead,
      bodyMedium: text.body,
      bodySmall: text.bodySmall,
      labelLarge: text.button,
      labelMedium: text.uiSmall,
      labelSmall: text.label,
    ),
    iconTheme: const IconThemeData(color: OrionColors.textMuted, size: 20),
    dividerTheme: const DividerThemeData(
      color: OrionColors.borderSubtle,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: OrionColors.textCyan,
      selectionColor: accentSelection,
      selectionHandleColor: OrionColors.textCyan,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OrionColors.bgCard,
      hintStyle: text.ui.copyWith(color: OrionColors.textFaint),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      border: _inputBorder(OrionColors.borderSubtle),
      enabledBorder: _inputBorder(OrionColors.borderSubtle),
      focusedBorder: _inputBorder(OrionColors.borderCyan),
      errorBorder: _inputBorder(OrionColors.borderSoft),
      focusedErrorBorder: _inputBorder(OrionColors.borderCyan),
      errorStyle: text.uiSmall,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(3),
      radius: const Radius.circular(OrionRadius.btn),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? OrionColors.borderSoft
            : const Color.fromRGBO(255, 255, 255, 0.05),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: OrionColors.bgCardElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(OrionRadius.lg)),
        side: BorderSide(color: OrionColors.borderSoft),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: OrionColors.bgCardElevated,
        border: Border.all(color: OrionColors.borderSoft),
        borderRadius: BorderRadius.circular(OrionRadius.sm),
      ),
      textStyle: text.uiSmall.copyWith(color: OrionColors.textWhite),
      waitDuration: OrionMotion.med,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: OrionColors.bgCardElevated,
      contentTextStyle: text.ui,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OrionRadius.btn),
        side: const BorderSide(color: OrionColors.borderSoft),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(OrionRadius.sm),
  borderSide: BorderSide(color: color),
);
