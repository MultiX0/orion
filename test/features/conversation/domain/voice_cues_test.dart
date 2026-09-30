import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/conversation/domain/voice_cues.dart';

void main() {
  test('drops cues anywhere in the reply, free-form ones too', () {
    expect(
      withoutVoiceCues('I cannot believe it [gasp] you did it [laugh].'),
      'I cannot believe it you did it.',
    );
    expect(
      withoutVoiceCues('[laughing nervously] معك حق، أعتذر.'),
      'معك حق، أعتذر.',
    );
    expect(
      withoutVoiceCues('قال: كي أوفّر الوقت! [laugh]'),
      'قال: كي أوفّر الوقت!',
    );
  });

  test('keeps text without cues and an unclosed bracket as it is', () {
    expect(withoutVoiceCues('Amman is the capital.'), 'Amman is the capital.');
    expect(withoutVoiceCues('a [ b'), 'a [ b');
  });
}
