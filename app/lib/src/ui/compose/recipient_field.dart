import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/services.dart';

/// Recipient input: chips for committed addresses, free typing, and
/// suggestions from people the user has corresponded with.
class RecipientField extends ConsumerStatefulWidget {
  const RecipientField({
    super.key,
    required this.label,
    required this.recipients,
    required this.onChanged,
    this.trailing,
    this.autofocus = false,
  });

  final String label;
  final List<Address> recipients;
  final ValueChanged<List<Address>> onChanged;
  final Widget? trailing;
  final bool autofocus;

  @override
  ConsumerState<RecipientField> createState() => RecipientFieldState();
}

class RecipientFieldState extends ConsumerState<RecipientField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Commits whatever is typed; called before sending.
  void commitPending() => _commit(_controller.text);

  void focus() => _focus.requestFocus();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(_controller.text);
    });
    // Backspace in an empty field removes the last recipient. Handled on the
    // field's own node so normal editing is untouched.
    _focus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.backspace &&
          _controller.text.isEmpty &&
          widget.recipients.isNotEmpty) {
        _remove(widget.recipients.last);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final parsed = Address.parseList(text).where((a) => a.email.contains('@')).toList();
    if (parsed.isEmpty) return;
    final existing = widget.recipients.map((a) => a.email.toLowerCase()).toSet();
    widget.onChanged([...widget.recipients, ...parsed.where((a) => existing.add(a.email.toLowerCase()))]);
    _controller.clear();
  }

  void _remove(Address a) => widget.onChanged([...widget.recipients]..remove(a));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(
              width: 40,
              child: Text(widget.label, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final a in widget.recipients) _RecipientChip(address: a, onRemove: () => _remove(a)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 160, maxWidth: 420),
                    child: IntrinsicWidth(child: _input(theme)),
                  ),
                ],
              ),
            ),
          ),
          ?widget.trailing,
        ],
      ),
    );
  }

  Widget _input(ThemeData theme) {
    return RawAutocomplete<Address>(
      textEditingController: _controller,
      focusNode: _focus,
      displayStringForOption: (a) => a.format(),
      optionsBuilder: (value) async {
        final q = value.text.trim();
        if (q.isEmpty) return const [];
        final already = widget.recipients.map((a) => a.email.toLowerCase()).toSet();
        final results = await ref.read(storeProvider).suggestAddresses(q, limit: 6);
        return results.where((a) => !already.contains(a.email.toLowerCase()));
      },
      onSelected: (a) {
        _controller.clear();
        widget.onChanged([...widget.recipients, a]);
        _focus.requestFocus();
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
          controller: controller,
          focusNode: focus,
          autofocus: widget.autofocus,
          style: theme.textTheme.bodyLarge,
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          onChanged: (text) {
            if (text.endsWith(',') || text.endsWith(';') || (text.endsWith(' ') && text.trim().contains('@') && !text.contains('<'))) {
              _commit(text.substring(0, text.length - 1));
            }
          },
          onSubmitted: (text) {
            onSubmit();
            _commit(text);
            focus.requestFocus();
          },
        ),
      optionsViewBuilder: (context, onSelected, options) {
        final scheme = theme.colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380, maxHeight: 320),
              child: ListView(
                padding: const EdgeInsets.all(6),
                shrinkWrap: true,
                children: [
                  for (final a in options)
                    Builder(builder: (context) {
                      final highlighted = AutocompleteHighlightedOption.of(context) == options.toList().indexOf(a);
                      return Material(
                        color: highlighted ? scheme.secondaryContainer : Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.medium)),
                        child: InkWell(
                          borderRadius: Corners.all(Corners.medium),
                          onTap: () => onSelected(a),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                MorphAvatar(name: a.displayName, colorKey: a.email, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(a.displayName, style: theme.textTheme.labelLargeEmphasized, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(a.email, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({required this.address, required this.onRemove});

  final Address address;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address.email);
    return Tooltip(
      message: address.email,
      child: Container(
        height: 32,
        padding: const EdgeInsets.only(left: 3, right: 4),
        decoration: BoxDecoration(
          color: valid ? scheme.secondaryContainer : scheme.errorContainer,
          borderRadius: Corners.all(Corners.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphAvatar(name: address.displayName, colorKey: address.email, size: 26),
            const SizedBox(width: 8),
            Text(
              address.name?.isNotEmpty == true ? address.displayName : address.email,
              style: theme.textTheme.labelLarge?.copyWith(color: valid ? scheme.onSecondaryContainer : scheme.onErrorContainer),
            ),
            const SizedBox(width: 2),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Symbols.close_rounded, size: 16, color: valid ? scheme.onSecondaryContainer : scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
