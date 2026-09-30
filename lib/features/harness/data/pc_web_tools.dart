import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Web search and page reading for the PC brain, with no API key: DuckDuckGo's
/// HTML results page, Wikipedia's search API when that comes back empty, and a
/// plain GET with the markup stripped for reading one page.
class PcWebTools {
  PcWebTools({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  static const _agent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36 Orion/1.0';

  static const searchName = 'web_search';
  static const fetchName = 'fetch_page';
  static const weatherName = 'weather';

  /// OpenAI function definitions, next to the PC's own tools.
  static final List<Map<String, dynamic>> specs = [
    _fn(
      searchName,
      'Search the web. Use it for anything current or that you are not sure '
      'of: news, weather, prices, scores, opening hours, facts after your '
      'training, people, places.',
      {'query': 'what to search for, in the language that finds it best'},
    ),
    _fn(
      fetchName,
      'Read one web page as plain text, usually a result from web_search.',
      {'url': 'the full http or https address'},
    ),
    _fn(
      weatherName,
      'The weather now and for the next two days, from Open-Meteo. Use it for '
      'any weather question instead of web_search.',
      {
        'place':
            'the city in English letters, like Amman or Irbid; empty for '
            'where this device is',
      },
    ),
  ];

  static Map<String, dynamic> _fn(
    String name,
    String description,
    Map<String, String> args,
  ) => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': {
          for (final e in args.entries)
            e.key: {'type': 'string', 'description': e.value},
        },
        'required': args.keys.toList(),
      },
    },
  };

  Future<String> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return 'No query given.';
    try {
      final html = await _get(
        Uri.https('html.duckduckgo.com', '/html/', {'q': q}),
      );
      final hits = _duckHits(html);
      if (hits.isNotEmpty) return hits.join('\n');
    } on Object {
      // Falls through to Brave.
    }
    // DuckDuckGo answers a burst of automated searches with a challenge page
    // and no results; Brave's page still has them.
    try {
      final html = await _get(
        Uri.https('search.brave.com', '/search', {'q': q}),
      );
      final hits = _braveHits(html);
      if (hits.isNotEmpty) return hits.join('\n');
    } on Object {
      // Falls through to Wikipedia.
    }
    return _wikipedia(q);
  }

  /// Open-Meteo needs no key and answers in about a second. The weather
  /// through a throttled search engine can come back empty after 17 s.
  Future<String> weather(String place) async {
    try {
      final at = await _where(place.trim());
      if (at == null) return 'I could not find a place called $place.';
      final (name, lat, lon) = at;
      final json =
          jsonDecode(
                await _get(
                  Uri.https('api.open-meteo.com', '/v1/forecast', {
                    'latitude': '$lat',
                    'longitude': '$lon',
                    'current':
                        'temperature_2m,apparent_temperature,weather_code,'
                        'wind_speed_10m,relative_humidity_2m',
                    'daily':
                        'temperature_2m_max,temperature_2m_min,'
                        'precipitation_probability_max,weather_code',
                    'timezone': 'auto',
                    'forecast_days': '3',
                  }),
                ),
              )
              as Map<String, dynamic>;
      final now = json['current'] as Map<String, dynamic>;
      final day = json['daily'] as Map<String, dynamic>;
      String at0(String k, int i) => '${(day[k] as List)[i]}';
      final days = <String>[];
      for (final (i, label) in ['Today', 'Tomorrow', 'The day after'].indexed) {
        days.add(
          '$label: ${_sky(int.tryParse(at0('weather_code', i)) ?? 0)}, high '
          '${at0('temperature_2m_max', i)} C, low ${at0('temperature_2m_min', i)} C, '
          'chance of rain ${at0('precipitation_probability_max', i)} percent.',
        );
      }
      return '$name now: ${now['temperature_2m']} C, feels like '
          '${now['apparent_temperature']} C, ${_sky(now['weather_code'] as int? ?? 0)}, '
          'humidity ${now['relative_humidity_2m']} percent, wind '
          '${now['wind_speed_10m']} km/h. ${days.join(' ')}';
    } on Object catch (e) {
      return 'The weather service did not answer: $e';
    }
  }

  /// A named place through Open-Meteo's geocoder, or this device's own
  /// place by its public address when none is named.
  Future<(String, double, double)?> _where(String place) async {
    if (place.isEmpty) {
      final me =
          jsonDecode(await _get(Uri.http('ip-api.com', '/json')))
              as Map<String, dynamic>;
      if (me['status'] != 'success') return null;
      return (
        '${me['city']}',
        (me['lat'] as num).toDouble(),
        (me['lon'] as num).toDouble(),
      );
    }
    final found =
        jsonDecode(
              await _get(
                Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
                  'name': place,
                  'count': '1',
                  'language': 'en',
                }),
              ),
            )
            as Map<String, dynamic>;
    final hits = (found['results'] as List?) ?? const [];
    if (hits.isEmpty) return null;
    final hit = hits.first as Map<String, dynamic>;
    return (
      '${hit['name']}, ${hit['country'] ?? ''}',
      (hit['latitude'] as num).toDouble(),
      (hit['longitude'] as num).toDouble(),
    );
  }

  /// WMO weather codes, in words.
  static String _sky(int code) => switch (code) {
    0 => 'clear sky',
    1 || 2 => 'partly cloudy',
    3 => 'overcast',
    45 || 48 => 'fog',
    51 || 53 || 55 || 56 || 57 => 'drizzle',
    61 || 63 || 65 || 66 || 67 => 'rain',
    71 || 73 || 75 || 77 => 'snow',
    80 || 81 || 82 => 'rain showers',
    85 || 86 => 'snow showers',
    95 || 96 || 99 => 'thunderstorm',
    _ => 'mixed weather',
  };

  Future<String> fetch(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'That is not a web address.';
    }
    try {
      final text = _plain(await _get(uri));
      return text.length > 4000 ? '${text.substring(0, 4000)} ...' : text;
    } on Object catch (e) {
      return 'Could not read the page: $e';
    }
  }

  List<String> _duckHits(String html) {
    final links = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(html).toList();
    final snippets = RegExp(
      r'class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    ).allMatches(html).map((m) => _plain(m.group(1)!)).toList();
    final hits = <String>[];
    for (var i = 0; i < links.length && hits.length < 5; i++) {
      final title = _plain(links[i].group(2)!);
      final snippet = i < snippets.length ? snippets[i] : '';
      hits.add(
        '${hits.length + 1}. $title: $snippet (${_target(links[i].group(1)!)})',
      );
    }
    return hits;
  }

  List<String> _braveHits(String html) {
    final hits = <String>[];
    for (final block in html.split('<div class="snippet svelte').skip(1)) {
      final b = block.length > 3000 ? block.substring(0, 3000) : block;
      final href = RegExp(r'<a href="(https?://[^"]+)"').firstMatch(b);
      final title = RegExp(
        r'class="title[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(b);
      if (href == null || title == null) continue;
      final desc = RegExp(
        r'class="(?:snippet-description|content)[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(b);
      hits.add(
        '${hits.length + 1}. ${_plain(title.group(1)!)}: '
        '${desc == null ? '' : _plain(desc.group(1)!)} (${href.group(1)})',
      );
      if (hits.length == 5) break;
    }
    return hits;
  }

  /// DuckDuckGo wraps each result in a redirect with the real address in uddg.
  String _target(String href) {
    final uri = Uri.tryParse(href.startsWith('//') ? 'https:$href' : href);
    return uri?.queryParameters['uddg'] ?? href;
  }

  Future<String> _wikipedia(String q) async {
    final arabic = RegExp(r'[؀-ۿ]').hasMatch(q);
    final host = arabic ? 'ar.wikipedia.org' : 'en.wikipedia.org';
    try {
      final body = await _get(
        Uri.https(host, '/w/api.php', {
          'action': 'query',
          'list': 'search',
          'srsearch': q,
          'srlimit': '3',
          'format': 'json',
        }),
      );
      final query = (jsonDecode(body) as Map<String, dynamic>)['query'];
      final results = query is Map<String, dynamic>
          ? (query['search'] as List? ?? const []).cast<Map<String, dynamic>>()
          : const <Map<String, dynamic>>[];
      if (results.isEmpty) return 'No results found.';
      return results
          .map((r) => '${r['title']}: ${_plain('${r['snippet']}')}')
          .join('\n');
    } on Object catch (e) {
      return 'The search did not work: $e';
    }
  }

  Future<String> _get(Uri uri) async {
    final req = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
    req.headers.set(HttpHeaders.userAgentHeader, _agent);
    req.headers.set(HttpHeaders.acceptLanguageHeader, 'ar,en;q=0.8');
    final resp = await req.close().timeout(const Duration(seconds: 10));
    if (resp.statusCode >= 400) throw HttpException('HTTP ${resp.statusCode}');
    return resp
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(const Duration(seconds: 10));
  }

  static String _plain(String html) => html
      .replaceAll(
        RegExp(r'<(script|style|noscript)[^>]*>.*?</\1>', dotAll: true),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
