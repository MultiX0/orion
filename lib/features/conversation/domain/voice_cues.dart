/// Fish Audio voice cues in square brackets, "[laugh]" or
/// "[laughing nervously]", are performed by the voice and never meant to be
/// read. The board strips them from its own screen; this does the same for
/// the reply the app shows. An unclosed "[" is kept as text.
String withoutVoiceCues(String text) {
  if (!text.contains('[')) return text;
  return text
      .replaceAll(RegExp(r'\[[^\[\]]*\]'), ' ')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAllMapped(RegExp(r'[ \t]+([.,!?:;،؛؟])'), (m) => m[1]!)
      .trim();
}
