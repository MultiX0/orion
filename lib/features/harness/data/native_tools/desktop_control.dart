import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Real control of the desktop, for any app: open a link or an app link
/// (spotify:, ms-settings:, mailto:, https:), bring an app to the front, press
/// keys, type text, and say what is open. Windows only for now, through the
/// shell and WScript, so nothing needs installing. Every result is a short
/// sentence the model can turn into speech.
class DesktopControl {
  DesktopControl({Future<ProcessResult> Function(String, List<String>)? run})
    : _run = run ?? ((exe, args) => Process.run(exe, args));

  final Future<ProcessResult> Function(String exe, List<String> args) _run;

  static bool get isSupported => Platform.isWindows;

  Future<String> openLink(String target) async {
    final t = target.trim();
    if (t.isEmpty) return 'Nothing to open.';
    // start's first quoted argument is a window title, hence the empty one.
    final r = await _run('cmd', <String>['/c', 'start', '', t]);
    if (r.exitCode != 0) {
      return 'Windows could not open that: ${'${r.stderr}'.trim()}';
    }
    return 'Opened $t.';
  }

  Future<String> focusApp(String name) async {
    final ok = await _ps(
      '\$w = New-Object -ComObject WScript.Shell; '
      '\$p = Get-Process | Where-Object { \$_.MainWindowTitle -and '
      "(\$_.ProcessName -like '*${_q(name)}*' -or \$_.MainWindowTitle -like '*${_q(name)}*') } "
      '| Select-Object -First 1; '
      'if (\$p) { [void]\$w.AppActivate(\$p.Id); "ok" } else { "none" }',
    );
    return ok.trim() == 'ok'
        ? 'Brought $name to the front.'
        : 'No open window matches $name.';
  }

  /// Closes every window of an app the way its own close button does, so
  /// one with unsaved work still asks. Every window, not only the first, or
  /// "close Chrome" leaves a second one open. Never Orion itself.
  Future<String> closeApp(String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'No app named.';
    final out = await _ps(_fill(_closeAll, {'APP': n}));
    if (out.contains('NO_WINDOW')) return 'No open window matches $n.';
    final m = RegExp(r'CLOSED (\d+) (.*)').firstMatch(out);
    if (m == null) return 'Windows would not close $n: ${out.trim()}';
    return 'Closed ${m.group(1)} window${m.group(1) == '1' ? '' : 's'} of ${m.group(2)!.trim()}.';
  }

  /// "ctrl+l", "enter", "space", "alt+tab", "ctrl+shift+t", several separated
  /// by commas. Goes to the window in front, so focus_app first.
  Future<String> pressKeys(String keys) async {
    final seq = keys
        .split(',')
        .map((k) => _sendKeys(k.trim()))
        .where((s) => s.isNotEmpty)
        .toList();
    if (seq.isEmpty) return 'No keys given.';
    final out = await _ps(
      '$_notOrion \$w = New-Object -ComObject WScript.Shell; '
      '${seq.map((s) => "\$w.SendKeys('${_q(s)}'); Start-Sleep -Milliseconds 150").join('; ')}; '
      "'ok'; $_frontNow",
    );
    return out.contains('self')
        ? _selfInFront
        : 'Pressed $keys.${_nowLine(out)}';
  }

  Future<String> typeText(String text, {String app = ''}) async {
    if (text.isEmpty) return 'Nothing to type.';
    final out = await _ps(
      '${_fill(_paste, {'TEXT': text, 'APP': app.trim()})}\n$_frontNow',
    );
    if (out.contains('self')) return _selfInFront;
    return 'Typed it${app.trim().isEmpty ? '' : ' into ${app.trim()}'}.'
        '${_nowLine(out)}';
  }

  /// After keys or a paste, what the window in front says: the model's first
  /// check that it worked. Without it, a search typed into Chrome that never
  /// ran gets reported as done.
  static const _frontNow =
      'Start-Sleep -Milliseconds 700; '
      'Add-Type -Namespace O -Name F -MemberDefinition \''
      '[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow(); '
      '[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint p);\'; '
      '\$ff = [uint32]0; [void][O.F]::GetWindowThreadProcessId([O.F]::GetForegroundWindow(), [ref]\$ff); '
      '\$fw = Get-Process -Id \$ff -ErrorAction SilentlyContinue; '
      "if (\$fw) { 'NOW ' + \$fw.ProcessName + ': ' + \$fw.MainWindowTitle }";

