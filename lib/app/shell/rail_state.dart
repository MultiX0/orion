import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'rail_state.g.dart';

/// Whether the desktop rail is folded to icons only. Session only.
@Riverpod(keepAlive: true)
class RailCollapsed extends _$RailCollapsed {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
