# Cases the chunker must get right, in Python here and in C on the board. Each
# case is fed a few characters at a time, the way the LLM stream arrives.
#
#   python tools/cloud/chunker_test.py

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chunker

CASES = [
    # A short reply is one piece. Nothing to gain from cutting it.
    ("عمان طبعاً.", ["عمان طبعاً."]),

    # First clause goes early at the comma, the rest waits for a full sentence.
    ("عاصمة فرنسا هي باريس، وهي مدينة جميلة كتير ومشهورة ببرج إيفل.",
     ["عاصمة فرنسا هي باريس،", "وهي مدينة جميلة كتير ومشهورة ببرج إيفل."]),

    # A tag after a cut belongs to the next sentence, never to the end of this one.
    ("[warm] أهلين، أنا أوريون وجاهز أساعدك. [playful] بس لا تسألني عن الطقس!",
     ["[warm] أهلين، أنا أوريون وجاهز أساعدك.",
      "[playful] بس لا تسألني عن الطقس!"]),

    # A comma cut inside a tagged sentence carries the tag into the continuation.
    ("[whispering] هاد سر كبير بيني وبينك، ما تحكي لحدا أبداً ولا حتى لأمك.",
     ["[whispering] هاد سر كبير بيني وبينك،",
      "[whispering] ما تحكي لحدا أبداً ولا حتى لأمك."]),

    # Never cut inside a tag, even when it contains a comma or a period.
    ("[the calm, measured tone of a pro. really] كل شي تمام وماشي حسب الخطة.",
     ["[the calm, measured tone of a pro. really] كل شي تمام وماشي حسب الخطة."]),

    # A sound cue right after a sentence end stays with it, the last one too.
    ("تمام، خلصت كل الشغل اللي طلبته مني اليوم. [laughing]",
     ["تمام، خلصت كل الشغل اللي طلبته مني اليوم. [laughing]"]),

    # 3.5 is not a sentence end.
    ("The file is 3.5 megabytes and it loads in about two seconds.",
     ["The file is 3.5 megabytes and it loads in about two seconds."]),

    # English, first clause early.
    ("The capital of France is Paris, and it is famous for the Eiffel Tower.",
     ["The capital of France is Paris,", "and it is famous for the Eiffel Tower."]),

    # A control token Gemma leaks at the end is never read out.
    ("It will be sunny tomorrow in Irbid.<turn|>",
     ["It will be sunny tomorrow in Irbid."]),

    # A laugh is a sound, not a mood: it is not carried across a comma cut.
    ("[chuckling] That is a classic excuse, but I believe you, and I think so too.",
     ["[chuckling] That is a classic excuse,", "but I believe you, and I think so too."]),

    # A pause before a punchline and the laugh after it, both kept in place.
    ("Why did the man put his clock in the bank? [pause] He wanted to save time! [laugh]",
     ["Why did the man put his clock in the bank? [pause]", "He wanted to save time! [laugh]"]),
    ("سأل رجلٌ صديقه: لماذا وضعتَ ساعتك في البنك؟ [pause] قال: كي أوفّر الوقت! [laugh]",
     ["سأل رجلٌ صديقه: لماذا وضعتَ ساعتك في البنك؟ [pause]", "قال: كي أوفّر الوقت! [laugh]"]),

    # A free-form cue in the middle of a sentence stays with the words after it.
    ("The capital of France is Paris, [laughing nervously] or at least it was yesterday.",
     ["The capital of France is Paris,", "[laughing nervously] or at least it was yesterday."]),
    ("Honestly that is the best news [gasp] I have heard all week, and I mean it.",
     ["Honestly that is the best news [gasp] I have heard all week,", "and I mean it."]),

    # A free-form mood is carried over a comma cut like any other.
    ("[whispers sweetly] هذا سرّ صغير بيني وبينك، لا تخبر به أحداً أبداً ولا حتى أمك.",
     ["[whispers sweetly] هذا سرّ صغير بيني وبينك،",
      "[whispers sweetly] لا تخبر به أحداً أبداً ولا حتى أمك."]),
]


def main():
    failed = 0
    for step in (1, 3, 7):
        for text, want in CASES:
            got = chunker.split_all(text, step=step)
            if got != want:
                failed += 1
                print("FAIL step %d\n  text %s\n  want %s\n  got  %s" % (step, text, want, got))
    total = len(CASES) * 3
    print("%d of %d passed" % (total - failed, total))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