  /// " Its window now shows: ..." from a script's NOW line, or nothing.
  static String _nowLine(String out) {
    final now = RegExp(r'NOW (.+)').firstMatch(out)?.group(1)?.trim() ?? '';
    return now.isEmpty || now.endsWith(':')
        ? ''
        : ' The window in front now shows "$now".';
  }

  /// Keys go to whatever window is in front. When that is Orion's own, a
  /// focus_app that did not take would have sent alt+f4 to the app itself.
  static const _notOrion =
      'Add-Type -Namespace O -Name W -MemberDefinition \''
      '[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow(); '
      '[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint p);\'; '
      '\$fp = 0; [void][O.W]::GetWindowThreadProcessId([O.W]::GetForegroundWindow(), [ref]\$fp); '
      "if ((Get-Process -Id \$fp).ProcessName -eq 'orion') { 'self'; return };";

  static const _selfInFront =
      'Orion\'s own window is in front, so no keys were sent. Bring the app '
      'forward with focus_app first.';

  /// The apps with a window, and what each window shows, for the model's
  /// context: "Spotify: Chris Grey - Lifetime".
  Future<List<String>> openWindows() async {
    final out = await _ps(
      'Get-Process | Where-Object { \$_.MainWindowTitle } | '
      'Select-Object ProcessName, MainWindowTitle | ConvertTo-Json -Compress',
    );
    try {
      final decoded = jsonDecode(out.trim().isEmpty ? '[]' : out);
      final list = decoded is List ? decoded : [decoded];
      return [
        for (final w in list.cast<Map<String, dynamic>>())
          '${w['ProcessName']}: ${w['MainWindowTitle']}',
      ];
    } on FormatException {
      return const [];
    }
  }

  /// What an app's window offers, through Windows UI Automation: its buttons,
  /// fields, list items, links, tabs and menu items, by name. This is how the
  /// brain works any app, not only the ones it has a shortcut for: look, then
  /// ui_act on a name it saw.
  Future<String> uiLook(String app) async {
    final a = app.trim();
    if (a.isEmpty) return 'No app named.';
    final script = _fill(_uiaFind + _uiaLook, {'APP': a});
    var out = await _ps(script, timeout: const Duration(seconds: 20));
    if (out.contains('NO_WINDOW')) return 'No open window matches $app.';
    var lines = out.trim().split(RegExp(r'\r?\n'));
    // Chromium apps (Spotify, Chrome, Discord) build their accessibility tree
    // only when first asked, so a first look at Spotify sees one field, and
    // right after a search Spotify shows nothing for a moment. Hence two
    // retries.
    for (final wait in const [800, 1500]) {
      if (lines.length >= 4) break;
      await Future<void>.delayed(Duration(milliseconds: wait));
      out = await _ps(script, timeout: const Duration(seconds: 20));
      lines = out.trim().split(RegExp(r'\r?\n'));
    }
    return lines.length <= 1
        ? '${lines.join()}. Its window shows no named controls.'
        : lines.join('\n');
  }

