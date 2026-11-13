import 'dart:math';

/// Orion Link (docs/ORION_LINK.md): every node in the Orion ecosystem has a
/// permanent id and answers `GET /.well-known/orion` with who it is, without
/// a token. An address is only a hint: a node is found again by its id when
/// its address changes.
abstract final class OrionLink {
  static const version = 1;
  static const wellKnownPath = '/.well-known/orion';

  /// The UDP port every node's presence beacon goes to.
  static const beaconPort = 7332;

  /// What a node is. Boards say `board`, hubs `hub`.
  static const kindPc = 'pc';
  static const kindPhone = 'phone';
  static const kindBoard = 'board';
  static const kindHub = 'hub';

  static final _idRe = RegExp(r'^(pc|phone)-[0-9a-f]{12}$');

  /// A new id for this install: `pc-` or `phone-` and 12 hex digits.
  static String newId(String kind, [Random? random]) {
    final r = random ?? Random.secure();
    final hex = List<String>.generate(
      12,
      (_) => r.nextInt(16).toRadixString(16),
    ).join();
    return '$kind-$hex';
  }

  /// True for an id this app made (and so may keep).
  static bool isAppId(String? id) => id != null && _idRe.hasMatch(id);

  /// What a node answers at [wellKnownPath].
  static Map<String, dynamic> identity({
    required String id,
    required String kind,
    required String name,
    required int port,
    required String appVersion,
  }) => <String, dynamic>{
    'orion': version,
    'id': id,
    'kind': kind,
    'name': name,
    'port': port,
    'version': appVersion,
  };
}
