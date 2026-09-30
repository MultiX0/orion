import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A headline with the brand's single italic emphasis. The first match of
/// emphasis inside text is set italic in the accent; the rest stays roman.
class EmphasisText extends StatelessWidget {
  const EmphasisText(
    this.text, {
    super.key,
    required this.style,
    this.emphasis,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final String? emphasis;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final em = emphasis;
    final at = em == null || em.isEmpty ? -1 : text.indexOf(em);
    if (at < 0) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: em,
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: OrionColors.textCyan,
            ),
          ),
          TextSpan(text: text.substring(at + em!.length)),
        ],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