  /// Does [action] on the control called [target] in [app]'s window:
  /// "click" (press a button, pick a list item, follow a link), "type"
  /// ([text] into a field) or "focus". An exact name first, then a name that
  /// contains it. The pattern the control offers first, a real click in its
  /// middle last.
  Future<String> uiAct(
    String app,
    String target,
    String action, {
    String text = '',
  }) async {
    final a = app.trim();
    // ui_look writes "Button: Play Blinding Lights #2", and a model often
    // hands the whole line back: the kind narrows the search, the number
    // picks among controls of one name, the name is what is left.
    final line = RegExp(
      r'^(?:(Button|Edit|ListItem|MenuItem|Hyperlink|CheckBox|TabItem|ComboBox|DataItem|TreeItem|RadioButton|Text|SplitButton|Document):\s*)?(.*?)(?:\s+#(\d+))?$',
    ).firstMatch(target.trim().replaceAll(RegExp(r'[\x00-\x1f]'), ' '))!;
    final kind = line.group(1) ?? '';
    final t = line.group(2)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    final nth = int.tryParse(line.group(3) ?? '') ?? 1;
    if (a.isEmpty || t.isEmpty) return 'Say which app and which control.';
    final what = action.trim().toLowerCase();
    final out = await _ps(
      _fill(_uiaFind + _uiaAct, {
        'APP': a,
        'TARGET': t,
        'ACTION': what,
        'TEXT': text,
        'KIND': kind,
        'NTH': '$nth',
      }),
      timeout: const Duration(seconds: 20),
    );
    if (out.contains('NO_WINDOW')) return 'No open window matches $app.';
    if (out.contains('NO_CONTROL')) {
      return 'Nothing called $target in $app. ui_look shows what is there.';
    }
    final done = RegExp(r'DONE (.+)').firstMatch(out)?.group(1)?.trim();
    if (done == null) return 'Windows would not do that: ${out.trim()}';
    // The script waits a moment before reading the title: read right after
    // clicking a song's Play, the media status still names the previous song.
    final did = switch (what) {
      'type' => 'Typed into $done.',
      'focus' => 'Focused $done.',
      _ => 'Clicked $done.',
    };
    return '$did${_nowLine(out)}';
  }

  /// Any PowerShell command, for what no other tool does: settings, files,
  /// processes, the volume, anything Windows can do from a prompt. Output is
  /// cut to 3000 characters for the model.
  Future<String> runPowerShell(String command) async {
    final c = command.trim();
    if (c.isEmpty) return 'No command given.';
    final out = await _ps(
      '& { $c } 2>&1 | Out-String -Width 160',
      timeout: const Duration(seconds: 25),
    );
    final text = out.trim();
    if (text.isEmpty) return 'Done, no output.';
    return text.length > 3000 ? '${text.substring(0, 3000)} ...' : text;
  }

  /// {{KEY}} to value, each value quoted for a single quoted PowerShell
  /// string.
  static String _fill(String script, Map<String, String> values) {
    var s = script;
    values.forEach((k, v) => s = s.replaceAll('{{$k}}', _q(v)));
    return s;
  }

  /// The first app window whose process or title matches, never Orion.
  static const _uiaFind = r'''
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$A = [System.Windows.Automation.AutomationElement]
$p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -ne 'orion' -and
  ($_.ProcessName -like '*{{APP}}*' -or $_.MainWindowTitle -like '*{{APP}}*') } | Select-Object -First 1
if (-not $p) { 'NO_WINDOW'; return }
$root = $A::FromHandle($p.MainWindowHandle)
''';

  static const _uiaLook = r'''
$t = [System.Windows.Automation.ControlType]
$kinds = @($t::Button, $t::Edit, $t::ListItem, $t::MenuItem, $t::Hyperlink, $t::CheckBox,
  $t::TabItem, $t::ComboBox, $t::DataItem, $t::TreeItem, $t::RadioButton, $t::Text)
$conds = [System.Windows.Automation.Condition[]]@($kinds | ForEach-Object {
  New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $_) })
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
  (New-Object System.Windows.Automation.OrCondition(,$conds)))
# A button inside a list row gets the row's text first, once: Spotify names
# every version's button "Play Blinding Lights", and only the row says whose
# it is ("Blinding Lights The Weeknd 3:20").
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$labels = New-Object System.Windows.Automation.OrCondition(
  (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $t::Hyperlink)),
  (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $t::Text)))
function RowText($el, $own) {
  $row = $null; $x = $el
  for ($i = 0; $i -lt 3; $i++) {
    $x = $walker.GetParent($x); if (-not $x) { break }
    $k = $x.Current.ControlType
    if ($k -eq $t::DataItem -or $k -eq $t::ListItem) { $row = $x }
  }
  if (-not $row) { return '' }
  $s = $row.Current.Name
  if (-not $s -or $s -eq $own) {
    $s = ($row.FindAll([System.Windows.Automation.TreeScope]::Descendants, $labels) |
      ForEach-Object { $_.Current.Name } | Where-Object { $_ -and $_ -ne $own } |
      Select-Object -Unique -First 4) -join ', '
  }
  if ($s.Length -gt 110) { $s = $s.Substring(0, 110) }
  $s
}
$seen = @{}; $n = 0; $lastRow = ''
foreach ($e in $all) {
  $c = $e.Current
  if (-not $c.Name -or $c.IsOffscreen) { continue }
  # Text is what a display or a label says ("Display is 5,888"); long runs of
  # it are page prose, not controls.
  if ($c.ControlType -eq $t::Text -and $c.Name.Length -gt 80) { continue }
  $line = $c.ControlType.ProgrammaticName.Replace('ControlType.', '') + ': ' + $c.Name
  # Spotify has a "Play Blinding Lights" button for every version of the
  # song; the second is written "#2", so the model can pick it.
  # A repeated row cell or label is the same thing nested again: skipped.
  $seen[$line] = 1 + [int]$seen[$line]
  if ($seen[$line] -gt 1) {
    if ($c.ControlType -eq $t::DataItem -or $c.ControlType -eq $t::Text) { continue }
    $line = $line + ' #' + $seen[$line]
  }
  if ($c.ControlType -eq $t::Button) {
    $r = RowText $e $c.Name
    if ($r -and $r -ne $lastRow) { 'Row: ' + $r; $n++ }
    if ($r) { $lastRow = $r }
  }
  $line; $n++
  if ($n -ge 160) { break }
}
'WINDOW: ' + $p.MainWindowTitle
''';

