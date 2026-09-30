import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mono_label.dart';
import '../../conversation/data/live_turn_notifier.dart';
import 'camera_stats.dart';
import 'camera_ui_notifier.dart';

/// fps and resolution, top left, in the machine voice.
class CameraStatsOverlay extends ConsumerWidget {
  const CameraStatsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(cameraStatsProvider);
    final res = stats.width == null ? '' : '${stats.width}x${stats.height}';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xs,
        vertical: Space.xxs,
      ),
      decoration: BoxDecoration(
        color: OrionColors.bgPrimary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(OrionRadius.xs),
      ),
      child: MonoLabel(
        '${stats.fps} fps${res.isEmpty ? '' : ' · $res'}',
        color: OrionColors.textMuted,
        live: stats.fps > 0,
      ),
    );
  }
}

/// The reply to "Ask about this", as a bubble over the picture.
class CameraReplyBubble extends ConsumerWidget {
  const CameraReplyBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final askTurnId = ref.watch(cameraUiProvider.select((s) => s.askTurnId));
    final turn = ref.watch(
      liveTurnProvider.select(
        (t) => t?.turnId == askTurnId ? (t?.reply, t?.isDone ?? false) : null,
      ),
    );
    final show = askTurnId != null && turn != null;
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.ease,
      child: !show
          ? const SizedBox.shrink()
          : GestureDetector(
              key: ValueKey(askTurnId),
              onTap: ref.read(cameraUiProvider.notifier).dismissReply,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: OrionColors.bgCardElevated.withValues(alpha: 0.92),
                  border: Border.all(color: OrionColors.borderCyan),
                  borderRadius: BorderRadius.circular(OrionRadius.card),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel.eyebrow(
                      turn.$2 ? 'Orion' : 'Orion is looking',
                      live: !turn.$2,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      turn.$1 ?? 'Reading the frame.',
                      style: context.text.lead.copyWith(
                        color: OrionColors.textWhite,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A short white flash when the shutter fires, then the snapshot thumb.
class SnapshotThumb extends ConsumerWidget {
  const SnapshotThumb({super.key});

  final double _size = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(cameraUiProvider.select((s) => s.snapshot));
    if (snapshot == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      key: ValueKey(snapshot.receivedAt),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.slow,
      curve: Motion.ease,
      builder: (context, v, child) => Transform.scale(
        scale: 0.9 + 0.1 * v,
        child: Opacity(opacity: v, child: child),
      ),
      child: Container(
        width: _size,
        height: _size * 0.75,
        decoration: BoxDecoration(
          border: Border.all(color: OrionColors.borderSoft),
          borderRadius: BorderRadius.circular(OrionRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(snapshot.bytes, fit: BoxFit.cover),
      ),
    );
  }
}
