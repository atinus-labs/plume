import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:plume_design/plume_design.dart';

import 'actions.dart';

/// An individual toast notification in the toaster stack.
class ToastItem {
  ToastItem({
    required this.id,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 5),
    this.showCloseIcon = true,
  }) : remainingDuration = duration;

  final int id;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final bool showCloseIcon;

  Duration remainingDuration;
  DateTime? timerStartedAt;
  Timer? timer;
  VoidCallback? dismissAction;

  void startTimer() {
    if (remainingDuration <= Duration.zero) return;
    timer?.cancel();
    timerStartedAt = clock.now();
    timer = Timer(remainingDuration, () {
      Toaster.instance.dismiss(id);
    });
  }

  void pauseTimer() {
    if (timer != null && timerStartedAt != null) {
      timer!.cancel();
      timer = null;
      final elapsed = clock.now().difference(timerStartedAt!);
      remainingDuration -= elapsed;
      if (remainingDuration < const Duration(milliseconds: 100)) {
        remainingDuration = const Duration(milliseconds: 100);
      }
      timerStartedAt = null;
    }
  }

  void resumeTimer() {
    pauseTimer();
    startTimer();
  }

  void cancelTimer() {
    timer?.cancel();
    timer = null;
    timerStartedAt = null;
  }
}

/// Global toaster manager that coordinates stacked toast notifications.
class Toaster extends ChangeNotifier {
  Toaster._();
  static final Toaster instance = Toaster._();

  int _nextId = 0;
  final List<ToastItem> _items = [];

  List<ToastItem> get items => List.unmodifiable(_items);

  OverlayEntry? _overlayEntry;
  bool isHostMounted = false;
  bool _isHovered = false;

  bool get isHovered => _isHovered;

  /// Maximum number of stacked toasts simultaneously tracked.
  static const int maxVisible = 6;

  /// Shows a new toast notification. New toasts appear in front while
  /// earlier toasts fold behind into a stacked card deck.
  void show(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    bool? showCloseIcon = true,
  }) {
    final effectiveDuration = duration ?? const Duration(seconds: 5);
    final item = ToastItem(
      id: ++_nextId,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: effectiveDuration,
      showCloseIcon: showCloseIcon ?? true,
    );

    // If reaching max stack limit, dismiss oldest toast.
    if (_items.length >= maxVisible) {
      dismiss(_items.first.id);
    }

    _items.add(item);

    // If currently hovered, the timer is on hold immediately.
    if (!_isHovered) {
      item.startTimer();
    }

    notifyListeners();
    _ensureOverlayMounted();
  }

  /// Sets whether the user is hovering over any toaster on screen.
  /// When hovered, pauses all dismiss timers. When released, holds are released
  /// and all timers resume.
  void setHovered(bool hovered) {
    if (_isHovered == hovered) return;
    _isHovered = hovered;
    if (_isHovered) {
      for (final item in _items) {
        item.pauseTimer();
      }
    } else {
      for (final item in _items) {
        item.resumeTimer();
      }
    }
    notifyListeners();
  }

  /// Triggers dismissal animation for the toast with [id].
  void dismiss(int id) {
    final index = _items.indexWhere((it) => it.id == id);
    if (index == -1) return;
    final item = _items[index];
    item.cancelTimer();
    if (item.dismissAction != null) {
      item.dismissAction!();
    } else {
      _items.removeAt(index);
      if (_items.isEmpty) {
        _isHovered = false;
      }
      notifyListeners();
    }
  }

  /// Removes the toast from the list after animation finishes.
  void remove(int id) {
    final index = _items.indexWhere((it) => it.id == id);
    if (index != -1) {
      final item = _items.removeAt(index);
      item.cancelTimer();
      if (_items.isEmpty) {
        _isHovered = false;
      }
      notifyListeners();
    }
  }

  /// Dismisses all toasts immediately and clears state.
  void clear() {
    for (final it in _items) {
      it.cancelTimer();
    }
    _items.clear();
    _isHovered = false;
    notifyListeners();
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      _overlayEntry!.remove();
    }
    _overlayEntry = null;
  }

  void _ensureOverlayMounted() {
    if (isHostMounted) return;
    if (_overlayEntry != null && _overlayEntry!.mounted) return;

    final overlay = _findOverlay();
    if (overlay != null) {
      _overlayEntry = OverlayEntry(
        builder: (context) => const Positioned.fill(
          child: ToasterStack(),
        ),
      );
      overlay.insert(_overlayEntry!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureOverlayMounted();
      });
    }
  }

  OverlayState? _findOverlay() {
    final ctx = scaffoldMessengerKey.currentContext;
    if (ctx == null) return null;
    OverlayState? overlay;
    void visitor(Element el) {
      if (overlay != null) return;
      if (el is StatefulElement && el.state is OverlayState) {
        overlay = el.state as OverlayState;
        return;
      }
      el.visitChildren(visitor);
    }
    (ctx as Element).visitChildren(visitor);
    return overlay;
  }
}

