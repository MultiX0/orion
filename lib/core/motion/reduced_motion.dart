import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../storage/storage_providers.dart';

part 'reduced_motion.g.dart';

/// The app-side switch. The OS switch is read from MediaQuery, see below.
@Riverpod(keepAlive: true)
bool reducedMotionSetting(Ref ref) => ref.watch(
  appSettingsProvider.select((s) => s.value?.reducedMotion ?? false),
);

/// True when either the OS or the app asks for less motion. Entrances cut
/// to zero; the orb slows down instead, it never freezes.
bool isMotionReduced(BuildContext context, WidgetRef ref) =>
    MediaQuery.disableAnimationsOf(context) ||
    ref.watch(reducedMotionSettingProvider);