  static const _uiaAct = r'''
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition)
# Several controls often share a name: in Spotify a result row and its Play
# button are both "Play Blinding Lights", and selecting the row plays
# nothing. Clicks go to the most clickable one, typing to a field.
$click = @('Button', 'MenuItem', 'Hyperlink', 'TabItem', 'CheckBox', 'RadioButton', 'SplitButton', 'ListItem', 'TreeItem', 'DataItem')
$field = @('Edit', 'ComboBox', 'Document')
function Rank($el) {
  $k = $el.Current.ControlType.ProgrammaticName.Replace('ControlType.', '')
  $order = if ('{{ACTION}}' -eq 'type') { $field } else { $click }
  $i = [array]::IndexOf($order, $k); if ($i -lt 0) { 99 } else { $i }
}
# The best kind, then the first of it in the window's order: that is the
# one ui_look wrote without a number, and "#2" is the next.
function Pick($m) {
  $m = @($m)
  if ('{{KIND}}') { $m = @($m | Where-Object { $_.Current.ControlType.ProgrammaticName -eq 'ControlType.{{KIND}}' }) }
  if (-not $m.Count) { return $null }
  $best = ($m | ForEach-Object { Rank $_ } | Measure-Object -Minimum).Minimum
  $m = @($m | Where-Object { (Rank $_) -eq $best })
  $nth = {{NTH}}
  if ($m.Count -ge $nth) { $m[$nth - 1] } else { $null }
}
$e = Pick ($all | Where-Object { $_.Current.Name -eq '{{TARGET}}' -and -not $_.Current.IsOffscreen })
if (-not $e) { $e = Pick ($all | Where-Object { $_.Current.Name -like '*{{TARGET}}*' -and -not $_.Current.IsOffscreen }) }
if (-not $e) { 'NO_CONTROL'; return }
Add-Type -Namespace O -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
'@
[void][O.U]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 150
$act = '{{ACTION}}'; $text = '{{TEXT}}'; $done = $false
if ($act -eq 'type') {
  try { $e.SetFocus(); $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($text); $done = $true } catch { }
  if (-not $done) { $e.SetFocus(); $old = $null; try { $old = Get-Clipboard -Raw -ErrorAction Stop } catch { }; Set-Clipboard -Value $text; (New-Object -ComObject WScript.Shell).SendKeys('^v'); Start-Sleep -Milliseconds 300; if ($old) { Set-Clipboard -Value $old }; $done = $true }
} elseif ($act -eq 'focus') {
  $e.SetFocus(); $done = $true
} else {
  try { $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $done = $true } catch { }
  if (-not $done) { try { $e.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $done = $true } catch { } }
  if (-not $done) { try { $e.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle(); $done = $true } catch { } }
  if (-not $done) {
    $r = $e.Current.BoundingRectangle
    [void][O.U]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
    [O.U]::mouse_event(2, 0, 0, 0, 0); [O.U]::mouse_event(4, 0, 0, 0, 0); $done = $true
  }
}
'DONE ' + $e.Current.ControlType.ProgrammaticName.Replace('ControlType.', '') + ': ' + $e.Current.Name
# The app takes a moment to act on it; then its title is the first check:
# Spotify's names the song that plays, Chrome's the page.
Start-Sleep -Milliseconds 700
$p.Refresh(); 'NOW ' + $p.ProcessName + ': ' + $p.MainWindowTitle
''';

