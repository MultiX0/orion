import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/platform/platform_info.dart';
import '../../../core/result.dart';
import '../../../core/storage/storage_providers.dart';
import '../../device/data/device_providers.dart';
import '../../device/domain/device_config.dart';
import '../../device/domain/pc_config.dart';
import '../data/harness_providers.dart';
import '../domain/approval_mode.dart';

part 'approval_choice.freezed.dart';
part 'approval_choice.g.dart';

/// The three things a user can pick. Off is PC control off; the other two
/// are the two ApprovalModes with PC control on.
enum ApprovalChoice { off, ask, auto }

extension ApprovalChoiceCopy on ApprovalChoice {
  String get title => switch (this) {
    ApprovalChoice.off => 'Off',
    ApprovalChoice.ask => 'Ask me first',
    ApprovalChoice.auto => 'Act on your own',
  };

  /// One honest sentence each.
  String get sentence => switch (this) {
    ApprovalChoice.off =>
      'Orion keeps its hands off the PC. No tool server, nothing offered '
          'to the board.',
    ApprovalChoice.ask =>
      'Safe tools run at once. Anything that changes the PC waits for '
          'your yes.',
    ApprovalChoice.auto =>
      'Every tool runs the moment it arrives, agent tasks included. '
          'Nothing is asked.',
  };

  ApprovalMode? get mode => switch (this) {
    ApprovalChoice.off => null,
    ApprovalChoice.ask => ApprovalMode.ask,
    ApprovalChoice.auto => ApprovalMode.auto,
  };
}

/// What the control shows. On a desktop the live harness status is the
/// truth; on a phone the board's pc block is, with the local copy of the
/// mode when the board is away.
@riverpod
ApprovalChoice approvalChoice(Ref ref) {
  final local = ref.watch(approvalModeProvider);
  final bool enabled;
  final ApprovalMode mode;
  if (ref.watch(platformInfoProvider).canHostHarness) {
    final status = ref.watch(harnessStatusProvider).value;
    enabled =
        status?.isEnabled ??
        ref.watch(
          appSettingsProvider.select((s) => s.value?.harnessEnabled ?? false),
        );
    mode = status?.approvalMode ?? local;
  } else {
    final pc = ref.watch(deviceConfigProvider).value?.pc;
    enabled = pc?.enabled ?? false;
    mode = pc?.approval ?? local;
  }
  if (!enabled) return ApprovalChoice.off;
  return mode == ApprovalMode.auto ? ApprovalChoice.auto : ApprovalChoice.ask;
}

@freezed
abstract class ApprovalSetState with _$ApprovalSetState {
  const factory ApprovalSetState({
    /// The choice being written, while it is.
    ApprovalChoice? busy,
    String? error,
  }) = _ApprovalSetState;
}

/// Writes a choice. Desktop: through the harness repository, which starts
/// or stops the server and tells the board. Phone: straight to the board's
/// pc block, since the phone hosts no harness. Both keep the local copy.
/// Kept alive so a write survives its card scrolling out of a list.
@Riverpod(keepAlive: true)
class ApprovalSetter extends _$ApprovalSetter {
  @override
  ApprovalSetState build() => const ApprovalSetState();

  Future<void> set(ApprovalChoice choice) async {
    state = ApprovalSetState(busy: choice);
    final result = ref.read(platformInfoProvider).canHostHarness
        ? await _onDesktop(choice)
        : await _onPhone(choice);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => const ApprovalSetState(),
      Err(:final failure) => ApprovalSetState(error: failure.message),
    };
  }

  Future<Result<void>> _onDesktop(ApprovalChoice choice) async {
    final repo = ref.read(harnessRepositoryProvider);
    final settings = ref.read(appSettingsProvider.notifier);
    final mode = choice.mode;
    if (mode == null) {
      await settings.setHarnessEnabled(false);
      return repo.setEnabled(false);
    }
    final current = ref.read(approvalChoiceProvider);
    if (current == ApprovalChoice.off) {
      final on = await repo.setEnabled(true);
      if (on.isErr) return on;
    }
    await settings.setHarnessEnabled(true);
    await settings.setApprovalMode(mode);
    return repo.setApprovalMode(mode);
  }

  Future<Result<void>> _onPhone(ApprovalChoice choice) async {
    final mode = choice.mode;
    if (mode != null) {
      await ref.read(appSettingsProvider.notifier).setApprovalMode(mode);
    }
    final patch = DeviceConfig(
      pc: PcConfig(enabled: mode != null, approval: mode),
    );
    final result = await ref.read(deviceClientProvider).updateConfig(patch);
    // Stay busy until the board's config is back, so the control never
    // shows the old choice for a frame between the write and the reload.
    if (result.isOk && ref.mounted) {
      ref.invalidate(deviceConfigProvider);
      try {
        await ref.read(deviceConfigProvider.future);
      } on Object {
        // The control falls back to the local copy; nothing to do here.
      }
    }
    return result.map((_) {});
  }
}
