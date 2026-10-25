import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';

import '../../state/mail.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../actions.dart';
import '../common/format.dart';
import 'compose_host.dart';
import 'recipient_field.dart';
import 'rich_text.dart';

/// Largest total attachment size most providers accept (Gmail: 25 MB).
const _maxAttachmentBytes = 25 * 1024 * 1024;

/// A compose window.
class ComposePanel extends ConsumerStatefulWidget {
  const ComposePanel({super.key, required this.request, required this.maximized, this.dockLeft = false});

  final ComposeRequest request;
  final bool maximized;
  final bool dockLeft;

  @override
  ConsumerState<ComposePanel> createState() => _ComposePanelState();
}

class _ComposePanelState extends ConsumerState<ComposePanel> {
  late String? _accountId = widget.request.accountId;
  late List<Address> _to = widget.request.to;
  late List<Address> _cc = widget.request.cc;
  late List<Address> _bcc = widget.request.bcc;
  late bool _showCc = widget.request.cc.isNotEmpty || widget.request.bcc.isNotEmpty;
  late final _subject = TextEditingController(text: widget.request.subject);
  late final _body = widget.request.html != null
      ? RichTextController.fromHtml(widget.request.html!)
      : RichTextController(text: widget.request.body);
  final _bodyFocus = FocusNode();
  late bool _plainText = widget.request.plainText;
  bool _showFormatting = true;
  final _toKey = GlobalKey<RecipientFieldState>();
  final _ccKey = GlobalKey<RecipientFieldState>();
  final _bccKey = GlobalKey<RecipientFieldState>();
  late List<OutgoingAttachment> _attachments = [...widget.request.attachments];
  bool _loadingForwarded = false;
  String? _quotedText;
  bool _showQuote = false;
  bool _minimized = false;
  late String? _draftId = widget.request.draftId;
  Timer? _autosave;
  String _saveState = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _subject.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
    unawaited(_loadQuote());
    if (widget.request.forwardFrom != null) unawaited(_loadForwardedAttachments());
    // Replies start in the body; new messages in the To field.
    if (widget.request.mode != ComposeMode.fresh && widget.request.mode != ComposeMode.forward) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bodyFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final m = widget.request.quoted;
    if (m == null) return;
    final body = await ref.read(storeProvider).body(m.accountId, m.id);
    var text = body?.text;
    if ((text == null || text.trim().isEmpty) && body?.html != null) text = _htmlToText(body!.html!);
    text ??= m.snippet;
    if (!mounted) return;
    setState(() {
      if (widget.request.mode == ComposeMode.forward) {
        _quotedText = [
          '---------- Forwarded message ---------',
          'From: ${m.from?.format() ?? ''}',
          'Date: ${fullDate(m.date)}',
          'Subject: ${m.subject}',
          'To: ${m.to.map((a) => a.format()).join(', ')}',
          if (m.cc.isNotEmpty) 'Cc: ${m.cc.map((a) => a.format()).join(', ')}',
          '',
          text!,
        ].join('\n');
        _showQuote = true;
      } else {
        _quotedText = '${attributionLine(m)}\n${text!.trimRight().split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n')}';
      }
    });
  }

  Future<void> _loadForwardedAttachments() async {
    final m = widget.request.forwardFrom!;
    final infos = m.attachments.where((a) => !a.isInline).toList();
    if (infos.isEmpty) return;
    setState(() => _loadingForwarded = true);
    final engine = ref.read(engineProvider);
    try {
      for (final info in infos) {
        final bytes = await engine.attachment(m.accountId, m.id, info);
        if (!mounted) return;
        setState(() => _attachments = [
              ..._attachments,
              OutgoingAttachment(filename: info.filename, mimeType: info.mimeType, bytes: bytes),
            ]);
      }
    } catch (_) {
      showSnack('Some attachments couldn’t be included');
    } finally {
      if (mounted) setState(() => _loadingForwarded = false);
    }
  }

  // Draft autosave -------------------------------------------------------------

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 3), () => unawaited(_saveDraft()));
  }

  bool get _isEmpty =>
      _to.isEmpty && _cc.isEmpty && _bcc.isEmpty && _subject.text.trim().isEmpty && _body.text.trim().isEmpty && _attachments.isEmpty;

  Future<void> _saveDraft() async {
    if (_isEmpty || _sending) return;
    final message = _build();
    if (message == null) return;
    setState(() => _saveState = 'Saving…');
    try {
      final id = await ref.read(engineProvider).saveDraft(message);
      if (!mounted) return;
      setState(() {
        _draftId = id;
        _saveState = 'Draft saved';
      });
    } catch (_) {
      if (mounted) setState(() => _saveState = 'Saved on this device');
    }
  }

  // Sending ------------------------------------------------------------------

  OutgoingMessage? _build() {
    final accounts = ref.read(accountMapProvider);
    final account = accounts[_accountId] ?? accounts.values.firstOrNull;
    if (account == null) return null;
    final quote = _quotedText;
    final typed = _body.toPlainText();
    final signature = account.signature?.trim();
    final textParts = [
      typed,
      if (signature != null && signature.isNotEmpty) '\n-- \n$signature',
      if (quote != null) '\n$quote',
    ];
    return OutgoingMessage(
      accountId: account.id,
      from: Address(account.email, account.displayName),
      to: _to,
      cc: _cc,
      bcc: _bcc,
      subject: _subject.text.trim(),
      textBody: textParts.join('\n'),
      htmlBody: _plainText
          ? null
          : _toHtml(_body.toHtml(), signature, quote, quoteIsForward: widget.request.mode == ComposeMode.forward),
      attachments: _attachments,
      threadId: widget.request.threadId,
      inReplyTo: widget.request.inReplyTo,
      references: widget.request.references,
      draftId: _draftId,
    );
  }

  Future<void> _send() async {
    _toKey.currentState?.commitPending();
    _ccKey.currentState?.commitPending();
    _bccKey.currentState?.commitPending();
    await Future<void>.delayed(Duration.zero);
    if (_to.isEmpty && _cc.isEmpty && _bcc.isEmpty) {
      showSnack('Add at least one recipient');
      return;
    }
    final message = _build();
    if (message == null) return;
    if (message.subject.isEmpty && !await _confirm('Send without a subject?', 'Send')) return;
    if (_mentionsAttachment(_body.text) && _attachments.isEmpty &&
        !await _confirm('You mentioned an attachment, but nothing is attached. Send anyway?', 'Send')) {
      return;
    }
    _sending = true;
    _autosave?.cancel();
    final engine = ref.read(engineProvider);
    final delay = Duration(seconds: ref.read(settingsProvider).undoSendSeconds);
    final outboxId = await engine.send(message, delay: delay);
    ref.read(composeProvider.notifier).close(widget.request.id);
    final composer = ref.read(composeProvider.notifier);
    showSnack(
      delay == Duration.zero ? 'Sending…' : 'Message scheduled to send',
      actionLabel: delay == Duration.zero ? null : 'Undo',
      duration: delay == Duration.zero ? const Duration(seconds: 2) : delay,
      onAction: () async {
        final taken = await engine.cancelSend(outboxId);
        if (taken == null) {
          showSnack('Too late, the message was already sent');
        } else {
          composer.reopen(taken);
        }
      },
    );
  }

  Future<void> _discard() async {
    _autosave?.cancel();
    final draftId = _draftId;
    final accountId = _accountId;
    ref.read(composeProvider.notifier).close(widget.request.id);
    if (draftId != null && accountId != null) {
      try {
        await ref.read(engineProvider).deleteDraft(accountId, draftId);
      } catch (_) {}
    }
    if (!_isEmpty) showSnack('Draft discarded');
  }

  Future<void> _closeKeepingDraft() async {
    _autosave?.cancel();
    final empty = _isEmpty;
    if (!empty) await _saveDraft();
    ref.read(composeProvider.notifier).close(widget.request.id);
    if (!empty) showSnack('Draft saved');
  }

  Future<bool> _confirm(String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _attach() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    var total = _attachments.fold<int>(0, (sum, a) => sum + a.bytes.length);
    final added = <OutgoingAttachment>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (total + bytes.length > _maxAttachmentBytes) {
        showSnack('${f.name} is too large to attach (limit 25 MB in total)');
        continue;
      }
      total += bytes.length;
      added.add(OutgoingAttachment(filename: f.name, mimeType: _mimeFor(f.name), bytes: bytes));
    }
    setState(() => _attachments = [..._attachments, ...added]);
    _scheduleSave();
  }

  // Formatting -----------------------------------------------------------------

  /// Runs a formatting [action] on the body and returns focus to it.
  void _format(void Function() action) {
    if (_plainText) return;
    action();
    _bodyFocus.requestFocus();
  }

  Future<void> _editLink() async {
    final sel = _body.selection;
    if (_plainText || !sel.isValid) return;
    final existing = _body.linkRange();
    final range = existing ?? TextRange(start: sel.start, end: sel.end);
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => _LinkDialog(
        label: range.textInside(_body.text),
        url: existing == null ? '' : _body.linkAt(existing.start) ?? '',
        canRemove: existing != null,
      ),
    );
    if (result != null && mounted) _body.setLink(range, result.$1, result.$2);
    _bodyFocus.requestFocus();
  }

  Future<void> _togglePlainText() async {
    if (!_plainText &&
        _body.hasFormatting &&
        !await _confirm('Switching to plain text removes the formatting from this message.', 'Switch')) {
      return;
    }
    setState(() => _plainText = !_plainText);
    if (_plainText) _body.clearAllFormatting();
    _scheduleSave();
  }

  Map<ShortcutActivator, VoidCallback> get _formatShortcuts {
    if (_plainText) return const {};
    void Function() style(int flag) => () => _body.toggle(flag);
    void Function() list(ListKind kind) => () => _body.toggleList(kind);
    return {
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): style(InlineStyle.bold),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): style(InlineStyle.italic),
      const SingleActivator(LogicalKeyboardKey.keyU, control: true): style(InlineStyle.underline),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true, shift: true): style(InlineStyle.strike),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => unawaited(_editLink()),
      // Shifted digits may arrive as the digit or as its symbol.
      const SingleActivator(LogicalKeyboardKey.digit7, control: true, shift: true): list(ListKind.numbered),
      const SingleActivator(LogicalKeyboardKey.ampersand, control: true, shift: true): list(ListKind.numbered),
      const SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true): list(ListKind.bullet),
      const SingleActivator(LogicalKeyboardKey.asterisk, control: true, shift: true): list(ListKind.bullet),
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): _body.clearFormatting,
    };
  }

  // UI -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final width = widget.maximized ? (size.width - 64).clamp(400.0, 1040.0) : 560.0;
    final height = _minimized ? 56.0 : (widget.maximized ? size.height - 64 : (size.height - 96).clamp(360.0, 640.0));
    final title = _subject.text.trim().isNotEmpty
        ? _subject.text.trim()
        : switch (widget.request.mode) {
            ComposeMode.fresh => 'New message',
            ComposeMode.reply || ComposeMode.replyAll => 'Reply',
            ComposeMode.forward => 'Forward',
          };

    final alignment = widget.maximized
        ? Alignment.center
        : (widget.dockLeft ? Alignment.bottomLeft : Alignment.bottomRight);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Spring.spatial.duration,
      curve: Spring.spatial.curve,
      builder: (context, t, child) => Transform(
        alignment: alignment,
        transform: Matrix4.identity()
          ..translateByDouble(0, (1 - t) * 40, 0, 1)
          ..scaleByDouble(0.92 + 0.08 * t, 0.92 + 0.08 * t, 1, 1),
        child: Opacity(opacity: unit(t), child: child),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
          const SingleActivator(LogicalKeyboardKey.escape): () => unawaited(_closeKeepingDraft()),
        },
        child: AnimatedContainer(
          duration: Spring.spatial.duration,
          curve: Spring.spatial.curve,
          width: width,
          height: height,
          margin: EdgeInsets.only(bottom: widget.maximized ? 0 : 16),
          child: Material(
            color: scheme.surfaceContainerLow,
            elevation: 8,
            shadowColor: scheme.shadow.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.extraLarge)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _TitleBar(
                  title: title,
                  minimized: _minimized,
                  maximized: widget.maximized,
                  onMinimize: () => setState(() => _minimized = !_minimized),
                  onMaximize: () => ref
                      .read(maximizedComposeProvider.notifier)
                      .set(widget.maximized ? null : widget.request.id),
                  onClose: () => unawaited(_closeKeepingDraft()),
                ),
                if (!_minimized) Expanded(child: _form(theme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    final scheme = theme.colorScheme;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final divider = Divider(height: 1, indent: 20, endIndent: 20, color: scheme.outlineVariant.withValues(alpha: 0.5));

    return Column(
      children: [
        if (accounts.length > 1) ...[
          _FromRow(
            accounts: accounts,
            selected: _accountId,
            locked: widget.request.threadId != null,
            onChanged: (id) => setState(() => _accountId = id),
          ),
          divider,
        ],
        RecipientField(
          key: _toKey,
          label: 'To',
          recipients: _to,
          autofocus: widget.request.mode == ComposeMode.fresh || widget.request.mode == ComposeMode.forward,
          onChanged: (v) {
            setState(() => _to = v);
            _scheduleSave();
          },
          trailing: _showCc
              ? null
              : TextButton(onPressed: () => setState(() => _showCc = true), child: const Text('Cc  Bcc')),
        ),
        divider,
        if (_showCc) ...[
          RecipientField(key: _ccKey, label: 'Cc', recipients: _cc, onChanged: (v) => setState(() => _cc = v)),
          divider,
          RecipientField(key: _bccKey, label: 'Bcc', recipients: _bcc, onChanged: (v) => setState(() => _bcc = v)),
          divider,
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _subject,
            style: theme.textTheme.titleMedium,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Subject',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        divider,
        Expanded(
          child: Scrollbar(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              children: [
                CallbackShortcuts(
                  bindings: _formatShortcuts,
                  child: TextField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    minLines: 8,
                    keyboardType: TextInputType.multiline,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    decoration: const InputDecoration(
                      hintText: 'Write your message',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_quotedText != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: _showQuote ? 'Hide quoted text' : 'Show quoted text',
                      child: ActionChip(
                        avatar: Icon(_showQuote ? Symbols.unfold_less_rounded : Symbols.more_horiz_rounded, size: 18),
                        label: Text(widget.request.mode == ComposeMode.forward ? 'Forwarded message' : 'Quoted text'),
                        onPressed: () => setState(() => _showQuote = !_showQuote),
                      ),
                    ),
                  ),
                  if (_showQuote)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.outlineVariant, width: 3))),
                        child: Text(_quotedText!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (_attachments.isNotEmpty || _loadingForwarded)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final a in _attachments)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      avatar: const Icon(Symbols.attach_file_rounded, size: 18),
                      label: Text('${a.filename}  ·  ${fileSize(a.bytes.length)}'),
                      onDeleted: () => setState(() => _attachments = [..._attachments]..remove(a)),
                    ),
                  ),
                if (_loadingForwarded) const Center(child: LoadingIndicator(size: 32)),
              ],
            ),
          ),
        if (_showFormatting && !_plainText)
          _FormatBar(controller: _body, onFormat: _format, onLink: () => unawaited(_editLink())),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 14),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _send,
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(112, 48))),
                icon: const Icon(Symbols.send_rounded, size: 20),
                label: const Text('Send'),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: _plainText ? 'Formatting is off in plain text mode' : 'Formatting options',
                isSelected: _showFormatting && !_plainText,
                onPressed: _plainText ? null : () => setState(() => _showFormatting = !_showFormatting),
                icon: const Icon(Symbols.text_format_rounded),
              ),
              IconButton(tooltip: 'Attach files', onPressed: _attach, icon: const Icon(Symbols.attach_file_rounded)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_saveState,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Text('Ctrl+Enter to send', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
              MenuAnchor(
                menuChildren: [
                  CheckboxMenuButton(
                    value: _plainText,
                    onChanged: (_) => unawaited(_togglePlainText()),
                    child: const Text('Plain text mode'),
                  ),
                ],
                builder: (context, controller, _) => IconButton(
                  tooltip: 'More options',
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  icon: const Icon(Symbols.more_vert_rounded),
                ),
              ),
              IconButton(tooltip: 'Discard draft', onPressed: _discard, icon: const Icon(Symbols.delete_rounded)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    required this.minimized,
    required this.maximized,
    required this.onMinimize,
    required this.onMaximize,
    required this.onClose,
  });

  final String title;
  final bool minimized;
  final bool maximized;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: minimized ? onMinimize : null,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmallEmphasized),
              ),
              IconButton(
                tooltip: minimized ? 'Restore' : 'Minimise',
                onPressed: onMinimize,
                icon: Icon(minimized ? Symbols.expand_less_rounded : Symbols.minimize_rounded, size: 20),
              ),
              if (!minimized)
                IconButton(
                  tooltip: maximized ? 'Exit full size' : 'Full size',
                  onPressed: onMaximize,
                  icon: Icon(maximized ? Symbols.close_fullscreen_rounded : Symbols.open_in_full_rounded, size: 18),
                ),
              IconButton(tooltip: 'Save & close (Esc)', onPressed: onClose, icon: const Icon(Symbols.close_rounded, size: 20)),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formatting buttons above the compose actions, like Gmail's formatting bar.