  /// Play, pause, next, previous or status through Windows' own media
  /// session (what the volume flyout shows), for whatever app is playing:
  /// Spotify, a YouTube tab, anything. The media keys only toggle, so
  /// "pause" on something already paused would start it again. Null when no
  /// app has a media session, for the caller to fall back to the keys.
  Future<String?> media(String action) async {
    final out = await _ps(
      _fill(_gsmtc, {'ACTION': action.trim().toLowerCase()}),
      timeout: const Duration(seconds: 10),
    );
    final m = RegExp(r'MEDIA (\w+) \| (.*) \| (.*) \| (.*)').firstMatch(out);
    if (m == null) return null;
    final state = m.group(1)!;
    final title = m.group(2)!.trim();
    final artist = m.group(3)!.trim();
    final app = m.group(4)!.trim().split('.').first.split('!').first;
    final what = [
      title,
      if (artist.isNotEmpty) 'by $artist',
    ].where((s) => s.isNotEmpty).join(' ');
    return '${state == 'Playing' ? 'Playing' : 'Paused'}'
        '${what.isEmpty ? '' : ': $what'}${app.isEmpty ? '' : ' in $app'}.';
  }

  /// Waits for a window of [app] to appear, so what comes next does not
  /// land on whatever was in front while it was starting.
  Future<bool> waitForWindow(
    String app, {
    Duration within = const Duration(seconds: 8),
  }) async {
    final a = app.trim().toLowerCase();
    final until = DateTime.now().add(within);
    while (DateTime.now().isBefore(until)) {
      final open = await openWindows();
      if (open.any((w) => w.toLowerCase().contains(a))) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  static const _gsmtc = r'''
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
}
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$s = $mgr.GetCurrentSession()
if (-not $s) { 'NO_SESSION'; return }
$act = '{{ACTION}}'
$state = $s.GetPlaybackInfo().PlaybackStatus.ToString()
switch ($act) {
  'play' { if ($state -ne 'Playing') { [void](Await ($s.TryPlayAsync()) ([bool])) } }
  'pause' { if ($state -eq 'Playing') { [void](Await ($s.TryPauseAsync()) ([bool])) } }
  'play_pause' { [void](Await ($s.TryTogglePlayPauseAsync()) ([bool])) }
  'next' { [void](Await ($s.TrySkipNextAsync()) ([bool])) }
  'previous' { [void](Await ($s.TrySkipPreviousAsync()) ([bool])) }
}
if ($act -ne 'status') { Start-Sleep -Milliseconds 700 }
$p = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
'MEDIA ' + $s.GetPlaybackInfo().PlaybackStatus + ' | ' + $p.Title + ' | ' + $p.Artist + ' | ' + $s.SourceAppUserModelId
''';

  /// Every window of the app, by process name first, then by window title,
  /// never Orion. WM_CLOSE, as the close button sends it.
  static const _closeAll = r'''
Add-Type -Namespace O -Name C -MemberDefinition @'
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, System.IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint p);
[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint m, System.IntPtr w, System.IntPtr l);
[DllImport("user32.dll")] public static extern int GetWindowTextLength(System.IntPtr h);
'@
$procs = @(Get-Process | Where-Object { $_.ProcessName -ne 'orion' -and $_.ProcessName -like '*{{APP}}*' })
if (-not $procs) { $procs = @(Get-Process | Where-Object { $_.ProcessName -ne 'orion' -and $_.MainWindowTitle -like '*{{APP}}*' }) }
if (-not $procs) { 'NO_WINDOW'; return }
$ids = $procs | ForEach-Object { [uint32]$_.Id }
$script:n = 0
$cb = [O.C+EnumProc] { param($h, $l)
  $p = [uint32]0; [void][O.C]::GetWindowThreadProcessId($h, [ref]$p)
  if ($ids -contains $p -and [O.C]::IsWindowVisible($h) -and [O.C]::GetWindowTextLength($h) -gt 0) {
    [void][O.C]::PostMessage($h, 0x0010, [System.IntPtr]::Zero, [System.IntPtr]::Zero); $script:n++
  }
  $true }
[void][O.C]::EnumWindows($cb, [System.IntPtr]::Zero)
'CLOSED ' + $script:n + ' ' + (($procs | Select-Object -ExpandProperty ProcessName -Unique) -join ', ')
''';

  /// Types by pasting: any language, any length. SendKeys drops or mangles
  /// Arabic. The clipboard is put back after. [app], when given, is
  /// brought to the front first.
  static const _paste = r'''
$old = $null; try { $old = Get-Clipboard -Raw -ErrorAction Stop } catch { }
Set-Clipboard -Value '{{TEXT}}'
Add-Type -Namespace O -Name P -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint p);
[DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, int f, int e);
'@
$app = '{{APP}}'
if ($app) {
  $w = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -ne 'orion' -and
    ($_.ProcessName -like "*$app*" -or $_.MainWindowTitle -like "*$app*") } | Select-Object -First 1
  if ($w) { [O.P]::keybd_event(0x12, 0, 0, 0); [O.P]::keybd_event(0x12, 0, 2, 0); [void][O.P]::SetForegroundWindow($w.MainWindowHandle); Start-Sleep -Milliseconds 300 }
}
$fp = [uint32]0; [void][O.P]::GetWindowThreadProcessId([O.P]::GetForegroundWindow(), [ref]$fp)
if ((Get-Process -Id $fp).ProcessName -eq 'orion') { 'self' }
else { (New-Object -ComObject WScript.Shell).SendKeys('^v'); Start-Sleep -Milliseconds 400; 'ok' }
if ($old) { Set-Clipboard -Value $old }
''';

  Future<String> _ps(
    String script, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final r = await _run('powershell', <String>[
        '-NoProfile',
        '-Command',
        script,
      ]).timeout(timeout);
      return '${r.stdout}${r.stderr}';
    } on TimeoutException {
      return 'It took longer than ${timeout.inSeconds} s and was left running.';
    }
  }

  static String _q(String s) => s.replaceAll("'", "''");

  static const _named = <String, String>{
    'enter': '{ENTER}',
    'return': '{ENTER}',
    'space': ' ',
    'tab': '{TAB}',
    'escape': '{ESC}',
    'esc': '{ESC}',
    'backspace': '{BACKSPACE}',
    'delete': '{DELETE}',
    'up': '{UP}',
    'down': '{DOWN}',
    'left': '{LEFT}',
    'right': '{RIGHT}',
    'home': '{HOME}',
    'end': '{END}',
    'pageup': '{PGUP}',
    'pagedown': '{PGDN}',
    'f5': '{F5}',
    'f11': '{F11}',
  };

  /// "ctrl+shift+t" to SendKeys' "^+t".
  static String _sendKeys(String combo) {
    final parts = combo.toLowerCase().split('+').map((p) => p.trim()).toList();
    if (parts.isEmpty || parts.last.isEmpty) return '';
    final mods = StringBuffer();
    for (final m in parts.take(parts.length - 1)) {
      mods.write(switch (m) {
        'ctrl' || 'control' => '^',
        'shift' => '+',
        'alt' => '%',
        _ => '',
      });
    }
    final key = parts.last;
    final named = _named[key];
    if (named != null || key.length == 1) return '$mods${named ?? key}';
    // Not a key name: typed as it is, "128*46=" into a calculator, with the
    // characters SendKeys reads as commands braced.
    if (mods.isNotEmpty) return '';
    return combo.replaceAllMapped(
      RegExp(r'[+^%~(){}\[\]]'),
      (m) => '{${m[0]}}',
    );
  }
}
