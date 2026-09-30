// Reads brand/tokens.json and writes lib/core/theme/tokens.dart.
// Run from the repo root: dart run tool/gen_tokens.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final raw = File('brand/tokens.json').readAsStringSync();
  final tokens = jsonDecode(raw) as Map<String, dynamic>;
  final out = StringBuffer()
    ..writeln('// Generated from brand/tokens.json by tool/gen_tokens.dart.')
    ..writeln('// Do not edit by hand. Rerun the tool when the brand changes.')
    ..writeln()
    ..writeln("import 'package:flutter/animation.dart';")
    ..writeln("import 'package:flutter/painting.dart';")
    ..writeln();
  _colors(out, tokens['color'] as Map<String, dynamic>);
  _fonts(out, tokens['font'] as Map<String, dynamic>);
  _space(out, tokens['space'] as Map<String, dynamic>);
  _numbers(out, 'OrionContainer', tokens['container'] as Map<String, dynamic>);
  _numbers(
    out,
    'OrionBreakpoint',
    tokens['breakpoint'] as Map<String, dynamic>,
  );
  _radius(out, tokens['radius'] as Map<String, dynamic>);
  _motion(out, tokens['motion'] as Map<String, dynamic>);
  _shadows(out, tokens['shadow'] as Map<String, dynamic>);
  _ints(out, 'OrionZ', tokens['z'] as Map<String, dynamic>);
  File('lib/core/theme/tokens.dart').writeAsStringSync(out.toString());
  Process.runSync('dart', [
    'format',
    'lib/core/theme/tokens.dart',
  ], runInShell: true);
  stdout.writeln('wrote lib/core/theme/tokens.dart');
}

void _colors(StringBuffer out, Map<String, dynamic> color) {
  out.writeln('abstract final class OrionColors {');
  for (final group in ['bg', 'text', 'border']) {
    final map = color[group] as Map<String, dynamic>;
    for (final entry in map.entries) {
      final name = '$group${_cap(entry.key)}';
      out.writeln('  static const $name = ${_color(entry.value as String)};');
    }
  }
  final accent = color['accent'] as Map<String, dynamic>;
  out.writeln('  static const accent = ${_color(accent['base'] as String)};');
  out.writeln(
    '  static const accentGlow = ${_rgb(accent['glowRgb'] as String)};',
  );
  out.writeln('}');
  out.writeln();
  out.writeln('/// Alpha steps for the accent. It is light, not paint.');
  out.writeln('abstract final class OrionAlpha {');
  final alphas = accent['alphas'] as Map<String, dynamic>;
  for (final entry in alphas.entries) {
    out.writeln('  static const double ${entry.key} = ${entry.value};');
  }
  out.writeln('}');
  out.writeln();
}

void _fonts(StringBuffer out, Map<String, dynamic> font) {
  final family = font['family'] as Map<String, dynamic>;
  final role = font['role'] as Map<String, dynamic>;
  out.writeln('abstract final class OrionFonts {');
  for (final entry in family.entries) {
    final name = _firstFamily(entry.value as String);
    out.writeln("  static const ${entry.key} = '$name';");
  }
  for (final entry in role.entries) {
    out.writeln('  static const ${entry.key} = ${entry.value};');
  }
  out.writeln('}');
  out.writeln();

  out.writeln(
    '/// Fixed sizes in logical pixels. Fluid sizes ship as min and max.',
  );
  out.writeln('abstract final class OrionFontSize {');
  final size = font['size'] as Map<String, dynamic>;
  for (final entry in size.entries) {
    final value = entry.value as String;
    if (value.startsWith('clamp')) {
      final parts = value.substring(6, value.length - 1).split(',');
      out.writeln('  static const double ${entry.key}Min = ${_px(parts[0])};');
      out.writeln('  static const double ${entry.key}Max = ${_px(parts[2])};');
    } else {
      out.writeln('  static const double ${entry.key} = ${_px(value)};');
    }
  }
  out.writeln('}');
  out.writeln();

  out.writeln('abstract final class OrionFontWeight {');
  final weight = font['weight'] as Map<String, dynamic>;
  for (final entry in weight.entries) {
    out.writeln('  static const ${entry.key} = FontWeight.w${entry.value};');
  }
  out.writeln('}');
  out.writeln();

  _doubles(out, 'OrionLineHeight', font['lineHeight'] as Map<String, dynamic>);

  out.writeln(
    '/// Tracking in em. Multiply by the font size for letterSpacing.',
  );
  out.writeln('abstract final class OrionTracking {');
  final tracking = font['tracking'] as Map<String, dynamic>;
  for (final entry in tracking.entries) {
    final value = (entry.value as String).replaceAll('em', '');
    out.writeln('  static const double ${entry.key} = $value;');
  }
  out.writeln('}');
  out.writeln();
}

