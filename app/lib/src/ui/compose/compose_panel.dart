import 'package:flutter/gestures.dart';

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    // ignore: experimental_member_use
    show QuillClipboardConfig, QuillController, QuillControllerConfig;
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
import 'body_editor.dart';
import 'compose_host.dart';
import 'format_bar.dart';
import 'mail_body.dart';
import 'recipient_field.dart';
import 'rich_text.dart';

/// Largest total attachment size most providers accept (Gmail: 25 MB).
const _maxAttachmentBytes = 25 * 1024 * 1024;

/// A compose window.
class ComposePanel extends ConsumerStatefulWidget {
  const ComposePanel({
    super.key,
    required this.request,
    required this.maximized,
    this.fullScreen = false,
    this.dockLeft = false,
    this.animateIn = true,
    this.onDrag,
  });

  final ComposeRequest request;
  final bool maximized;

  /// Fills a narrow window, without minimise or full size.
  final bool fullScreen;
  final bool dockLeft;

  /// Rises into place when first shown; off when the host animates the
  /// window in from the control that opened it.
  final bool animateIn;
  final void Function(Offset delta)? onDrag;

  @override
  ConsumerState<ComposePanel> createState() => _ComposePanelState();
}

class _ComposePanelState extends ConsumerState<ComposePanel> {
  late String? _accountId = widget.request.accountId;
  late List<Address> _to = widget.request.to;
  late List<Address> _cc = widget.request.cc;
  late List<Address> _bcc = widget.request.bcc;
  late bool _showCc =
      widget.request.cc.isNotEmpty || widget.request.bcc.isNotEmpty;
  late final _subject = TextEditingController(text: widget.request.subject);
  late bool _plainText = widget.request.plainText;

  /// The formatted body, and the body in plain text mode.
  late final _body = QuillController(
    document: widget.request.html != null && !_plainText
        ? documentFromHtml(widget.request.html!)
        : documentFromText(_plainText ? null : widget.request.body),
    selection: const TextSelection.collapsed(offset: 0),
    // Formatting pasted from other apps is not read. On Linux reading it
    // runs a bundled xclip, which Wayland sessions may not support.
    config: const QuillControllerConfig(
      // ignore: experimental_member_use
      clipboardConfig: QuillClipboardConfig(enableExternalRichPaste: false),
    ),
  );
  late final _plainBody = TextEditingController(
    text: _plainText ? widget.request.body : '',
  );
  final _bodyFocus = FocusNode();
  final _bodyScroll = ScrollController();
  bool _showFormatting = true;
  final _toKey = GlobalKey<RecipientFieldState>();
  final _ccKey = GlobalKey<RecipientFieldState>();
  final _bccKey = GlobalKey<RecipientFieldState>();
  late List<OutgoingAttachment> _attachments = [...widget.request.attachments];
  bool _loadingAttachments = false;

  /// Done once the attachments that come along are in.
  Future<void> _attachmentsLoaded = Future.value();
  late String? _quotedText = widget.request.quote;
  late bool _showQuote = widget.request.mode == ComposeMode.forward;
  bool _minimized = false;
  late final bool _animateIn = widget.animateIn;
  late String? _draftId = widget.request.draftId;

  /// The draft as kept on this device, once saved.
  late int? _localId = widget.request.localDraftId;

  /// The account [_draftId] and [_localId] belong to.
  late String? _draftAccount = widget.request.accountId;

  /// The latest save, whose upload the status line tells of.
  LocalDraft? _lastSave;
  Timer? _autosave;
  String _saveState = '';
  bool _sending = false;
  Offset _dragOffset = Offset.zero;

  void _handleDrag(Offset delta) {
    if (widget.maximized) return;
    if (widget.onDrag != null) {
      widget.onDrag!(delta);
    } else {
      setState(() => _dragOffset += delta);
    }
  }

