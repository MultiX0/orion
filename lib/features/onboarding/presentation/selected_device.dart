import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../device/domain/device.dart';

part 'selected_device.g.dart';

/// The board the user tapped on the discover step, so the pair route can
/// find its host. The route only carries the id.
@Riverpod(keepAlive: true)
class SelectedDevice extends _$SelectedDevice {
  @override
  Device? build() => null;

  void set(Device? device) => state = device;
}
