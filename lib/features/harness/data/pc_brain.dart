import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import '../../providers/data/provider_headers.dart';
import '../../providers/domain/llm_provider.dart';
import '../domain/harness_call.dart';
import '../domain/harness_call_status.dart';
import '../domain/tool_request.dart';
import '../domain/tool_spec.dart';
import 'pc_memory.dart';
import 'pc_web_tools.dart';
import 'spoken_tool_names.dart';

/// Orion's extended brain, on the PC or on the phone. The board sends its usual
/// chat request here instead of to the model's host; this runs the turn as an
/// agent, with the date and time, the web, what was said before and this
/// device's tools, and streams back only the spoken answer, in the same OpenAI
/// SSE shape the board already reads. The board stays the voice: it wakes,
/// listens and speaks. A tool the board offered itself (look, its camera) goes
/// back to the board as a tool call.
class PcBrain {
  PcBrain({
    required this.brain,
    required this.catalog,
    required this.runTool,
    required this.updates,
    this.memory,
    this.desktopState,
    this.onPhone = false,
    this.reasoningEffort,
    PcWebTools? web,
    HttpClient? client,
    DateTime Function()? now,
  }) : web = web ?? PcWebTools(),
       _client = client ?? HttpClient(),
       _now = now ?? DateTime.now;

  final Future<(LlmProvider, String)?> Function() brain;
  final Future<List<ToolSpec>> Function() catalog;
  final Future<HarnessCall> Function(ToolRequest request) runTool;
  final Stream<HarnessCall> updates;
  final PcWebTools web;

  /// The conversation and the actions taken, kept on disk. Null: the board's
  /// own short history is used as it comes.
  final PcMemory? memory;

  /// The apps with a window open right now, for context.
  final Future<List<String>> Function()? desktopState;

  /// Running in the phone app: the phone's words and tools, not the PC's.
  final bool onPhone;

  /// "low", "medium" or "high" for a model that takes it; null sends none,
  /// and a thinking model thinks at its own default.
  final String? reasoningEffort;
  final HttpClient _client;
  final DateTime Function() _now;

  /// Opening an app, looking at it, typing, looking again and clicking is
  /// five rounds on its own.
  static const _maxRounds = 14;

  /// Tools that only look something up. The fast model may use these itself;
  /// any other tool acts on the PC or phone, and the turn goes to the
  /// thinking model. A fast model tends to claim it played a song it only
  /// searched for.
  static const _lookUps = {
    PcWebTools.searchName,
    PcWebTools.fetchName,
    PcWebTools.weatherName,
    'open_windows',
    'system_stats',
    'ui_look',
  };

