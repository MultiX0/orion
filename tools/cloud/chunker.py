# Cuts a streaming LLM reply into pieces the TTS can start on early.
#
# This is the reference for firmware/components/orion_cloud/cloud_chunk.c. The
# rules are the same in both, and tools/cloud/chunker_test.py checks them.
#
# Rules:
#   - The first piece goes as soon as there is a clause of FIRST_MIN speakable
#     characters, because that is what decides when Orion starts talking.
#   - Later pieces wait for a full sentence of LATER_MIN, so there are few
#     joins, and every join is a place a gap can happen.
#   - Never cut inside a [tag]. A tag belongs to the words after it, so a tag
#     that sits after a cut moves with the next piece.
#   - A cut at a comma inside a sentence carries that sentence's tags into the
#     next piece. A tag colours everything after it within one TTS request, so
#     without this the second half of a [whispering] sentence would come out in
#     a normal voice.
#   - A sound cue right after a sentence end, "you did it! [laugh]", stays with
#     that sentence. Sent forward it was lost at the end of a reply. Cues are
#     free text on Fish S2, so nothing here knows a fixed list.
#   - Never emit a piece that is only tags, whitespace or punctuation.
#   - "." only ends a sentence when whitespace follows it, so 3.5 stays whole.

import re

FIRST_MIN = 15
LATER_MIN = 40

SENTENCE_END = set(".?!؟\n")          # . ? ! ؟ newline
CLAUSE_END = set(",،;؛:")         # , ، ; ؛ :
TAG = re.compile(r"\[[^\]]*\]")
# A model's control token leaked into the text: "<turn|>", "<|im_end|>".
MODEL_TOKEN = re.compile(r"<[A-Za-z_|/]{1,24}>")


def speakable(text):
    """Characters a listener would actually hear."""
    t = TAG.sub("", text)
    return sum(1 for ch in t if ch.isalnum())


SOUNDS = ("laugh", "chuckl", "giggl", "sigh", "gasp", "breath", "inhale", "exhale",
          "cough", "throat", "pause", "break", "sob", "cry", "yawn", "groan", "pant",
          "snor", "sniff")
CUE_MAX = 48


def is_sound(tag):
    return any(s in tag.lower() for s in SOUNDS)


def leading_tags(sentence):
    """The run of mood [tags] at the start of a sentence, ignoring whitespace.
    A sound tag ([chuckling]) stays where it was written; carried on, the
    laugh was heard twice."""
    tags = []
    rest = sentence.lstrip()
    while rest.startswith("["):
        end = rest.find("]")
        if end < 0:
            break
        tag = rest[:end + 1]
        if not is_sound(tag):
            tags.append(tag)
        rest = rest[end + 1:].lstrip()
    return "".join(tags)


class Chunker:
    def __init__(self, first_min=FIRST_MIN, later_min=LATER_MIN):
        self.buf = ""
        self.first_min = first_min
        self.later_min = later_min
        self.emitted = 0
        self.carry = ""          # tags carried over a mid-sentence cut

    def _cut_point(self, final):
        """Index just past the boundary to cut at, or -1."""
        depth = 0
        want = self.first_min if self.emitted == 0 else self.later_min
        allow_clause = self.emitted == 0
        best = -1
        for i, ch in enumerate(self.buf):
            if ch == "[":
                depth += 1
            elif ch == "]":
                depth = max(0, depth - 1)
            if depth:
                continue
            is_sentence = ch in SENTENCE_END
            is_clause = allow_clause and ch in CLAUSE_END
            if not (is_sentence or is_clause):
                continue
            if ch == "." and not final:
                nxt = self.buf[i + 1:i + 2]
                if nxt == "":
                    continue          # cannot tell yet whether a digit follows
                if not nxt.isspace():
                    continue
            if speakable(self.buf[:i + 1]) >= want:
                best = i + 1
                if is_sentence:
                    best = self._past_sound_cue(best, final)
                break
        return best

    def _past_sound_cue(self, at, final):
        """A sound cue right after the sentence end goes with the sentence.
        -1 while that cannot be told yet."""
        rest = self.buf[at:]
        j = at + len(rest) - len(rest.lstrip())
        if j >= len(self.buf):
            return at if final else -1
        if self.buf[j] != "[":
            return at
        end = self.buf.find("]", j)
        if end < 0:
            return -1 if (not final and len(self.buf) - j < CUE_MAX) else at
        return end + 1 if is_sound(self.buf[j:end + 1]) else at

    def _emit(self, piece, mid_sentence):
        carried = self.carry
        piece = MODEL_TOKEN.sub("", piece)
        text = (carried + " " + piece.strip()) if carried else piece.strip()
        self.carry = ""
        if mid_sentence:
            # The sentence goes on in the next piece, so its tone goes with it.
            last_end = max((piece.rfind(ch) for ch in SENTENCE_END), default=-1)
            tags = leading_tags(piece[last_end + 1:])
            self.carry = tags or (carried if last_end < 0 else "")
        if speakable(text) == 0:
            return None
        self.emitted += 1
        return text

    def feed(self, delta):
        """Adds LLM text. Returns a ready piece, or None."""
        self.buf += delta
        cut = self._cut_point(final=False)
        if cut < 0:
            return None
        piece, self.buf = self.buf[:cut], self.buf[cut:]
        return self._emit(piece, mid_sentence=piece.rstrip()[-1:] in CLAUSE_END)

    def finish(self):
        """End of the stream. Returns whatever is left if it is worth saying."""
        piece, self.buf = self.buf, ""
        if speakable(piece) == 0:
            self.carry = ""
            return None
        return self._emit(piece, mid_sentence=False)


def split_all(text, step=3):
    """Feeds text a few characters at a time, the way the stream arrives."""
    ck = Chunker()
    out = []
    for i in range(0, len(text), step):
        p = ck.feed(text[i:i + step])
        while p:
            out.append(p)
            p = ck.feed("")
    p = ck.finish()
    if p:
        out.append(p)
    return out