class _FormatBar extends StatelessWidget {
  const _FormatBar({required this.controller, required this.onFormat, required this.onLink});

  final RichTextController controller;
  final void Function(void Function() action) onFormat;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : null),
      foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
    );
    Widget button(IconData icon, String tooltip, bool selected, VoidCallback onPressed) => IconButton(
          tooltip: tooltip,
          isSelected: selected,
          style: selectedStyle,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: onPressed,
          icon: Icon(icon),
        );
    Widget gap() => SizedBox(
        height: 20, child: VerticalDivider(width: 12, color: scheme.outlineVariant.withValues(alpha: 0.6)));

    // Clicking a button must not take the selection away from the body.
    return TextFieldTapRegion(
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final list = controller.listKind();
                Widget style(IconData icon, String tooltip, int flag) =>
                    button(icon, tooltip, controller.isActive(flag), () => onFormat(() => controller.toggle(flag)));
                return Row(
                  children: [
                    style(Symbols.format_bold_rounded, 'Bold (Ctrl+B)', InlineStyle.bold),
                    style(Symbols.format_italic_rounded, 'Italic (Ctrl+I)', InlineStyle.italic),
                    style(Symbols.format_underlined_rounded, 'Underline (Ctrl+U)', InlineStyle.underline),
                    style(Symbols.strikethrough_s_rounded, 'Strikethrough (Ctrl+Shift+X)', InlineStyle.strike),
                    gap(),
                    button(Symbols.link_rounded, 'Insert link (Ctrl+K)', controller.linkRange() != null, onLink),
                    gap(),
                    button(Symbols.format_list_numbered_rounded, 'Numbered list (Ctrl+Shift+7)', list == ListKind.numbered,
                        () => onFormat(() => controller.toggleList(ListKind.numbered))),
                    button(Symbols.format_list_bulleted_rounded, 'Bulleted list (Ctrl+Shift+8)', list == ListKind.bullet,
                        () => onFormat(() => controller.toggleList(ListKind.bullet))),
                    gap(),
                    button(Symbols.format_clear_rounded, 'Remove formatting (Ctrl+\\)', false,
                        () => onFormat(controller.clearFormatting)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits the text and address of a link.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.label, required this.url, required this.canRemove});

  final String label;
  final String url;
  final bool canRemove;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _label = TextEditingController(text: widget.label);
  late final _url = TextEditingController(text: widget.url);

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  String? get _link => normalizeLink(_url.text);

  void _apply() {
    final link = _link;
    if (link == null) return;
    Navigator.pop(context, (_label.text.isEmpty ? _url.text.trim() : _label.text, link));
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _url.text.trim().isNotEmpty && _link == null;
    return AlertDialog(
      title: Text(widget.canRemove ? 'Edit link' : 'Insert link'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              autofocus: widget.label.isEmpty,
              decoration: const InputDecoration(labelText: 'Text to display'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              autofocus: widget.label.isNotEmpty,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _apply(),
              decoration: InputDecoration(
                labelText: 'Web address or email',
                hintText: 'https://example.com',
                errorText: invalid ? 'Enter a web address or an email address' : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canRemove)
          TextButton(onPressed: () => Navigator.pop(context, (widget.label, null)), child: const Text('Remove link')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _link == null ? null : _apply, child: const Text('Apply')),
      ],
    );
  }
}

class _FromRow extends StatelessWidget {
  const _FromRow({required this.accounts, required this.selected, required this.locked, required this.onChanged});

  final List<Account> accounts;
  final String? selected;
  final bool locked;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = accounts.where((a) => a.id == selected).firstOrNull ?? accounts.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('From', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          MenuAnchor(
            menuChildren: [
              for (final a in accounts)
                MenuItemButton(
                  leadingIcon: MorphAvatar(name: a.displayName, colorKey: a.email, size: 28),
                  onPressed: () => onChanged(a.id),
                  child: Text('${a.displayName}  <${a.email}>'),
                ),
            ],
            builder: (context, controller, _) => TextButton.icon(
              onPressed: locked ? null : () => controller.isOpen ? controller.close() : controller.open(),
              iconAlignment: IconAlignment.end,
              icon: locked ? null : const Icon(Symbols.arrow_drop_down_rounded),
              label: Text('${current.displayName} <${current.email}>', style: theme.textTheme.bodyLarge),
            ),
          ),
        ],
      ),
    );
  }
}

