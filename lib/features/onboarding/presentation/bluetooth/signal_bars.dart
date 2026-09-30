import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';

/// Three rising bars, lit up to [bars]. Accent for lit, faint for the rest.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars});

  /// Zero to three.
  final int bars;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Signal $bars of 3',
      child: SizedBox(
        width: 16,
        height: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 4,
                height: 4.0 + i * 4,
                decoration: BoxDecoration(
                  color: i < bars ? OrionColors.accent : OrionColors.textFaint,
                  borderRadius: BorderRadius.circular(OrionRadius.xs / 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
