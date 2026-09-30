import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_context.dart';
import '../theme/tokens.dart';
import 'mono_label.dart';

/// The brand input with an optional mono label above it. obscure adds a
/// reveal toggle, so keys are masked until the user asks.
class OrionTextField extends StatefulWidget {
  const OrionTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.mono = false,
    this.accent = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final bool obscure;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final bool mono;

  /// The hairline turns accent, for a value that has been proven.
  final bool accent;

  @override
  State<OrionTextField> createState() => _OrionTextFieldState();
}

class _OrionTextFieldState extends State<OrionTextField> {
  var _revealed = false;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final style = widget.mono
        ? text.mono.copyWith(
            color: OrionColors.textWhite,
            fontSize: OrionFontSize.ui,
          )
        : text.ui;
    final suffix = widget.obscure
        ? _RevealToggle(
            revealed: _revealed,
            onToggle: () => setState(() => _revealed = !_revealed),
          )
        : widget.trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          MonoLabel(widget.label!),
          const SizedBox(height: Space.xs),
        ],
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: widget.obscure && !_revealed,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: style,
          cursorWidth: 1,
          decoration: InputDecoration(
            hintText: widget.hint,
            enabledBorder: widget.accent
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(OrionRadius.sm),
                    borderSide: const BorderSide(color: OrionColors.borderCyan),
                  )
                : null,
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: Space.xl,
              minHeight: Space.xl,
            ),
            errorText: widget.error,
          ),
        ),
        if (widget.helper != null && widget.error == null) ...[
          const SizedBox(height: Space.xs),
          Text(widget.helper!, style: text.uiSmall),
        ],
      ],
    );
  }
}

class _RevealToggle extends StatelessWidget {
  const _RevealToggle({required this.revealed, required this.onToggle});

  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Icon(
            revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
            color: revealed ? OrionColors.textCyan : OrionColors.textMuted,
          ),
        ),
      ),
    );
  }
}
