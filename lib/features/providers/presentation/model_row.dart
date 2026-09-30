import 'package:flutter/material.dart';

import '../../../core/theme/theme_context.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/orion_chip.dart';
import '../domain/model_info.dart';

/// One model in the picker: name, context length and the vision and tools
/// badges. The chosen one carries a cyan hairline.
class ModelRow extends StatelessWidget {
  const ModelRow({
    super.key,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  static const height = 56.0;

  final ModelInfo model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    // The id is what the board is sent, so it shows under a friendly name.
    final detail = [
      if (model.displayName != null) model.id,
      if (model.contextLength != null)
        '${(model.contextLength! / 1000).round()}k context',
    ].join(' · ');
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: selected ? OrionColors.bgHighlight : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          child: Row(
            children: [
              SizedBox(
                width: 1,
                height: 20,
                child: ColoredBox(
                  color: selected ? OrionColors.textCyan : Colors.transparent,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.displayName ?? model.id,
                      style: text.ui.copyWith(
                        color: selected
                            ? OrionColors.textWhite
                            : OrionColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: text.mono.copyWith(color: OrionColors.textFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (model.supportsVision == true) ...[
                const SizedBox(width: Space.xs),
                const OrionTag('vision', accent: true),
              ],
              if (model.supportsTools == true) ...[
                const SizedBox(width: Space.xs),
                const OrionTag('tools'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
