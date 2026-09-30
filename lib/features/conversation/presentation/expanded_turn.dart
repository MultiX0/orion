import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'expanded_turn.g.dart';

/// Which turn shows its timings and raw tool results. One at a time.
@riverpod
class ExpandedTurn extends _$ExpandedTurn {
  @override
  String? build() => null;

  void toggle(String turnId) => state = state == turnId ? null : turnId;
}
