import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/mono_label.dart';
import '../../../core/widgets/orion_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/camera_providers.dart';

/// The live picture. Image.memory with gaplessPlayback inside a
/// RepaintBoundary, so a new frame only repaints this box. onFrame is the
/// hook for on-device detection later; nothing calls it yet.
class CameraView extends ConsumerWidget {
  const CameraView({super.key, this.onFrame});

  final void Function(Uint8List bytes)? onFrame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frames = ref.watch(cameraFramesProvider);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OrionRadius.card),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: OrionColors.bgCard,
            border: Border.all(color: OrionColors.borderSubtle),
            borderRadius: BorderRadius.circular(OrionRadius.card),
          ),
          child: switch (frames) {
            AsyncData(:final value) => _Frame(
              bytes: value.bytes,
              onFrame: onFrame,
            ),
            AsyncError(:final error) => _Dark(
              error: error,
              onRetry: () => ref.invalidate(cameraFramesProvider),
            ),
            _ => const _Opening(),
          },
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.bytes, this.onFrame});

  final Uint8List bytes;
  final void Function(Uint8List bytes)? onFrame;

  @override
  Widget build(BuildContext context) {
    onFrame?.call(bytes);
    return RepaintBoundary(
      child: Image.memory(
        bytes,
        gaplessPlayback: true,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => const _Opening(),
      ),
    );
  }
}

/// The stream failed. The board streams to one viewer at a time, so the
/// most likely reason gets its own line; everything else says what to do.
class _Dark extends StatelessWidget {
  const _Dark({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, emphasis, body) = switch (error) {
      DeviceFailure(code: 'busy') => (
        'Another screen holds the lens',
        'lens',
        'Orion streams to one viewer at a time. Close it there, then try '
            'again.',
      ),
      AuthFailure() => (
        'Orion does not know this app',
        'know',
        'Pair again from Settings and the picture returns.',
      ),
      TimeoutFailure() || NetworkFailure() => (
        'The link dropped',
        'dropped',
        'No frames are arriving. Orion may be rebooting or out of range.',
      ),
      _ => ('The lens is dark', 'dark', 'The stream ended without a reason.'),
    };
    return EmptyState(
      label: '// No picture',
      title: title,
      emphasis: emphasis,
      body: body,
      action: OrionButton.ghost(
        label: 'Try again',
        size: OrionButtonSize.compact,
        icon: Icons.refresh,
        onPressed: onRetry,
      ),
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Skeleton.card(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MonoLabel.eyebrow('Opening the lens'),
              const SizedBox(height: Space.xs),
              Text('First frame in a moment.', style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