bool _mentionsAttachment(String body) =>
    RegExp(r'\b(attached|attachment|attaching|enclosed)\b', caseSensitive: false).hasMatch(body);

String _mimeFor(String name) => switch (p.extension(name).toLowerCase()) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.svg' => 'image/svg+xml',
      '.txt' || '.md' => 'text/plain',
      '.csv' => 'text/csv',
      '.html' || '.htm' => 'text/html',
      '.zip' => 'application/zip',
      '.json' => 'application/json',
      '.doc' => 'application/msword',
      '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls' => 'application/vnd.ms-excel',
      '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.ppt' => 'application/vnd.ms-powerpoint',
      '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.odt' => 'application/vnd.oasis.opendocument.text',
      '.ods' => 'application/vnd.oasis.opendocument.spreadsheet',
      '.mp3' => 'audio/mpeg',
      '.mp4' => 'video/mp4',
      _ => 'application/octet-stream',
    };

/// Builds the HTML part around the formatted [body]: the signature and
/// quote are escaped with paragraphs kept, links clickable, and the quote in
/// a blockquote.
String _toHtml(String body, String? signature, String? quote, {required bool quoteIsForward}) {
  String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
  String para(String s) => linkifyHtml(esc(s)).replaceAll('\n', '<br>');
  final buffer = StringBuffer('<div dir="auto" style="font-family:sans-serif">')..write(body);
  if (signature != null && signature.isNotEmpty) {
    buffer.write('<br><div class="plume_signature">-- <br>${para(signature)}</div>');
  }
  buffer.write('</div>');
  if (quote != null) {
    if (quoteIsForward) {
      buffer.write('<br><div class="gmail_quote">${para(quote)}</div>');
    } else {
      final lines = quote.split('\n');
      final attribution = lines.first;
      final quoted = lines.skip(1).map((l) => l.startsWith('> ') ? l.substring(2) : (l == '>' ? '' : l)).join('\n');
      buffer.write('<br><div class="gmail_quote"><div>${esc(attribution)}</div>'
          '<blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">'
          '${para(quoted)}</blockquote></div>');
    }
  }
  return buffer.toString();
}

/// Rough HTML to text for quoting.
String _htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|tr|li|h\d)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