  @override
  void initState() {
    super.initState();
    _subject.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
    _plainBody.addListener(_scheduleSave);
    unawaited(_loadQuote());
    if (widget.request.attachmentsFrom != null) {
      _attachmentsLoaded = _loadAttachments();
    }
    // Asked for outright: autofocus gives way to the shell, which holds focus
    // for the mail shortcuts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_startInTo) {
        _toKey.currentState?.focus();
      } else {
        _bodyFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _subject.dispose();
    _body.dispose();
    _plainBody.dispose();
    _bodyFocus.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  /// New replies and messages with recipients start in the body; other new
  /// messages in the To field.
  bool get _startInTo =>
      (widget.request.mode == ComposeMode.fresh ||
          widget.request.mode == ComposeMode.forward) &&
      widget.request.to.isEmpty;

  Future<void> _loadQuote() async {
    final m = widget.request.quoted;
    if (m == null || widget.request.quote != null) return;
    final body = await ref.read(storeProvider).body(m.accountId, m.id);
    var text = body?.text;
    if ((text == null || text.trim().isEmpty) && body?.html != null)
      text = _htmlToText(body!.html!);
    text ??= m.snippet;
    if (!mounted) return;
    setState(() {
      _quotedText = widget.request.mode == ComposeMode.forward
          ? forwardQuote(m, text!)
          : replyQuote(m, text!);
    });
  }

  Future<void> _loadAttachments() async {
    final m = widget.request.attachmentsFrom!;
    final infos = m.attachments.where((a) => !a.isInline).toList();
    if (infos.isEmpty) return;
    setState(() => _loadingAttachments = true);
    final engine = ref.read(engineProvider);
    try {
      for (final info in infos) {
        final bytes = await engine.attachment(m.accountId, m.id, info);
        if (!mounted) return;
        setState(
          () => _attachments = [
            ..._attachments,
            OutgoingAttachment(
              filename: info.filename,
              mimeType: info.mimeType,
              bytes: bytes,
            ),
          ],
        );
      }
    } catch (_) {
      showSnack('Some attachments couldn’t be included');
    } finally {
      if (mounted) setState(() => _loadingAttachments = false);
    }
  }

  // Draft autosave -------------------------------------------------------------

  void _scheduleSave() {
    _autosave?.cancel();
    _autosave = Timer(
      const Duration(seconds: 3),
      () => unawaited(_saveDraft()),
    );
  }

  String get _bodyText =>
      _plainText ? _plainBody.text : _body.document.toPlainText();

  bool get _isEmpty =>
      _to.isEmpty &&
      _cc.isEmpty &&
      _bcc.isEmpty &&
      _subject.text.trim().isEmpty &&
      _bodyText.trim().isEmpty &&
      _attachments.isEmpty;

  /// Saves run one after another, so each updates the draft the last one
  /// made instead of making another.
  Future<bool> _saving = Future.value(false);

  /// Saves the draft on this device, returning whether it is saved. The
  /// upload to the server follows in the background.
  Future<bool> _saveDraft() => _saving = _saving.then((_) => _save());

  Future<bool> _save() async {
    // A draft saved without the attachments still coming would lose them.
    await _attachmentsLoaded;
    if (_isEmpty || _sending || !mounted) return false;
    final engine = ref.read(engineProvider);
    final account = _account;
    if (account == null) return false;
    setState(() => _saveState = 'Saving…');
    try {
      await _leaveOtherAccount(engine, account.id);
      final draft = await engine.saveDraft(_build()!, localId: _localId);
      _localId = draft.id;
      _draftId = draft.draftId ?? _draftId;
      _lastSave = draft;
      if (!mounted) return true;
      ref.read(composeProvider.notifier).saved(widget.request.id, draft.id);
      unawaited(_showUploaded(engine, draft));
      return true;
    } catch (_) {
      if (mounted) setState(() => _saveState = 'Couldn’t save the draft');
      return false;
    }
  }

  /// Tells whether the server has [draft] too, once its upload was tried.
  Future<void> _showUploaded(MailEngine engine, LocalDraft draft) async {
    final bool uploaded;
    try {
      uploaded = await engine.uploadDraft(draft);
    } on Object {
      return;
    }
    // A later save tells of its own.
    if (!mounted || _lastSave != draft) return;
    setState(() => _saveState = uploaded ? 'Draft saved' : 'Saved on this device');
  }

  /// Keeps the draft in [accountId]: one kept in another account, before
  /// the message moved, is discarded there.
  Future<void> _leaveOtherAccount(MailEngine engine, String accountId) async {
    final previous = _draftAccount;
    _draftAccount = accountId;
    if (previous == null || previous == accountId) return;
    final (localId, draftId) = (_localId, _draftId);
    _localId = null;
    _draftId = null;
    if (localId != null || draftId != null) {
      await engine.discardDraft(previous, localId: localId, draftId: draftId);
    }
  }

  // Sending ------------------------------------------------------------------

  Account? get _account {
    final accounts = ref.read(accountMapProvider);
    return accounts[_accountId] ?? accounts.values.firstOrNull;
  }

  OutgoingMessage? _build() {
    final account = _account;
    if (account == null) return null;
    final quote = _quotedText;
    final typed = _plainText ? _plainBody.text.trimRight() : _body.document.toMailText();
    final signature = account.signature?.trim();
    return OutgoingMessage(
      accountId: account.id,
      from: Address(account.email, account.displayName),
      to: _to,
      cc: _cc,
      bcc: _bcc,
      subject: _subject.text.trim(),
      textBody: mailText(typed, signature: signature, quote: quote),
      htmlBody: _plainText
          ? null
          : mailHtml(_body.document.toMailHtml(), signature: signature, quote: quote),
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
    // A save still under way would leave its draft behind.
    await (_attachmentsLoaded, _saving).wait;
    if (!mounted) return;
    final account = _account;
    if (account == null) return;
    final engine = ref.read(engineProvider);
    await _leaveOtherAccount(engine, account.id);
    if (!mounted) return;
    final message = _build()!;
    if (message.subject.isEmpty &&
        !await _confirm('Send without a subject?', 'Send'))
      return;
    if (_mentionsAttachment(_bodyText) &&
        _attachments.isEmpty &&
        !await _confirm(
          'You mentioned an attachment, but nothing is attached. Send anyway?',
          'Send',
        )) {
      return;
    }
    _sending = true;
    _autosave?.cancel();
    final delay = Duration(seconds: ref.read(settingsProvider).undoSendSeconds);
    final outboxId = await engine.send(message, delay: delay, localDraftId: _localId);
    ref.read(composeProvider.notifier).close(widget.request.id, sent: true);
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
    final engine = ref.read(engineProvider);
    final empty = _isEmpty;
    ref.read(composeProvider.notifier).close(widget.request.id);
    // Whatever a save under way makes goes too.
    await _saving;
    final accountId = _draftAccount;
    if (accountId != null && (_localId != null || _draftId != null)) {
      try {
        await engine.discardDraft(accountId, localId: _localId, draftId: _draftId);
      } catch (_) {}
    }
    if (!empty) showSnack('Draft discarded');
  }

  /// Closes the window, keeping what was written as a draft. It is kept on
  /// this device until the server has it, and the snackbar opens it again.
  Future<void> _closeKeepingDraft() async {
    _autosave?.cancel();
    if (_isEmpty) {
      ref.read(composeProvider.notifier).close(widget.request.id);
      return;
    }
    final saved = await _saveDraft();
    if (!mounted) return;
    final message = _build();
    final localId = _localId;
    final composer = ref.read(composeProvider.notifier);
    final engine = ref.read(engineProvider);
    final offline = ref.read(syncStatusProvider).value?[message?.accountId]?.isOffline ?? false;
    composer.close(widget.request.id);
    // Drafts then shows it as the server has it.
    if (saved && message != null) unawaited(engine.flushDrafts(message.accountId));
    showSnack(
      !saved
          ? 'Couldn’t save the draft'
          : offline
          ? 'Draft saved on this device'
          : 'Draft saved',
      actionLabel: message == null ? null : 'Open',
      duration: saved ? null : const Duration(seconds: 10),
      onAction: message == null ? null : () => composer.reopen(message, localDraftId: localId),
    );
  }

  Future<bool> _confirm(String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
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
      added.add(
        OutgoingAttachment(
          filename: f.name,
          mimeType: _mimeFor(f.name),
          bytes: bytes,
        ),
      );
    }
    setState(() => _attachments = [..._attachments, ...added]);
    _scheduleSave();
  }

  // Formatting -----------------------------------------------------------------

  /// Runs a formatting [action] on the body and returns focus to it.
  void _format(VoidCallback action) {
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
        label: _body.document.getPlainText(
          range.start,
          range.end - range.start,
        ),
        url: existing == null ? '' : _body.linkAt(existing.start) ?? '',
        canRemove: existing != null,
      ),
    );
    if (result != null && mounted) _body.setLink(range, result.$1, result.$2);
    _bodyFocus.requestFocus();
  }

  /// Switches between formatted and plain text. Plain text keeps lists,
  /// quotes and links as text and drops the rest of the formatting.
  Future<void> _togglePlainText() async {
    if (!_plainText &&
        _body.document.hasFormatting &&
        !await _confirm(
          'Switching to plain text removes the formatting from this message.',
          'Switch',
        )) {
      return;
    }
    setState(() {
      if (_plainText) {
        _body.document = documentFromText(_plainBody.text);
      } else {
        _plainBody.text = _body.document.toMailText(marks: false);
      }
      _plainText = !_plainText;
    });
    _scheduleSave();
  }

  // UI -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(composeForwardProvider, (_, next) {
      if (next?.id != widget.request.id) return;
      setState(() => _minimized = false);
      if (_to.isEmpty) {
        _toKey.currentState?.focus();
      } else {
        _bodyFocus.requestFocus();
      }
    });
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final full = widget.fullScreen;
    final minimized = _minimized && !full;
    final width = full
        ? null
        : widget.maximized
        ? (size.width - 64).clamp(400.0, 1040.0)
        : 560.0;
    final height = full
        ? null
        : minimized
        ? 56.0
        : (widget.maximized
              ? size.height - 64
              : (size.height - 96).clamp(360.0, 640.0));
    final title = _subject.text.trim().isNotEmpty
        ? _subject.text.trim()
        : switch (widget.request.mode) {
            ComposeMode.fresh => 'New message',
            ComposeMode.reply || ComposeMode.replyAll => 'Reply',
            ComposeMode.forward => 'Forward',
          };

    final alignment = widget.maximized
        ? Alignment.center
        : full
        ? Alignment.bottomCenter
        : (widget.dockLeft ? Alignment.bottomLeft : Alignment.bottomRight);
    final canDrag = !widget.maximized && !full;

    // Tab follows the window's own fields, top to bottom. Ordered among
    // everything else on screen, it would leave from Subject for whatever
    // lies beside the window.
    final panel = FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: _animateIn ? 0 : 1, end: 1),
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
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(_closeKeepingDraft()),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            dragStartBehavior: DragStartBehavior.down,
            onPanUpdate: canDrag ? (details) => _handleDrag(details.delta) : null,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.maximized || full ? 0 : 16),
              child: AnimatedContainer(
                duration: Spring.spatial.duration,
                curve: Spring.spatial.curve,
                width: width,
                height: height,
                child: Material(
                  color: scheme.surfaceContainerLow,
                  elevation: full ? 0 : 8,
                  shadowColor: scheme.shadow.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: Corners.all(full ? 0 : Corners.extraLarge),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (minimized)
                        Expanded(
                          child: _TitleBar(
                            title: title,
                            minimized: minimized,
                            maximized: widget.maximized,
                            fullScreen: full,
                            onMinimize: () =>
                                setState(() => _minimized = !_minimized),
                            onMaximize: () => ref
                                .read(maximizedComposeProvider.notifier)
                                .set(widget.maximized ? null : widget.request.id),
                            onClose: () => unawaited(_closeKeepingDraft()),
                            onDrag: canDrag ? _handleDrag : null,
                          ),
                        )
                      else ...[
                        _TitleBar(
                          title: title,
                          minimized: minimized,
                          maximized: widget.maximized,
                          fullScreen: full,
                          onMinimize: () =>
                              setState(() => _minimized = !_minimized),
                          onMaximize: () => ref
                              .read(maximizedComposeProvider.notifier)
                              .set(widget.maximized ? null : widget.request.id),
                          onClose: () => unawaited(_closeKeepingDraft()),
                          onDrag: canDrag ? _handleDrag : null,
                        ),
                        Expanded(child: _form(theme)),
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

    if (widget.onDrag != null ||
        widget.maximized ||
        _dragOffset == Offset.zero) {
      return panel;
    }
    return Transform.translate(offset: _dragOffset, child: panel);
  }

  Widget _form(ThemeData theme) {
    final scheme = theme.colorScheme;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final divider = Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: scheme.outlineVariant.withValues(alpha: 0.5),
    );

    return Column(
      children: [
        if (accounts.length > 1) ...[
          _FromRow(
            accounts: accounts,
            selected: _accountId,
            locked: widget.request.threadId != null,
            onChanged: (id) {
              setState(() => _accountId = id);
              // Moves the draft over.
              _scheduleSave();
            },
          ),
          divider,
        ],
        RecipientField(
          key: _toKey,
          label: 'To',
          recipients: _to,
          onChanged: (v) {
            setState(() => _to = v);
            _scheduleSave();
          },
          trailing: _showCc
              ? null
              : TextButton(
                  onPressed: () => setState(() => _showCc = true),
                  child: const Text('Cc  Bcc'),
                ),
        ),
        divider,
        if (_showCc) ...[
          RecipientField(
            key: _ccKey,
            label: 'Cc',
            recipients: _cc,
            onChanged: (v) => setState(() => _cc = v),
          ),
          divider,
          RecipientField(
            key: _bccKey,
            label: 'Bcc',
            recipients: _bcc,
            onChanged: (v) => setState(() => _bcc = v),
          ),
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
                if (_plainText)
                  TextField(
                    controller: _plainBody,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    minLines: 8,
                    keyboardType: TextInputType.multiline,
                    style: theme.textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Write your message',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else
                  BodyEditor(
                    controller: _body,
                    focusNode: _bodyFocus,
                    scrollController: _bodyScroll,
                    onEditLink: () => unawaited(_editLink()),
                    onEscape: () => unawaited(_closeKeepingDraft()),
                    minHeight: 8 * (theme.textTheme.bodyLarge?.fontSize ?? 16) * 1.5,
                  ),
                if (_quotedText != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: _showQuote
                          ? 'Hide quoted text'
                          : 'Show quoted text',
                      child: ActionChip(
                        avatar: Icon(
                          _showQuote
                              ? Symbols.unfold_less_rounded
                              : Symbols.more_horiz_rounded,
                          size: 18,
                        ),
                        label: Text(
                          widget.request.mode == ComposeMode.forward
                              ? 'Forwarded message'
                              : 'Quoted text',
                        ),
                        onPressed: () =>
                            setState(() => _showQuote = !_showQuote),
                      ),
                    ),
                  ),
                  if (_showQuote)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: scheme.outlineVariant,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          _quotedText!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (_attachments.isNotEmpty || _loadingAttachments)
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
                      label: Text(
                        '${a.filename}  ·  ${fileSize(a.bytes.length)}',
                      ),
                      onDeleted: () => setState(
                        () => _attachments = [..._attachments]..remove(a),
                      ),
                    ),
                  ),
                if (_loadingAttachments)
                  const Center(child: LoadingIndicator(size: 32)),
              ],
            ),
          ),
        if (_showFormatting && !_plainText)
          FormatBar(
            controller: _body,
            onFormat: _format,
            onLink: () => unawaited(_editLink()),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 14),
          child: Row(
            children: [
              Tooltip(
                message: 'Send (Ctrl+Enter)',
                child: FilledButton.icon(
                  onPressed: _send,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(112, 48)),
                  ),
                  icon: const Icon(Symbols.send_rounded, size: 20),
                  label: const Text('Send'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: _plainText
                    ? 'Formatting is off in plain text mode'
                    : 'Formatting options',
                isSelected: _showFormatting && !_plainText,
                onPressed: _plainText
                    ? null
                    : () => setState(() => _showFormatting = !_showFormatting),
                icon: const Icon(Symbols.text_format_rounded),
              ),
              IconButton(
                tooltip: 'Attach files',
                onPressed: _attach,
                icon: const Icon(Symbols.attach_file_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _saveState,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
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
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  icon: const Icon(Symbols.more_vert_rounded),
                ),
              ),
              IconButton(
                tooltip: 'Discard draft',
                onPressed: _discard,
                icon: const Icon(Symbols.delete_rounded),
              ),
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
    required this.fullScreen,
    required this.onMinimize,
    required this.onMaximize,
    required this.onClose,
    this.onDrag,
  });

  final String title;
  final bool minimized;
  final bool maximized;
  final bool fullScreen;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onClose;
  final void Function(Offset delta)? onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canDrag = !maximized && onDrag != null;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: canDrag ? (details) => onDrag!(details.delta) : null,
        child: InkWell(
          onTap: minimized ? onMinimize : null,
          child: MouseRegion(
            cursor: canDrag
                ? SystemMouseCursors.move
                : SystemMouseCursors.basic,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmallEmphasized,
                    ),
                  ),
                  if (!fullScreen)
                    IconButton(
                      tooltip: minimized ? 'Restore' : 'Minimise',
                      onPressed: onMinimize,
                      icon: Icon(
                        minimized
                            ? Symbols.expand_less_rounded
                            : Symbols.minimize_rounded,
                        size: 20,
                      ),
                    ),
                  if (!minimized && !fullScreen)
                    IconButton(
                      tooltip: maximized ? 'Exit full size' : 'Full size',
                      onPressed: onMaximize,
                      icon: Icon(
                        maximized
                            ? Symbols.close_fullscreen_rounded
                            : Symbols.open_in_full_rounded,
                        size: 18,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Save & close (Esc)',
                    onPressed: onClose,
                    icon: const Icon(Symbols.close_rounded, size: 20),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits the text and address of a link.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({
    required this.label,
    required this.url,
    required this.canRemove,
  });

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
    Navigator.pop(context, (
      _label.text.isEmpty ? _url.text.trim() : _label.text,
      link,
    ));
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
                errorText: invalid
                    ? 'Enter a web address or an email address'
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canRemove)
          TextButton(
            onPressed: () => Navigator.pop(context, (widget.label, null)),
            child: const Text('Remove link'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _link == null ? null : _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _FromRow extends StatelessWidget {
  const _FromRow({
    required this.accounts,
    required this.selected,
    required this.locked,
    required this.onChanged,
  });

  final List<Account> accounts;
  final String? selected;
  final bool locked;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current =
        accounts.where((a) => a.id == selected).firstOrNull ?? accounts.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              'From',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          MenuAnchor(
            menuChildren: [
              for (final a in accounts)
                MenuItemButton(
                  leadingIcon: MorphAvatar(
                    name: a.displayName,
                    colorKey: a.email,
                    size: 28,
                  ),
                  onPressed: () => onChanged(a.id),
                  child: Text('${a.displayName}  <${a.email}>'),
                ),
            ],
            builder: (context, controller, _) => TextButton.icon(
              onPressed: locked
                  ? null
                  : () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
              iconAlignment: IconAlignment.end,
              icon: locked ? null : const Icon(Symbols.arrow_drop_down_rounded),
              label: Text(
                '${current.displayName} <${current.email}>',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _mentionsAttachment(String body) => RegExp(
  r'\b(attached|attachment|attaching|enclosed)\b',
  caseSensitive: false,
).hasMatch(body);

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
  '.docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls' => 'application/vnd.ms-excel',
  '.xlsx' =>
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt' => 'application/vnd.ms-powerpoint',
  '.pptx' =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.odt' => 'application/vnd.oasis.opendocument.text',
  '.ods' => 'application/vnd.oasis.opendocument.spreadsheet',
  '.mp3' => 'audio/mpeg',
  '.mp4' => 'video/mp4',
  _ => 'application/octet-stream',
};

/// Rough HTML to text for quoting.
String _htmlToText(String html) {
  var s = html
      .replaceAll(
        RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
        '',
      )
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
