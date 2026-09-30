import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/spoken_tool_names.dart';

void main() {
  const names = [
    'ui_look',
    'ui_act',
    'open_app',
    'open_windows',
    'run_powershell',
    'web_search',
    'media',
    'weather',
  ];
  String scrub(String s) => withoutToolNames(s, names);

  test('a lead-in that names the tool goes, the result stays', () {
    expect(
      scrub('I checked with ui_look: the calculator is open.'),
      'The calculator is open.',
    );
    expect(scrub('Using open_app, I opened Spotify.'), 'I opened Spotify.');
    expect(
      scrub('Spotify is open. According to open_windows: Chrome is too.'),
      'Spotify is open. Chrome is too.',
    );
  });

  test('"with the tool" goes from the middle of a sentence', () {
    expect(
      scrub('I checked with ui_look that the song is playing.'),
      'I checked that the song is playing.',
    );
    expect(scrub('I closed it by running run_powershell.'), 'I closed it.');
    expect(
      scrub('Chrome is open, I checked using the `open_windows` tool.'),
      'Chrome is open, I checked.',
    );
  });

  test('a bare name goes and the punctuation is mended', () {
    expect(scrub('Done, ui_act clicked Play.'), 'Done, clicked Play.');
    expect(
      scrub('The search (web_search) found nothing.'),
      'The search found nothing.',
    );
  });

  test('ordinary words and names without an underscore are left alone', () {
    const plain = 'The media player shows the weather, and open apps work.';
    expect(scrub(plain), plain);
    expect(scrub('Tokyo.'), 'Tokyo.');
    const lookalike = 'The ui_looking glass is fine.';
    expect(scrub(lookalike), lookalike);
  });

  test('an Arabic answer loses the name and keeps its words', () {
    expect(
      scrub('تحققتُ عبر ui_look: الآلة الحاسبة مفتوحة.'),
      'الآلة الحاسبة مفتوحة.',
    );
  });
}
