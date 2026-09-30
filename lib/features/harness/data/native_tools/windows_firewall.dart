import 'dart:convert';
import 'dart:io';

/// Lets the board reach this PC's tool server through Windows Defender
/// Firewall, with Windows' own consent prompt instead of commands to paste.
///
/// A firewall prompt dismissed once leaves a Block rule on the executable, a
/// block rule beats any allow rule, and a home network marked Public shows no
/// prompt again. So the app checks for its rule
/// and, when missing, asks Windows to run the fix elevated: one "Do you want to
/// allow this app to make changes" prompt, then nothing to remember.
abstract final class WindowsFirewall {
  static const ruleName = 'Orion PC brain';

  /// The ports the rule opens: the tool server's own and the ones it moves
  /// to when that one is busy.
  static const ports = '7331-7339';

  /// True when an enabled allow rule opens [port]. Reading rules needs no
  /// admin. A rule that opens 7331 alone looks fine and still blocks a
  /// server that moved to 7332.
  static Future<bool> isAllowed(int port) async {
    final result = await Process.run('powershell', <String>[
      '-NoProfile',
      '-Command',
      "Get-NetFirewallRule -DisplayName '$ruleName' -ErrorAction SilentlyContinue "
          "| Where-Object { \$_.Enabled -eq 'True' -and \$_.Action -eq 'Allow' } "
          '| Get-NetFirewallPortFilter | ForEach-Object { \$_.LocalPort }',
    ]);
    for (final line in '${result.stdout}'.split(RegExp(r'\s+'))) {
      final range = line.trim().split('-');
      final lo = int.tryParse(range.first);
      final hi = int.tryParse(range.last);
      if (lo != null && hi != null && port >= lo && port <= hi) return true;
    }
    return false;
  }

  /// Shows the Windows consent prompt. On Yes: removes Block rules on this
  /// executable, then allows [port] from the local network only (the tool
  /// server still wants the pairing token). False when the user says No.
  static Future<bool> allow(int port) async {
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final script = [
      "Get-NetFirewallApplicationFilter -Program '$exe' -ErrorAction SilentlyContinue "
          '| Get-NetFirewallRule | Where-Object Action -eq Block | Remove-NetFirewallRule',
      "Get-NetFirewallRule -DisplayName '$ruleName' -ErrorAction SilentlyContinue "
          '| Remove-NetFirewallRule',
      "New-NetFirewallRule -DisplayName '$ruleName' -Direction Inbound -Protocol TCP "
          '-LocalPort $ports -RemoteAddress LocalSubnet -Action Allow -Profile Any | Out-Null',
    ].join('; ');
    final result = await Process.run('powershell', <String>[
      '-NoProfile',
      '-Command',
      'try { Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden '
          "-ArgumentList '-NoProfile','-EncodedCommand','${_encoded(script)}'; exit 0 } "
          'catch { exit 1 }',
    ]);
    if (result.exitCode != 0) return false;
    return isAllowed(port);
  }

  /// -EncodedCommand takes base64 of UTF-16LE, which also spares the quoting.
  static String _encoded(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    return base64.encode(bytes);
  }
}
