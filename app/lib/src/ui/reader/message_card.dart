import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:plume_core/plume_core.dart';
import 'package:plume_design/plume_design.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/avatars.dart';
import '../../state/mail.dart';
import '../../state/services.dart';
import '../actions.dart';
import '../common/format.dart';
import '../compose/compose_host.dart';
import 'html_body.dart';

/// The colour of a message card, which simple HTML mail is rendered on.
Color messageCardColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.light ? scheme.surfaceContainerLow : scheme.surfaceContainer;

/// One message in a conversation. Collapsed messages show a single line;
/// expanding springs the body open.
class MessageCard extends ConsumerStatefulWidget {
  const MessageCard({
    super.key,
    required this.message,
    required this.initiallyExpanded,
    required this.index,
    required this.count,
    required this.myEmail,
  });

  final Message message;
  final bool initiallyExpanded;
  final int index;
  final int count;
  final String myEmail;

  @override
  ConsumerState<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends ConsumerState<MessageCard> {
  late bool _expanded = widget.initiallyExpanded;
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = widget.message;
    final from = m.from;
    final isMe = from?.email.toLowerCase() == widget.myEmail.toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: messageCardColor(scheme),
        shape: RoundedRectangleBorder(borderRadius: groupedRadius(widget.index, widget.count, outer: Corners.extraLarge, inner: Corners.small)),
        clipBehavior: Clip.antiAlias,
        // The card resizes while the two layouts cross-fade on top of each
        // other, so the content never jumps.
        child: AnimatedSize(
          duration: Spring.spatial.duration,
          curve: Spring.spatial.curve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Spring.effects.duration,
            layoutBuilder: (current, previous) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final p in previous) Positioned(top: 0, left: 0, right: 0, child: p),
                ?current,
              ],
            ),
            child: _expanded
                ? KeyedSubtree(key: const ValueKey('expanded'), child: _expandedView(theme, m, from, isMe))
                : KeyedSubtree(key: const ValueKey('collapsed'), child: _collapsedView(theme, m, from, isMe)),
          ),
        ),
      ),
    );
  }

  Widget _collapsedView(ThemeData theme, Message m, Address? from, bool isMe) => LayoutBuilder(
        builder: (context, constraints) => _collapsedRow(theme, m, from, isMe, narrow: constraints.maxWidth < _narrowCard),
      );

  Widget _collapsedRow(ThemeData theme, Message m, Address? from, bool isMe, {required bool narrow}) {
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            MorphAvatar(name: from?.displayName ?? '?', colorKey: from?.email ?? m.id, image: from?.email != null ? ref.watch(senderAvatarProvider(from!.email)).value : null, size: 32),
            const SizedBox(width: 14),
            SizedBox(
              width: narrow ? 104 : 160,
              child: Text(
                isMe ? 'me' : (from?.displayName ?? '(unknown)'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: m.isRead ? theme.textTheme.titleSmall : theme.textTheme.titleSmallEmphasized,
              ),
            ),
            Expanded(
              child: Text(m.snippet, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 12),
            Text(listDate(m.date), style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }

  Widget _expandedView(ThemeData theme, Message m, Address? from, bool isMe) => LayoutBuilder(
        builder: (context, constraints) => _expandedBody(theme, m, from, isMe, narrow: constraints.maxWidth < _narrowCard),
      );

  Widget _expandedBody(ThemeData theme, Message m, Address? from, bool isMe, {required bool narrow}) {
    final scheme = theme.colorScheme;
    final recipients = [...m.to, ...m.cc];
    String nameOf(Address a) => a.email.toLowerCase() == widget.myEmail.toLowerCase() ? 'me' : a.shortName;
    final toLine = recipients.isEmpty ? 'undisclosed recipients' : recipients.map(nameOf).join(', ');
    // Body and details line up with the sender's name.
    final indent = narrow ? 0.0 : 54.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.count > 1 ? () => setState(() => _expanded = false) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MorphAvatar(name: from?.displayName ?? '?', colorKey: from?.email ?? m.id, image: from?.email != null ? ref.watch(senderAvatarProvider(from!.email)).value : null, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Narrow cards keep the name; the address is one tap away in the details.
                      if (narrow)
                        Text(isMe ? 'me' : (from?.displayName ?? '(unknown sender)'),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmallEmphasized)
                      else
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(isMe ? 'me' : (from?.displayName ?? '(unknown sender)'), style: theme.textTheme.titleSmallEmphasized),
                            if (from != null)
                              SelectableText(from.email, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      const SizedBox(height: 2),
                      InkWell(
                        borderRadius: Corners.all(Corners.small),
                        onTap: () => setState(() => _details = !_details),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text('to $toLine', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ),
                            Icon(_details ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: fullDate(m.date),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(listDate(m.date), style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                    ),
                    IconButton(
                      tooltip: m.isFlagged ? 'Unstar' : 'Star',
                      onPressed: () => applyMessageAction(ref, m.isFlagged ? MailAction.unflag : MailAction.flag, m.accountId, [m.id]),
                      icon: Pop(
                        active: m.isFlagged,
                        child: Icon(Symbols.star_rounded, fill: m.isFlagged ? 1 : 0,
                            color: m.isFlagged ? const Color(0xFFE8A200) : scheme.onSurfaceVariant),
                      ),
                    ),
                    if (!narrow)
                      Builder(
                        builder: (context) => IconButton(
                          tooltip: 'Reply',
                          // The reply grows out of this button.
                          onPressed: () => ref.read(composeProvider.notifier).reply(m, all: false, origin: globalRectOf(context)),
                          icon: const Icon(Symbols.reply_rounded),
                        ),
                      ),
                    _MessageMenu(message: m),
                  ],
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: Spring.standard.duration,
            curve: Spring.standard.curve,
            alignment: Alignment.topCenter,
            child: _details ? _DetailsTable(message: m, indent: indent) : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.only(left: indent, right: 8),
            child: MessageBodyView(message: m),
          ),
          if (m.hasAttachments) ...[
            const SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.only(left: indent, right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final a in m.attachments.where((a) => !a.isInline)) AttachmentChip(message: m, attachment: a)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cards narrower than this (a narrow window, or a narrow reader beside the
/// list) drop the sender's address and the indent under the avatar, leaving
/// the width to the name and the message.
const _narrowCard = 520.0;

/// A draft in a conversation: who it is for and how it starts. Clicking it
/// opens it to carry on writing, in a window that grows out of the card.
class DraftCard extends ConsumerStatefulWidget {
  const DraftCard({
    super.key,
    required this.message,
    required this.index,
    required this.count,
    required this.myEmail,
  });

  final Message message;
  final int index;
  final int count;
  final String myEmail;

  @override
  ConsumerState<DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends ConsumerState<DraftCard> {
  bool _opening = false;

  Future<void> _edit() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await ref.read(composeProvider.notifier).openDraft(widget.message, origin: globalRectOf(context));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = widget.message;
    final from = m.from;
    final index = widget.index;
    final count = widget.count;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final recipients = [...m.to, ...m.cc, ...m.bcc];
    String nameOf(Address a) => a.email.toLowerCase() == widget.myEmail.toLowerCase() ? 'me' : a.shortName;
    void edit() => unawaited(_edit());
    // Fetched ahead, so the draft opens without waiting for it.
    ref.watch(bodyProvider((accountId: m.accountId, messageId: m.id)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: messageCardColor(scheme),
        shape: RoundedRectangleBorder(borderRadius: groupedRadius(index, count, outer: Corners.extraLarge, inner: Corners.small)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: edit,
          child: LayoutBuilder(builder: (context, constraints) {
            // The preview and buttons line up with the label, as a message's
            // body lines up with its sender.
            final indent = constraints.maxWidth < _narrowCard ? 0.0 : 54.0;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MorphAvatar(
                        name: from?.displayName ?? '?',
                        colorKey: from?.email ?? m.id,
                        image: from?.email != null ? ref.watch(senderAvatarProvider(from!.email)).value : null,
                        size: 40,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Draft', style: theme.textTheme.titleSmallEmphasized.copyWith(color: scheme.error)),
                            const SizedBox(height: 2),
                            Text(
                              recipients.isEmpty ? 'No recipients yet' : 'to ${recipients.map(nameOf).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: fullDate(m.date),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(listDate(m.date), style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                      ),
                    ],
                  ),
                  if (m.snippet.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(left: indent, top: 12, right: 8),
                      child: Text(m.snippet, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                    ),
                  Padding(
                    padding: EdgeInsets.only(left: indent, top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: edit,
                          // Opening waits for the draft when it was not
                          // fetched yet.
                          icon: _opening
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: OverflowBox(
                                    maxWidth: 28,
                                    maxHeight: 28,
                                    child: LoadingIndicator(size: 28, delay: Duration(milliseconds: 150)),
                                  ),
                                )
                              : const Icon(Symbols.edit_rounded, size: 20),
                          label: const Text('Edit'),
                        ),
                        TextButton.icon(
                          onPressed: () => unawaited(discardDraft(ref, m)),
                          icon: const Icon(Symbols.delete_rounded, size: 20),
                          label: const Text('Discard'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({required this.message, required this.indent});

  final Message message;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rows = <(String, String)>[
      if (message.from != null) ('From', message.from!.format()),
      if (message.to.isNotEmpty) ('To', message.to.map((a) => a.format()).join(', ')),
      if (message.cc.isNotEmpty) ('Cc', message.cc.map((a) => a.format()).join(', ')),
      if (message.bcc.isNotEmpty) ('Bcc', message.bcc.map((a) => a.format()).join(', ')),
      if (message.replyTo.isNotEmpty) ('Reply to', message.replyTo.map((a) => a.format()).join(', ')),
      ('Date', fullDate(message.date)),
      ('Subject', message.subject),
    ];
    return Padding(
      padding: EdgeInsets.only(left: indent, top: 12, right: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: Corners.all(Corners.large),
        ),
        child: Table(
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          children: [
            for (final (label, value) in rows)
              TableRow(children: [
                Padding(padding: const EdgeInsets.only(right: 16, bottom: 4), child: Text(label, style: muted)),
                Padding(padding: const EdgeInsets.only(bottom: 4), child: SelectableText(value, style: theme.textTheme.bodySmall)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _MessageMenu extends ConsumerWidget {
  const _MessageMenu({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compose = ref.read(composeProvider.notifier);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Symbols.reply_rounded), onPressed: () => compose.reply(message, all: false), child: const Text('Reply')),
        MenuItemButton(leadingIcon: const Icon(Symbols.reply_all_rounded), onPressed: () => compose.reply(message, all: true), child: const Text('Reply all')),
        MenuItemButton(leadingIcon: const Icon(Symbols.forward_rounded), onPressed: () => compose.forward(message), child: const Text('Forward')),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.mark_email_unread_rounded),
          onPressed: () => applyMessageAction(ref, MailAction.markUnread, message.accountId, [message.id]),
          child: const Text('Mark as unread'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.delete_rounded),
          onPressed: () => applyMessageAction(ref, MailAction.trash, message.accountId, [message.id]),
          child: const Text('Delete this message'),
        ),
        if (message.listUnsubscribe != null)
          MenuItemButton(
            leadingIcon: const Icon(Symbols.unsubscribe_rounded),
            onPressed: () => _unsubscribe(message.listUnsubscribe!),
            child: const Text('Unsubscribe'),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'More',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Symbols.more_vert_rounded),
      ),
    );
  }

  /// Opens the sender's unsubscribe link (preferring https over mailto).
  static Future<void> _unsubscribe(String header) async {
    final links = RegExp(r'<([^>]+)>').allMatches(header).map((m) => m.group(1)!).toList();
    final link = links.firstWhere((l) => l.startsWith('https://'), orElse: () => links.isEmpty ? '' : links.first);
    final uri = Uri.tryParse(link);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// A downloadable attachment.
class AttachmentChip extends ConsumerStatefulWidget {
  const AttachmentChip({super.key, required this.message, required this.attachment});

  final Message message;
  final AttachmentInfo attachment;

  @override
  ConsumerState<AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends ConsumerState<AttachmentChip> {
  bool _busy = false;

  IconData get _icon {
    final mime = widget.attachment.mimeType;
    if (mime.startsWith('image/')) return Symbols.image_rounded;
    if (mime == 'application/pdf') return Symbols.picture_as_pdf_rounded;
    if (mime.contains('spreadsheet') || mime.contains('excel') || mime.contains('csv')) return Symbols.table_chart_rounded;
    if (mime.contains('presentation') || mime.contains('powerpoint')) return Symbols.slideshow_rounded;
    if (mime.contains('word') || mime.startsWith('text/')) return Symbols.description_rounded;
    if (mime.contains('zip') || mime.contains('compressed') || mime.contains('tar')) return Symbols.folder_zip_rounded;
    if (mime.startsWith('audio/')) return Symbols.audio_file_rounded;
    if (mime.startsWith('video/')) return Symbols.video_file_rounded;
    return Symbols.draft_rounded;
  }

  Future<File?> _download({bool ask = false}) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(engineProvider).attachment(widget.message.accountId, widget.message.id, widget.attachment);
      String? path;
      if (ask) {
        final location = await getSaveLocation(suggestedName: widget.attachment.filename);
        path = location?.path;
        if (path == null) return null;
      } else {
        final downloads = Platform.environment['XDG_DOWNLOAD_DIR'] ?? p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
        await Directory(downloads).create(recursive: true);
        path = _unique(p.join(downloads, _safeName(widget.attachment.filename)));
      }
      final file = File(path);
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      showSnack('Couldn’t download ${widget.attachment.filename}');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[/\\\x00]'), '_').trim();
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  static String _unique(String path) {
    if (!File(path).existsSync()) return path;
    final ext = p.extension(path);
    final base = path.substring(0, path.length - ext.length);
    for (var i = 1;; i++) {
      final candidate = '$base ($i)$ext';
      if (!File(candidate).existsSync()) return candidate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = widget.attachment;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.large)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy
            ? null
            : () async {
                final file = await _download();
                if (file != null) await launchUrl(Uri.file(file.path));
              },
        child: SizedBox(
          width: 248,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Material(
                    color: scheme.tertiaryContainer,
                    shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.medium)),
                    child: _busy
                        ? const Padding(padding: EdgeInsets.all(6), child: LoadingIndicator(size: 28))
                        : Icon(_icon, color: scheme.onTertiaryContainer, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLargeEmphasized),
                      Text(fileSize(a.size), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Save as…',
                  onPressed: _busy
                      ? null
                      : () async {
                          final file = await _download(ask: true);
                          if (file != null) showSnack('Saved ${p.basename(file.path)}');
                        },
                  icon: const Icon(Symbols.download_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
