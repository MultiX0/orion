import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../features/device/domain/device_mode.dart';
import 'orb_painter.dart';
import 'orb_sim.dart';

/// The product's face. A Ticker drives OrbSim; the painter repaints on a
/// notifier so the widget tree never rebuilds per frame. Pass mode and
/// level in; LiveOrb in home/presentation wires the providers.
class Orb extends StatefulWidget {
  const Orb({
    super.key,
    required this.mode,
    this.level,
    this.isSpeaking = false,
    this.reducedMotion = false,
    this.size = 260,
    this.startOffline = true,
  });

  final DeviceMode mode;
  final double? level;
  final bool isSpeaking;
  final bool reducedMotion;
  final double size;

  /// Start dim and wake up into the first mode.
  final bool startOffline;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  late final OrbSim _sim = OrbSim(
    start: widget.startOffline ? OrbLook.offline : OrbLook.forMode(widget.mode),
  );
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = ValueNotifier<int>(0);
  late final OrbPainter _painter = OrbPainter(_sim, repaint: _frame);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _push();
    _ticker.start();
  }

  @override
  void didUpdateWidget(Orb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _push();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _push() {
    _sim
      ..setMode(widget.mode)
      ..setLevel(widget.level)
      ..setSpeaking(widget.isSpeaking)
      ..reduced = widget.reducedMotion;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // A long pause (app in background) would otherwise jump the phases.
    _sim.tick(dt.clamp(0, 0.05));
    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(widget.size), painter: _painter),
    );
  }
}