/// Host widget placed in MaterialApp's builder to render stacked toasts.
class ToasterHost extends StatefulWidget {
  const ToasterHost({super.key, required this.child});

  final Widget child;

  @override
  State<ToasterHost> createState() => _ToasterHostState();
}

class _ToasterHostState extends State<ToasterHost> {
  @override
  void initState() {
    super.initState();
    Toaster.instance.isHostMounted = true;
  }

  @override
  void dispose() {
    Toaster.instance.isHostMounted = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        const Positioned.fill(
          child: ToasterStack(),
        ),
      ],
    );
  }
}

/// Renders the stacked card deck of toasts when folded, and expands them
/// into a fully exposed vertical list on hover.
class ToasterStack extends StatefulWidget {
  const ToasterStack({super.key});

  @override
  State<ToasterStack> createState() => _ToasterStackState();
}

class _ToasterStackState extends State<ToasterStack> {
  final Map<int, double> _cardHeights = {};
  Timer? _exitDebounce;

  static const double _peekOffset = 14.0;
  static const double _gap = 8.0;
  static const double _defaultHeight = 52.0;

  void _onEnter() {
    _exitDebounce?.cancel();
    _exitDebounce = null;
    Toaster.instance.setHovered(true);
  }

  void _onExit() {
    _exitDebounce?.cancel();
    _exitDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        Toaster.instance.setHovered(false);
      }
    });
  }

  @override
  void dispose() {
    _exitDebounce?.cancel();
    _exitDebounce = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Toaster.instance,
      builder: (context, _) {
        final items = Toaster.instance.items;
        if (items.isEmpty) {
          _exitDebounce?.cancel();
          _exitDebounce = null;
          return const SizedBox.shrink();
        }

        final hovered = Toaster.instance.isHovered;

        // displayList has newest first (index 0 = front card)
        final displayList = items.reversed.toList();
        final count = displayList.length;

        // Calculate unfolded and folded bottoms
        double currentBottom = 0.0;
        final Map<int, double> unfoldedBottoms = {};
        for (int i = 0; i < count; i++) {
          final item = displayList[i];
          unfoldedBottoms[item.id] = currentBottom;
          final h = _cardHeights[item.id] ?? _defaultHeight;
          currentBottom += h + _gap;
        }
        final double totalUnfoldedHeight = count > 0 ? (currentBottom - _gap) : 0.0;

        final double frontHeight = _cardHeights[displayList.first.id] ?? _defaultHeight;
        final double totalFoldedHeight = frontHeight + math.min(count - 1, 2) * _peekOffset;
        final double containerHeight = hovered ? totalUnfoldedHeight : totalFoldedHeight;

        // Stack children ordered from back to front (displayList.reversed)
        // so index 0 (newest) is painted last and sits on top.
        final stackList = displayList.reversed.toList();

        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
              child: MouseRegion(
                onEnter: (_) => _onEnter(),
                onExit: (_) => _onExit(),
                hitTestBehavior: HitTestBehavior.translucent,
                child: GestureDetector(
                  onTap: () {
                    // Tap toggle for touch devices
                    if (hovered) {
                      _onExit();
                    } else {
                      _onEnter();
                    }
                  },
                  behavior: HitTestBehavior.deferToChild,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      height: containerHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          for (final item in stackList) ...[
                            _buildCardEntry(
                              item: item,
                              index: displayList.indexOf(item),
                              hovered: hovered,
                              unfoldedBottom: unfoldedBottoms[item.id] ?? 0.0,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardEntry({
    required ToastItem item,
    required int index,
    required bool hovered,
    required double unfoldedBottom,
  }) {
    // Folded calculations: index 0 is front card at bottom: 0.
    // index 1 is behind it, bottom: 14, scale: 0.94.
    // index 2 is behind index 1, bottom: 28, scale: 0.88.
    // index >= 3 is hidden behind until front ones dismiss.
    final double foldedBottom;
    final double foldedScale;
    final double foldedOpacity;

    if (index == 0) {
      foldedBottom = 0.0;
      foldedScale = 1.0;
      foldedOpacity = 1.0;
    } else if (index == 1) {
      foldedBottom = _peekOffset;
      foldedScale = 0.94;
      foldedOpacity = 0.92;
    } else if (index == 2) {
      foldedBottom = _peekOffset * 2;
      foldedScale = 0.88;
      foldedOpacity = 0.80;
    } else {
      foldedBottom = _peekOffset * 2;
      foldedScale = 0.84;
      foldedOpacity = 0.0;
    }

    final double targetBottom = hovered ? unfoldedBottom : foldedBottom;
    final double targetScale = hovered ? 1.0 : foldedScale;
    final double targetOpacity = hovered ? 1.0 : foldedOpacity;

    return AnimatedPositioned(
      key: ValueKey(item.id),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      bottom: targetBottom,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        scale: targetScale,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          opacity: targetOpacity,
          child: _MeasureSize(
            onChange: (size) {
              if (_cardHeights[item.id] != size.height) {
                setState(() => _cardHeights[item.id] = size.height);
              }
            },
            child: _ToastCard(
              key: ValueKey('toast_card_${item.id}'),
              item: item,
              isFront: index == 0,
              isHovered: hovered,
              onEnter: _onEnter,
              onExit: _onExit,
              onDismissed: () {
                _cardHeights.remove(item.id);
                Toaster.instance.remove(item.id);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.item,
    required this.isFront,
    required this.isHovered,
    required this.onEnter,
    required this.onExit,
    required this.onDismissed,
  });

  final ToastItem item;
  final bool isFront;
  final bool isHovered;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onDismissed;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _dismissing) {
        widget.onDismissed();
      }
    });

    widget.item.dismissAction = _triggerDismiss;
    _controller.forward();
  }

  @override
  void didUpdateWidget(_ToastCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.item.dismissAction = _triggerDismiss;
  }

  void _triggerDismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _controller.reverse();
  }

  @override
  void dispose() {
    widget.item.cancelTimer();
    if (widget.item.dismissAction == _triggerDismiss) {
      widget.item.dismissAction = null;
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: MouseRegion(
          onEnter: (_) => widget.onEnter(),
          onExit: (_) => widget.onExit(),
          hitTestBehavior: HitTestBehavior.translucent,
          child: _ToastView(
            item: widget.item,
            isFront: widget.isFront,
            isHovered: widget.isHovered,
            onDismiss: _triggerDismiss,
          ),
        ),
      ),
    );
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({
    required this.item,
    required this.isFront,
    required this.isHovered,
    required this.onDismiss,
  });

  final ToastItem item;
  final bool isFront;
  final bool isHovered;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snackTheme = theme.snackBarTheme;
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = snackTheme.backgroundColor ?? scheme.inverseSurface;
    final textColor = snackTheme.contentTextStyle?.color ?? scheme.onInverseSurface;
    final closeColor = snackTheme.closeIconColor ?? scheme.onInverseSurface;
    final actionColor = snackTheme.actionTextColor ?? scheme.inversePrimary;

    // A subtle border separates cards cleanly when stacked behind each other in the deck.
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

    return Material(
      color: bgColor,
      elevation: (isHovered || isFront) ? 4.0 : 2.0,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corners.medium),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 16,
            end: (item.showCloseIcon || item.actionLabel != null) ? 8 : 16,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    item.message,
                    style: snackTheme.contentTextStyle ?? TextStyle(color: textColor, fontSize: 14),
                  ),
                ),
              ),
              if (item.actionLabel != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    item.onAction?.call();
                    onDismiss();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: actionColor,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(item.actionLabel!),
                ),
              ],
              if (item.showCloseIcon) ...[
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: closeColor),
                  tooltip: 'Close',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  onPressed: onDismiss,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper widget to measure size of rendered cards.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChange(newSize);
      });
    }
  }
}
