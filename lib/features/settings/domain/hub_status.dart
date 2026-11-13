import 'package:freezed_annotation/freezed_annotation.dart';

part 'hub_status.freezed.dart';

/// The board's Orion Hub client, as GET /api/hub reports it. The board finds
/// hubs and pairs by itself; the app asks and watches.
@freezed
abstract class HubStatus with _$HubStatus {
  const HubStatus._();

  const factory HubStatus({
    /// none, scanning, found, pairing, waiting, connected, offline, failed.
    required String state,
    @Default(false) bool paired,
    String? name,
    String? url,

    /// While waiting: the four digits the hub's owner approves.
    String? code,
    String? message,
    @Default(<FoundHub>[]) List<FoundHub> found,
  }) = _HubStatus;

  factory HubStatus.fromBoard(Map<String, dynamic> j) => HubStatus(
    state: j['state'] as String? ?? 'none',
    paired: j['paired'] as bool? ?? false,
    name: j['name'] as String?,
    url: j['url'] as String?,
    code: j['code'] as String?,
    message: j['message'] as String?,
    found: [
      for (final h in (j['found'] as List<dynamic>? ?? const []))
        if (h is Map<String, dynamic> && h['url'] is String)
          FoundHub(
            name: h['name'] as String? ?? 'Orion Hub',
            url: h['url'] as String,
          ),
    ],
  );

  /// Something is happening that the next poll will change.
  bool get busy =>
      state == 'scanning' || state == 'pairing' || state == 'waiting';

  /// "192.168.1.5:8780", without the scheme.
  String? get address => url?.replaceFirst(RegExp(r'^\w+://'), '');
}

@freezed
abstract class FoundHub with _$FoundHub {
  const factory FoundHub({required String name, required String url}) =
      _FoundHub;
}