  /// Makes the first model request before anything is sent back, so a PC with
  /// no model set up, a bad key or no internet answers with an error and the
  /// board falls back to its own model instead of saying nothing. Null then.
  Future<Stream<List<int>>?> open(Map<String, dynamic> body) async {
    final chosen = await brain();
    if (chosen == null) return null;
    final (provider, model) = chosen;
    final clientTools = ((body['tools'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final raw = ((body['messages'] as List?) ?? const [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    final system = raw.isNotEmpty && raw.first['role'] == 'system'
        ? raw.first
        : null;
    final last = raw.isNotEmpty && raw.last != system ? raw.last : null;
    // The PC's own record replaces the board's short one: it survives
    // reboots and knows what was done, not only what was said.
    final remembered = memory;
    final tools = [
      ...(await catalog()).map((t) => t.toFunctionJson()),
      ...PcWebTools.specs,
      ...clientTools,
    ];
    final messages = remembered == null
        ? raw
        : [
            ?system,
            ...remembered.history(
              known: {
                for (final t in tools) '${(t['function'] as Map?)?['name']}',
              },
            ),
            ?last,
          ];
    // Said on the request itself as well as in the system prompt: after a
    // few tool rounds with Arabic turns in the history, a model answers an
    // English request in Arabic. Not kept in memory.
    final note = _languageNote(_text(last?['content']));
    if (note.isNotEmpty &&
        messages.isNotEmpty &&
        messages.last['role'] == 'user' &&
        messages.last['content'] is String) {
      messages[messages.length - 1] = <String, dynamic>{
        ...messages.last,
        'content': '${messages.last['content']}\n\n$note',
      };
    }
    final windows = await (desktopState?.call() ?? Future.value(<String>[]))
        .timeout(const Duration(seconds: 3), onTimeout: () => <String>[]);
    final state = _Turn(
      provider: provider,
      model: model,
      thinkingModel: provider.thinkingModel,
      userText: _text(last?['content']),
      messages: _withContext(
        messages,
        windows,
        remembered?.recentActions() ?? '',
        _text(last?['content']),
      ),
      tools: tools,
      clientNames: clientTools
          .map((t) => '${(t['function'] as Map?)?['name']}')
          .toSet(),
      temperature: (body['temperature'] as num?)?.toDouble() ?? 0.6,
    );
    final HttpClientResponse first;
    try {
      first = await _request(state);
    } on Object {
      return null;
    }
    return _run(state, first);
  }

  Stream<List<int>> _run(_Turn t, HttpClientResponse first) async* {
    // An empty opening event, the way hosted models start a stream. The
    // board's HTTP client keeps only the last body piece that arrives with the
    // headers, so without this the first word is lost.
    yield _sse(<String, dynamic>{'role': 'assistant', 'content': ''});
    final started = _now();
    var response = first;
    var answer = '';
    var handedBack = false;
    // True once the turn's last words went out. Out of rounds, [answer] can
    // hold the words of a round that went on to call tools, never spoken,
    // and the board would have said only "one moment".
    var finished = false;
    for (var round = 0; round < _maxRounds; round++) {
      final calls = <int, _Call>{};
      final said = StringBuffer();
      final roundStarted = _now();
      // An everyday answer on the fast model gets no "one moment" unless
      // it is slow; a task gets it at once.
      final fillerAfter = round == 0 && !t.thinking
          ? _fillerOnAnswer
          : _pulseEvery;
      await for (final delta in _ticking(response)) {
        // Checked on a clock, not only when a piece arrives: a thinking
        // model can send nothing for 24 s while it thinks.
        if (!t.said && _now().difference(roundStarted) > fillerAfter) {
          yield _filler(t);
        } else if (_now().difference(t.lastSign) > _pulseEvery) {
          t.lastSign = _now();
          yield _alive;
        }
        if (delta == null) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          // Held until the round ends: a round that goes on to call tools is
          // the model thinking aloud ("let me check Spotify first"), which
          // must not be spoken; only the last round's words are the answer.
          said.write(content);
        }
        for (final c in (delta['tool_calls'] as List?) ?? const []) {
          final m = c as Map<String, dynamic>;
          final call = calls.putIfAbsent(m['index'] as int? ?? 0, _Call.new);
          call.id ??= m['id'] as String?;
          final fn = m['function'] as Map<String, dynamic>?;
          call.name.write(fn?['name'] ?? '');
          call.args.write(fn?['arguments'] ?? '');
        }
      }
      answer = _dropTokens(said.toString());
      // The phone has nothing to look at the screen with.
      if (calls.isEmpty &&
          !onPhone &&
          t.uncheckedAct &&
          !t.nudged &&
          round < _maxRounds - 1) {
        // About to answer right after acting, without having looked at
        // what came of it: once, the model is asked to check first. Models
        // report a YouTube search as done without ever looking at it.
        t.nudged = true;
        t.messages
          ..add(<String, dynamic>{'role': 'assistant', 'content': answer})
          ..add(<String, dynamic>{
            'role': 'user',
            'content':
                'Before you tell me: look and check that what I asked is '
                'really done (ui_look, media status or open_windows). If it '
                'is not, keep going; if it is, say so.',
          });
        final again = _request(t);
        yield* _whileWaiting(again, t);
        try {
          response = await again;
        } on Object {
          answer = _couldNot;
          finished = true;
          yield _sse(<String, dynamic>{'content': answer});
          break;
        }
        continue;
      }
      if (calls.isEmpty) {
        answer = withoutToolNames(answer, t.toolNames);
        if (answer.isNotEmpty) {
          t.said = true;
          finished = true;
          yield _sse(<String, dynamic>{'content': answer});
        }
        break;
      }

      final acting = calls.values.any(
        (c) => _acts(c.name.toString(), c.decodedArgs(), t),
      );
      final thinker = t.thinkingModel;
      // A task: the board says "one moment" now, not after the first long
      // wait. Each step is short, but the first filler can come 17 s late.
      if (acting && !t.said) yield _filler(t);
      if (acting && thinker != null && !t.thinking) {
        // The round is dropped, not run: the thinking model plans the task
        // from the request itself.
        t.model = thinker;
        final handed = _request(t);
        yield* _whileWaiting(handed, t);
        try {
          response = await handed;
        } on Object {
          answer = _couldNot;
          finished = true;
          yield _sse(<String, dynamic>{'content': answer});
          break;
        }
        continue;
      }

      final forBoard = calls.values
          .where((c) => t.clientNames.contains(c.name.toString()))
          .firstOrNull;
      if (forBoard != null) {
        // The board looks and asks again with the picture; that turn is
        // the one remembered.
        handedBack = true;
        yield _sse(<String, dynamic>{
          'tool_calls': [forBoard.toJson(0)],
        }, finish: 'tool_calls');
        break;
      }
      if (_now().difference(started) > _budget) {
        // The summary below says what was done; the stock line only when
        // that fails too.
        break;
      }

      t.messages.add(<String, dynamic>{
        'role': 'assistant',
        'content': answer.isEmpty ? null : answer,
        'tool_calls': [for (final (i, c) in calls.values.indexed) c.toJson(i)],
      });
      final tools = _runTools(t, calls.values.toList());
      yield* _whileWaiting(tools, t);
      await tools;
      // The last round's results go to the summary request below instead.
      if (round == _maxRounds - 1) break;
      final next = _request(t);
      yield* _whileWaiting(next, t);
      try {
        response = await next;
      } on Object {
        answer = _couldNot;
        finished = true;
        yield _sse(<String, dynamic>{'content': answer});
        break;
      }
    }
    if (!finished && !handedBack) {
      // Out of rounds or time with nothing said: one more request, tools
      // off, for the words. Asked "what did you do and did it work", models
      // claim the song played after only looking at Spotify; given the list
      // of what they did, they say it is not done yet.
      final did = t.actions.isEmpty
          ? '- nothing yet'
          : t.actions.map((a) => '- $a').join('\n');
      t.messages.add(<String, dynamic>{
        'role': 'user',
        'content':
            'This is everything you did for me this turn, and nothing else '
            'happened:\n$did\nIn one short spoken sentence, in my language, '
            'tell me honestly where my request stands: if these steps did not '
            'finish it, say it is not done yet.',
      });
      final last = _request(t, tools: false);
      yield* _whileWaiting(last, t);
      try {
        final said = StringBuffer();
        await for (final delta in _deltas(await last)) {
          final c = delta['content'];
          if (c is String) said.write(c);
        }
        answer = withoutToolNames(
          _dropTokens(said.toString()).trim(),
          t.toolNames,
        );
      } on Object {
        answer = '';
      }
      yield _sse(<String, dynamic>{
        'content': answer.isEmpty ? _tooLong(t.userText) : answer,
      });
    }
    if (!handedBack) {
      memory?.addTurn(
        t.userText,
        answer,
        t.actions,
        calls: t.calls,
        model: t.model,
      );
    }
    yield utf8.encode('data: [DONE]\n\n');
  }

  /// Whether a call changes something on the PC or phone. media status
  /// only reads; play, pause and the rest act.
  static bool _acts(String name, Map<String, dynamic> args, _Turn t) {
    if (_lookUps.contains(name) || t.clientNames.contains(name)) return false;
    return !(name == 'media' && '${args['action']}' == 'status');
  }

  /// Whether a call shows what an act did: the screen, the windows, what
  /// plays. A web search is no check that the PC did something.
  static bool _checks(String name, Map<String, dynamic> args) =>
      name == 'ui_look' ||
      name == 'open_windows' ||
      name == 'screenshot' ||
      (name == 'media' && '${args['action']}' == 'status');

  Future<void> _runTools(_Turn t, List<_Call> calls) async {
    for (final c in calls) {
      final args = c.decodedArgs();
      final result = await _tool(c.name.toString(), args);
      // A look after acting is the check; an act after it needs another.
      t.uncheckedAct = _acts(c.name.toString(), args, t)
          ? true
          : (t.uncheckedAct && !_checks(c.name.toString(), args));
      t.actions.add('${c.name} $args: ${_short(result)}');
      t.calls.add(<String, dynamic>{
        'name': c.name.toString(),
        'args': args,
        'result': _short(result),
      });
      t.messages.add(<String, dynamic>{
        'role': 'tool',
        'tool_call_id': c.id,
        'content': _cap(result),
      });
    }
  }

  /// While [work] runs, the board hears that the brain is alive: once, when
  /// nothing has been said yet, a short "one moment" it speaks, then SSE
  /// comments it ignores. Its turn deadline counts from the last of these,
  /// so opening an app, searching it and clicking a result fits.
  Stream<List<int>> _whileWaiting(Future<Object?> work, _Turn t) async* {
    var done = false;
    unawaited(work.then((_) => done = true, onError: (_) => done = true));
    while (!done) {
      await Future.any<void>([
        work.then((_) {}, onError: (_) {}),
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      if (done) break;
      // Counted for the whole turn, not this wait: a task is many short
      // steps, none of them 3 s, and counted per wait the board would hear
      // nothing for 30 s and give up while the PC works.
      if (_now().difference(t.lastSign) <= _pulseEvery) continue;
      if (!t.said) {
        yield _filler(t);
      } else {
        t.lastSign = _now();
        yield _alive;
      }
    }
  }

  /// 128 bytes, one full read on the board: its HTTP client fills a
  /// 128-byte read before returning it. A 12-byte keep-alive would sit
  /// unread until ten more came, the filler stuck behind them, and the
  /// board's 30 s deadline would run out while the PC works.
  static final _alive = utf8.encode(': ${'working'.padRight(124)}\n\n');

  /// "One moment", once a turn, and a keep-alive behind it so the board
  /// reads it now.
  List<int> _filler(_Turn t) {
    t.said = true;
    t.lastSign = _now();
    return [
      ..._sse(<String, dynamic>{'content': '${_oneMoment(t.userText)} '}),
      ..._alive,
    ];
  }

  static const _pulseEvery = Duration(seconds: 3);
  static const _fillerOnAnswer = Duration(seconds: 8);

  /// The deltas of [resp], and a null each second none comes.
  Stream<Map<String, dynamic>?> _ticking(HttpClientResponse resp) {
    final out = StreamController<Map<String, dynamic>?>();
    final tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!out.isClosed) out.add(null);
    });
    final sub = _deltas(resp).listen(
      out.add,
      onError: out.addError,
      onDone: () {
        tick.cancel();
        out.close();
      },
    );
    out.onCancel = () {
      tick.cancel();
      return sub.cancel();
    };
    return out.stream;
  }

  /// The most a turn works before it answers with what it has.
  static const _budget = Duration(seconds: 90);

  /// Arabic when there are Arabic words at all: "شغّلي أغنية Save Your
  /// Tears" has more Latin letters than Arabic and still wants Arabic.
  static bool _arabic(String s) {
    final arabic = RegExp(r'[\u0600-\u06FF]').allMatches(s).length;
    final latin = RegExp('[A-Za-z]').allMatches(s).length;
    return arabic >= 2 || (arabic > 0 && arabic >= latin);
  }

  /// Fifteen letters or more: the board holds a first piece shorter than
  /// that for the words after it, so "One moment." would wait 30 s for them.
  static String _oneMoment(String heard) =>
      _arabic(heard) ? 'لحظة من فضلك، أعمل على ذلك.' : "One moment, I'm on it.";

  static String _tooLong(String heard) => _arabic(heard)
      ? 'أخذ هذا وقتاً طويلاً، فتوقفتُ هنا.'
      : 'That was taking too long, so I stopped here.';

  String get _couldNot =>
      'I could not finish that on the ${onPhone ? 'phone' : 'PC'} just now.';

  /// Drops a model's control tokens leaked into its words, `<turn|>` from
  /// Gemma or `<|im_end|>`, which the voice would read out.
  static String _dropTokens(String s) =>
      s.replaceAll(RegExp(r'<[A-Za-z_|/]{1,24}>'), '').trimRight();

  static String _short(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 120 ? '${one.substring(0, 120)}...' : one;
  }

  /// The text of a message: a string, or the text parts of a list.
  static String _text(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map<dynamic, dynamic>>()
          .where((p) => p['type'] == 'text')
          .map((p) => '${p['text']}')
          .join(' ');
    }
    return '';
  }

  /// "at night" for 23:40. Given the 24 hour clock, a model says "the
  /// twenty first hour" in Arabic.
  static String _partOfDay(int hour) => hour < 5
      ? 'at night'
      : hour < 12
      ? 'in the morning'
      : hour < 17
      ? 'in the afternoon'
      : hour < 21
      ? 'in the evening'
      : 'at night';

  /// Which language to answer in, decided from the letters of what was heard.
  /// The board's prompt leads with Arabic, and after a long context and a
  /// few Arabic answers in the history a model answers English in Arabic.
  /// So it goes last, where it weighs most: "(Answer in English.)" after the
  /// request.
  static String _languageNote(String heard) {
    if (_arabic(heard)) return '(أجب بالعربية الفصحى.)';
    return RegExp('[A-Za-z]').hasMatch(heard) ? '(Answer in English.)' : '';
  }

  static String _languageLine(String heard) {
    if (!_arabic(heard) && !RegExp('[A-Za-z]').hasMatch(heard)) return '';
    return _arabic(heard)
        ? '\n\nThe user\'s last message is in Arabic: answer in Arabic, the '
              'way a native speaker says it, never an English sentence '
              'translated: the verb itself (شغّلتُ، فتحتُ، أغلقتُ), not أقوم بـ '
              'or تم + مصدر.'
        : '\n\nThe user\'s last message is in English: answer in English '
              'only, not Arabic.';
  }

  /// The board's own prompt, plus what only this device knows.
  List<Map<String, dynamic>> _withContext(
    List<Map<String, dynamic>> out,
    List<String> windows,
    String actions,
    String heard,
  ) {
    final now = _now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final zone =
        'UTC$sign${offset.inHours.abs()}${offset.inMinutes % 60 == 0 ? '' : ':${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}'}';
    final here = onPhone ? 'phone' : 'PC';
    final where = onPhone
        ? '\n\nYou are running on the user\'s phone right now '
              '(${Platform.operatingSystem}), which lends the board its brain. '
        : '\n\nYou are running on the user\'s PC right now, '
              '"${Platform.localHostname}" (${Platform.operatingSystem}). ';
    final context =
        '$where'
        'It is ${DateFormat('EEEE d MMMM y, h:mm', 'en_US').format(now)} ${_partOfDay(now.hour)} local time ($zone). '
        'Use your tools when they help: web_search and fetch_page for anything '
        'current or that you are not sure of, and the $here tools to act on '
        'this $here. After a tool, answer in one or two short spoken sentences, '
        'in the language of the user\'s last message, even when the tool '
        'results are in another: say what you found or what you did. Use '
        'metric units: degrees Celsius, kilometres, kilograms. '
        'Never read out file paths, commands, code, URLs, JSON or long lists; '
        'round numbers and name at most three things. Never name a tool or '
        'say how you checked or did it ("I checked with ui_look", "I ended '
        'its process"): say only the result, in plain words, like "The '
        'calculator is open." If a tool failed, say so simply.'
        '${onPhone ? '' : ' If something is waiting for approval, ask the user to approve it on the PC screen.'}'
        '\n\nThe conversation so far is in the messages above, and it goes '
        'with the actions below: a short request like "play Lifetime by Chris '
        'Grey" or "pause it" means the app the user opened or used recently'
        '${onPhone ? '' : ', or the one open in the windows list'}. Act inside '
        'that app. For '
        'other apps use open_link with the app\'s link or address'
        '${onPhone ? '' : '. For any app there is no shortcut for, work it like a person would: open_app, then ui_look to see its buttons and fields, then ui_act to click or type, and ui_look again to check; run_powershell for anything Windows does from a command line. weather is a shortcut for forecasts, not a limit'}. '
        'Do the task, do not describe how the user could do it. A step is '
        'not the result: an opened search is not a song playing, so keep '
        'going until what was asked is done. Check it worked before you say '
        'so: look again (ui_look, open_windows, media status) and if it did '
        'not, try another way.'
        '\n\nEvery request to do something needs its tool call in this turn, '
        'even when the same thing was done before: never say something is '
        'open, playing or done unless a tool did it in this turn. '
        '${onPhone ? 'The conversation' : 'The windows list below is what is open right now; the conversation'} '
        'and the recent actions can be out of date, since the user may have '
        'closed things since. Only the last message is the task: earlier '
        'requests are finished, even ones that went wrong, so never go back '
        'to them unless the user asks again.'
        '${windows.isEmpty ? '' : '\n\nOpen on this PC now:\n${windows.take(15).map((w) => '- ${w.length > 90 ? w.substring(0, 90) : w}').join('\n')}'}'
        '${actions.isEmpty ? '' : '\n\nRecent actions on this $here:\n$actions'}'
        '${_languageLine(heard)}';
    final first = out.isEmpty ? null : out.first;
    if (first != null &&
        first['role'] == 'system' &&
        first['content'] is String) {
      first['content'] = '${first['content']}$context';
    } else {
      out.insert(0, <String, dynamic>{
        'role': 'system',
        'content': context.trim(),
      });
    }
    return out;
  }

  Future<HttpClientResponse> _request(_Turn t, {bool tools = true}) async {
    final req = await _client
        .postUrl(Uri.parse('${t.provider.baseUrl}/chat/completions'))
        .timeout(const Duration(seconds: 10));
    headersFor(t.provider).forEach(req.headers.set);
    req.headers.contentType = ContentType.json;
    req.add(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'model': t.model,
          'stream': true,
          // A thinking model spends its reasoning out of this too.
          'max_tokens': t.thinking ? 4000 : 600,
          'temperature': t.temperature,
          'messages': t.messages,
          if (tools) 'tools': t.tools,
          if (tools) 'tool_choice': 'auto',
          if (t.thinking) 'reasoning_effort': ?reasoningEffort,
        }),
      ),
    );
    final resp = await req.close().timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      final text = await resp.transform(utf8.decoder).join();
      throw HttpException('model http ${resp.statusCode}: $text');
    }
    return resp;
  }

  Stream<Map<String, dynamic>> _deltas(HttpClientResponse resp) async* {
    await for (final line
        in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') break;
      try {
        final choices = (jsonDecode(data) as Map)['choices'] as List?;
        final choice = choices?.firstOrNull as Map<String, dynamic>?;
        final delta = choice?['delta'];
        if (delta is Map<String, dynamic>) yield delta;
      } on FormatException {
        continue;
      }
    }
  }

  Future<String> _tool(String name, Map<String, dynamic> args) async {
    if (name == PcWebTools.searchName) {
      return web.search('${args['query'] ?? ''}');
    }
    if (name == PcWebTools.fetchName) {
      return web.fetch('${args['url'] ?? ''}');
    }
    if (name == PcWebTools.weatherName) {
      return web.weather('${args['place'] ?? ''}');
    }

    final id = 'v${_now().microsecondsSinceEpoch}';
    HarnessCall? latest;
    final finished = Completer<void>();
    final sub = updates.listen((c) {
      if (c.callId != id) return;
      latest = c;
      if (_final(c.status) && !finished.isCompleted) finished.complete();
    });
    try {
      var call = await runTool(
        ToolRequest(callId: id, name: name, args: args, turnId: 'voice'),
      );
      if (!_final(call.status)) {
        // Inside the board's 30 s turn: an approval or a long agent task is
        // reported as waiting, not waited out.
        await finished.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () {},
        );
        call = latest ?? call;
      }
      return switch (call.status) {
        HarnessCallStatus.done => call.result ?? 'Done.',
        HarnessCallStatus.denied => 'The user said no to this on the PC.',
        HarnessCallStatus.error =>
          'It failed: ${call.message ?? 'unknown error'}.',
        HarnessCallStatus.pendingConfirmation =>
          'Waiting for the user to approve this on the PC screen.',
        _ => 'Started on the PC and still running.',
      };
    } on Object catch (e) {
      return 'It failed: $e';
    } finally {
      await sub.cancel();
    }
  }

  static bool _final(HarnessCallStatus s) =>
      s == HarnessCallStatus.done ||
      s == HarnessCallStatus.error ||
      s == HarnessCallStatus.denied;

  static String _cap(String s) =>
      s.length > 3000 ? '${s.substring(0, 3000)} ...' : s;

  List<int> _sse(Map<String, dynamic> delta, {String? finish}) => utf8.encode(
    'data: ${jsonEncode(<String, dynamic>{
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    })}\n\n',
  );
}

