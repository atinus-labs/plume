import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/navigation.dart';
import '../../state/services.dart';

/// Focus for the search field, so `/` can jump to it from anywhere.
final searchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'search');
  ref.onDispose(node.dispose);
  return node;
});

/// The M3 Expressive search bar. Typing filters downloaded mail instantly;
/// Enter asks the server(s) too.
class SearchField extends ConsumerStatefulWidget {
  const SearchField({super.key});

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _focused = false;
  late final FocusNode _focusNode = ref.read(searchFocusProvider);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focused = _focusNode.hasFocus);

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      ref.read(searchProvider.notifier).setQuery(value);
      setState(() {});
    });
  }

  Future<void> _submit() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    final notifier = ref.read(searchProvider.notifier);
    if (ref.read(searchProvider).query != _controller.text) notifier.setQuery(_controller.text);
    final generation = notifier.beginServerSearch();
    final accountId = ref.read(viewProvider).accountId;
    final keys = await ref.read(engineProvider).searchServer(query, accountIds: accountId == null ? null : {accountId});
    notifier.complete(generation, keys);
  }

  void _clear() {
    _controller.clear();
    ref.read(searchProvider.notifier).clear();
    ref.read(searchFocusProvider).unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final focus = ref.watch(searchFocusProvider);
    // Keep the field in sync when search is cleared from elsewhere.
    ref.listen(searchProvider, (prev, next) {
      if (!next.active && _controller.text.isNotEmpty && !focus.hasFocus) _controller.clear();
    });

    return SpringBuilder(
      value: _focused ? 1 : 0,
      spring: Spring.spatialFast,
      builder: (context, t, child) => Material(
        color: Color.lerp(scheme.surfaceContainerHigh, scheme.surfaceContainerHighest, unit(t)),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge - 4 * unit(t))),
        child: child,
      ),
      child: SizedBox(
        height: 52,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Symbols.search_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: focus,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Search mail',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              if (_controller.text.isNotEmpty)
                IconButton(tooltip: 'Clear search', onPressed: _clear, icon: const Icon(Symbols.close_rounded))
              else
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _KeyHint(label: '/', color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: Corners.all(Corners.small - 2),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
      );
}