void _space(StringBuffer out, Map<String, dynamic> space) {
  out.writeln(
    '/// Spacing scale. The sN names mirror tokens.json, the rest are roles.',
  );
  out.writeln('abstract final class Space {');
  for (final entry in space.entries) {
    final value = _px(entry.value as String);
    out.writeln('  static const double s${entry.key} = $value;');
  }
  out.writeln('  static const double xxs = s1;');
  out.writeln('  static const double xs = s2;');
  out.writeln('  static const double sm = s3;');
  out.writeln('  static const double md = s4;');
  out.writeln('  static const double lg = s6;');
  out.writeln('  static const double xl = s8;');
  out.writeln('  static const double xxl = s10;');
  out.writeln('}');
  out.writeln();
}

void _radius(StringBuffer out, Map<String, dynamic> radius) {
  out.writeln('abstract final class OrionRadius {');
  for (final entry in radius.entries) {
    final value = entry.value as String;
    final number = value.endsWith('%') ? '9999' : _px(value);
    out.writeln('  static const double ${entry.key} = $number;');
  }
  out.writeln('}');
  out.writeln();
}

void _motion(StringBuffer out, Map<String, dynamic> motion) {
  out.writeln('abstract final class OrionMotion {');
  final ease = motion['ease'] as Map<String, dynamic>;
  for (final entry in ease.entries) {
    final value = entry.value as String;
    final args = value.substring(13, value.length - 1);
    out.writeln('  static const ease${_cap(entry.key)} = Cubic($args);');
  }
  final duration = motion['duration'] as Map<String, dynamic>;
  for (final entry in duration.entries) {
    out.writeln('  static const ${entry.key} = ${_ms(entry.value as String)};');
  }
  out.writeln('  static const stagger = ${_ms(motion['stagger'] as String)};');
  out.writeln('}');
  out.writeln();
}

void _shadows(StringBuffer out, Map<String, dynamic> shadow) {
  out.writeln('abstract final class OrionShadow {');
  for (final entry in shadow.entries) {
    final value = entry.value as String;
    final open = value.indexOf('rgba');
    final parts = value.substring(0, open).trim().split(RegExp(r'\s+'));
    final color = _color(value.substring(open));
    final blur = _px(parts[2]);
    out.writeln(
      '  static const ${entry.key} = BoxShadow(color: $color, blurRadius: $blur);',
    );
  }
  out.writeln('}');
  out.writeln();
}

void _numbers(StringBuffer out, String name, Map<String, dynamic> map) {
  out.writeln('abstract final class $name {');
  for (final entry in map.entries) {
    final value = _px(entry.value as String);
    out.writeln('  static const double ${_ident(entry.key)} = $value;');
  }
  out.writeln('}');
  out.writeln();
}

// A few token names are Dart keywords.
String _ident(String key) => switch (key) {
  'default' => 'standard',
  _ => key,
};

void _doubles(StringBuffer out, String name, Map<String, dynamic> map) {
  out.writeln('abstract final class $name {');
  for (final entry in map.entries) {
    out.writeln('  static const double ${entry.key} = ${entry.value};');
  }
  out.writeln('}');
  out.writeln();
}

void _ints(StringBuffer out, String name, Map<String, dynamic> map) {
  out.writeln('abstract final class $name {');
  for (final entry in map.entries) {
    out.writeln('  static const int ${entry.key} = ${entry.value};');
  }
  out.writeln('}');
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

String _px(String value) => value.trim().replaceAll('px', '');

String _ms(String value) {
  final number = value.trim().replaceAll('ms', '');
  return 'Duration(milliseconds: $number)';
}

String _firstFamily(String stack) {
  final match = RegExp("'([^']+)'").firstMatch(stack);
  return match?.group(1) ?? stack.split(',').first.trim();
}

String _rgb(String triplet) {
  final parts = triplet.split(',').map((p) => p.trim()).toList();
  return 'Color.fromRGBO(${parts[0]}, ${parts[1]}, ${parts[2]}, 1)';
}

String _color(String css) {
  if (css.startsWith('#')) {
    return 'Color(0xFF${css.substring(1).toUpperCase()})';
  }
  final inner = css.substring(css.indexOf('(') + 1, css.lastIndexOf(')'));
  final parts = inner.split(',').map((p) => p.trim()).toList();
  return 'Color.fromRGBO(${parts[0]}, ${parts[1]}, ${parts[2]}, ${parts[3]})';
}
