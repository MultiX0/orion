import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_info.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/orion_app_bar.dart';
import '../../../core/widgets/orion_card.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_mode.dart';
import 'camera_controls.dart';
import 'camera_overlays.dart';
import 'camera_view.dart';

/// Live picture with stats, shutter and "ask about this". The stream
/// opens with this screen and closes when it leaves the tree, because
/// cameraFramesProvider auto-disposes.
class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = ref.watch(platformInfoProvider).isDesktop;
    final offline = ref.watch(deviceModeProvider) == DeviceMode.offline;
    final body = offline
        ? const EmptyState(
            label: '// Offline',
            title: 'No picture without a link',
            emphasis: 'link',
            body: 'The camera streams from the board. It returns with it.',
          )
        : const _Stage();
    return SafeArea(
      child: Column(
        children: [
          const OrionAppBar(
            label: '// Camera',
            title: 'What Orion sees',
            emphasis: 'sees',
          ),
          Expanded(
            child: isDesktop
                ? _DesktopStage(child: body)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.md,
                      0,
                      Space.md,
                      Space.xxl + Space.lg,
                    ),
                    child: body,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A centered card whose width is chosen so the 4:3 picture and the
/// controls under it fit the window height. Nothing hides below the fold.
class _DesktopStage extends StatelessWidget {
  const _DesktopStage({required this.child});

  final Widget child;

  /// Controls with the question row open, gaps, and card padding, so the
  /// card does not jump when the row unfolds.
  static const _chrome = 2 * Space.lg + 2 * Space.xl + 156;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final byHeight = (c.maxHeight - _chrome) * 4 / 3 + 2 * Space.xl;
        final width = min(OrionContainer.narrow, max(byHeight, 480.0));
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.lg),
              child: OrionCard(large: true, hoverable: false, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            CameraView(),
            Positioned(
              top: Space.sm,
              left: Space.sm,
              child: CameraStatsOverlay(),
            ),
            Positioned(
              bottom: Space.sm,
              left: Space.sm,
              child: SnapshotThumb(),
            ),
            Positioned(
              left: Space.sm,
              right: Space.sm,
              bottom: Space.sm,
              child: Align(
                alignment: Alignment.bottomRight,
                child: CameraReplyBubble(),
              ),
            ),
          ],
        ),
        SizedBox(height: Space.lg),
        CameraControls(),
      ],
    );
  }
}
