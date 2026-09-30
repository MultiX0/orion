/// Takes tool names out of words the board is about to speak. The prompt
/// already asks for none, but models still say things like "I checked with
/// ui_look: the calculator is open".
///
/// Only names that cannot be ordinary words are touched, the ones with an
/// underscore: "media" and "weather" are left alone.
String withoutToolNames(String text, Iterable<String> toolNames) {
  final names = toolNames.where((n) => n.contains('_')).toSet();
  if (names.isEmpty || text.isEmpty) return text;
  // The name, maybe in backticks or with "()", maybe "the ... tool".
  final tool =
      r'(?:\bthe\s+)?`?(?<![A-Za-z0-9_])(?:' +
      names.map(RegExp.escape).join('|') +
      r')(?![A-Za-z0-9_])(?:\(\))?`?(?:\s+tool)?';
  if (!RegExp(tool, caseSensitive: false).hasMatch(text)) return text;

  RegExp re(String s) => RegExp(s, caseSensitive: false);
  final out = text
      // A lead-in that only says how: "I checked with ui_look: X" is "X".
      .replaceAllMapped(
        re(r'(^|[.!?]\s+)[^.!?:,\n]*?' + tool + r'[^.!?:\n]*:\s+(?=\S)'),
        (m) => m[1]!,
      )
      // "Using open_app, I opened Spotify" is "I opened Spotify".
      .replaceAllMapped(
        re(
          r'(^|[.!?]\s+)(?:using|with|via|through|after|by)\s[^.!?:,\n]*?' +
              tool +
              r'[^.!?:,\n]*,\s+(?=\S)',
        ),
        (m) => m[1]!,
      )
      // "I checked with ui_look that X" is "I checked that X".
      .replaceAll(re(r'\s*\b' + _how + r'\s+' + tool), '')
      // Anything left: the name alone goes.
      .replaceAll(re(tool), '');
  return _tidy(out);
}

const _how = r'(?:with|using|via|through|by\s+(?:calling|running|using))';

/// Mends what a cut leaves: doubled spaces, a space before a stop, a
/// sentence that starts with a comma or a small letter.
String _tidy(String s) => s
    .replaceAll(RegExp(r'[ \t]*\([ \t]*\)'), '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r'[ \t]+([.,!?:;])'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'[,:;]+([.!?])'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'([.!?])[ \t]*[,:;]+'), (m) => m[1]!)
    .trim()
    .replaceFirst(RegExp(r'^[,:;.]+\s*'), '')
    .replaceAllMapped(
      RegExp(r'(^|[.!?]\s+)([a-z])'),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
    );