class _Turn {
  _Turn({
    required this.provider,
    required this.model,
    this.thinkingModel,
    required this.messages,
    required this.tools,
    required this.clientNames,
    required this.temperature,
    this.userText = '',
  });

  final LlmProvider provider;

  /// The model this turn is on now: the fast one first.
  String model;

  /// Where the turn goes when it has to act. Null: the fast model does all.
  final String? thinkingModel;
  bool get thinking => thinkingModel != null && model == thinkingModel;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> tools;
  late final toolNames = {
    for (final t in tools) '${(t['function'] as Map?)?['name']}',
  };
  final Set<String> clientNames;
  final double temperature;

  /// What the user said this turn, for the memory.
  final String userText;

  /// "open_app {name: Spotify}: Opened Spotify", one per tool call.
  final List<String> actions = [];

  /// The same, as `{name, args, result}` for the memory to replay.
  final List<Map<String, dynamic>> calls = [];

  /// Something was spoken already, the "one moment" included.
  bool said = false;

  /// When the board last heard anything from this turn.
  DateTime lastSign = DateTime.now();

  /// An act ran and nothing looked at the screen after it.
  bool uncheckedAct = false;

  /// Asked once already to check before answering.
  bool nudged = false;
}

class _Call {
  String? id;
  final name = StringBuffer();
  final args = StringBuffer();

  Map<String, dynamic> decodedArgs() {
    try {
      final v = jsonDecode(args.isEmpty ? '{}' : args.toString());
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> toJson(int index) => <String, dynamic>{
    'index': index,
    'id': id ?? 'call_$index',
    'type': 'function',
    'function': <String, dynamic>{
      'name': name.toString(),
      'arguments': args.isEmpty ? '{}' : args.toString(),
    },
  };
}
