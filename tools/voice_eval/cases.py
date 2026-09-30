# The fixed questions the voice eval asks every prompt. Each case is
# (id, user text) or (id, user text, history), history being earlier
# (user, assistant) turns, the way the board sends them.

CASES = [
    ("greet_ar", "مرحبا أوريون، كيف حالك؟"),
    ("morning_ar", "صباح الخير"),
    ("joke_ar", "احكيلي نكتة قصيرة"),
    ("weather_ar", "كيف الطقس اليوم في عمّان؟"),
    ("time_ar", "كم الساعة هلأ؟"),
    ("date_ar", "شو تاريخ اليوم؟"),
    ("fact_ar", "ما عاصمة أستراليا؟"),
    ("moon_ar", "كم تبعد الأرض عن القمر؟"),
    ("history_ar", "متى استقل الأردن؟"),
    ("apology_ar", "لا، هذا غلط.",
     [("ما عاصمة أستراليا؟", "عاصمة أستراليا سيدني.")]),
    ("reminder_ar", "ذكّريني بكرة الساعة ثمانية الصبح بموعد الدكتور"),
    ("pc_ar", "افتحي يوتيوب على الكمبيوتر"),
    ("explain_ar", "اشرحي لي كيف يعمل الذكاء الاصطناعي"),
    ("story_ar", "احكيلي قصة قصيرة قبل النوم"),
    ("tired_ar", "أنا تعبان كثير اليوم"),
    ("news_ar", "نجحت في امتحان التوجيهي!"),
    ("funny_ar", "قطتي أكلت دفتر الواجب، والأستاذ ما صدّقني"),
    ("advice_ar", "شو أحسن لغة برمجة أبدأ فيها؟"),
    ("math_ar","معي مئة وخمسون ديناراً وصرفت ثلثها، كم بقي معي؟"),
    ("who_ar", "مين إنتِ؟"),
    ("greet_en", "Hi Orion, how are you?"),
    ("joke_en", "Tell me a joke."),
    ("funny_en", "My dog just ate my homework. For real this time."),
    ("time_en", "What time is it?"),
    ("reminder_en", "Remind me to call my mom at six."),
    ("explain_en", "Explain how a rainbow forms."),
]

# What the board adds after the prompt: its clock line (cloud_reply.c
# now_line, pinned here so every run asks at the same moment) and the note for
# a turn with no PC or phone connected, the default assistant's usual case.
NOW = "\n\nCurrent local date and time: Thursday 24 September 2026, 11:40 at night (23:40)."

NOTE_ALONE = (
    "\n\nNo PC or phone is connected to you right now. You cannot open, close, play or change "
    "anything on a computer or phone, and you cannot search the web. If asked to, say in one short "
    "sentence that the Orion app has to be open on the PC first, or on the phone for something on "
    "the phone, for example: افتح تطبيق Orion على الكمبيوتر أولاً، وبعدها أفعلها لك. "
    "Never say you did it."
)

# The look tool exactly as cloud_reply.c offers it in "tool" mode.
LOOK_TOOL = [{
    "type": "function",
    "function": {
        "name": "look",
        "description": "Take a picture with the camera and look at what is in front of the device. "
                       "Call this whenever the user asks about something you can see.",
        "parameters": {"type": "object", "properties": {}},
    },
}]
