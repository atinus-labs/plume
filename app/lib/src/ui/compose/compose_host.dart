import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:plume_core/plume_core.dart';
import 'package:plume_mime/plume_mime.dart' show MailtoLink;

import '../../state/mail.dart';
import '../../state/navigation.dart';
import 'compose_panel.dart';

enum ComposeMode { fresh, reply, replyAll, forward }

/// The initial content of a compose window.
@immutable
final class ComposeRequest {
  const ComposeRequest({
    required this.id,
    required this.mode,
    this.accountId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.html,
    this.plainText = false,
    this.quoted,
    this.threadId,
    this.inReplyTo,
    this.references = const [],
    this.draftId,
    this.forwardFrom,
    this.attachments = const [],
  });

  final int id;
  final ComposeMode mode;
  final String? accountId;
  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final String subject;
  final String body;

  /// Formatted body; takes the place of [body] when set.
  final String? html;

  /// Compose in plain text: no formatting and no HTML part.
  final bool plainText;

  /// The original message, quoted below the reply.
  final Message? quoted;
  final String? threadId;
  final String? inReplyTo;
  final List<String> references;
  final String? draftId;

  /// For forwards: the message whose attachments come along.
  final Message? forwardFrom;
  final List<OutgoingAttachment> attachments;
}

/// Open compose windows.
final composeProvider = NotifierProvider<ComposeNotifier, List<ComposeRequest>>(ComposeNotifier.new);

class ComposeNotifier extends Notifier<List<ComposeRequest>> {
  int _next = 1;

  @override
  List<ComposeRequest> build() => const [];

  String? _defaultAccount() {
    final view = ref.read(viewProvider);
    if (view.accountId != null) return view.accountId;
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    return accounts.isEmpty ? null : accounts.first.id;
  }

  void newMessage({List<Address> to = const []}) {
    // Only one blank message at a time; focus it instead of stacking.
    final blank = state.where((r) => r.mode == ComposeMode.fresh && r.to.isEmpty && to.isEmpty).firstOrNull;
    if (blank != null) return;
    _open(ComposeRequest(id: _next++, mode: ComposeMode.fresh, accountId: _defaultAccount(), to: to));
  }

  /// Opens a message prefilled from a `mailto:` link.
  void mailto(MailtoLink link) {
    if (link.isEmpty) return newMessage();
    _open(ComposeRequest(
      id: _next++,
      mode: ComposeMode.fresh,
      accountId: _defaultAccount(),
      to: link.to,
      cc: link.cc,
      bcc: link.bcc,
      subject: link.subject,
      body: link.body,
      inReplyTo: link.inReplyTo,
      references: [?link.inReplyTo],
    ));
  }

  void reply(Message m, {required bool all}) {
    final account = ref.read(accountMapProvider)[m.accountId];
    final me = account?.email.toLowerCase() ?? '';
    bool notMe(Address a) => a.email.toLowerCase() != me;
    final fromMe = m.from != null && !notMe(m.from!);

    final to = fromMe ? m.to : (m.replyTo.isNotEmpty ? m.replyTo : [?m.from]);
    final cc = all
        ? [...m.to, ...m.cc].where(notMe).where((a) => !to.any((t) => t.email.toLowerCase() == a.email.toLowerCase())).toList()
        : const <Address>[];
    _open(ComposeRequest(
      id: _next++,
      mode: all ? ComposeMode.replyAll : ComposeMode.reply,
      accountId: m.accountId,
      to: _dedupe(to),
      cc: _dedupe(cc),
      subject: _prefixed('Re:', m.subject),
      quoted: m,
      threadId: m.threadId,
      inReplyTo: m.messageIdHeader,
      references: [...m.references, ?m.messageIdHeader],
    ));
  }

  void forward(Message m) {
    _open(ComposeRequest(
      id: _next++,
      mode: ComposeMode.forward,
      accountId: m.accountId,
      subject: _prefixed('Fwd:', m.subject),
      quoted: m,
      forwardFrom: m,
    ));
  }

  /// Re-opens a message taken back by undo-send or a failed send.
  void reopen(OutgoingMessage message) {
    _open(ComposeRequest(
      id: _next++,
      mode: message.threadId == null ? ComposeMode.fresh : ComposeMode.reply,
      accountId: message.accountId,
      to: message.to,
      cc: message.cc,
      bcc: message.bcc,
      subject: message.subject,
      body: message.textBody,
      html: message.htmlBody,
      plainText: message.htmlBody == null,
      threadId: message.threadId,
      inReplyTo: message.inReplyTo,
      references: message.references,
      draftId: message.draftId,
      attachments: message.attachments,
    ));
  }

  void close(int id) => state = [for (final r in state) if (r.id != id) r];

  void _open(ComposeRequest request) {
    // At most three docked windows, like other desktop clients.
    final kept = state.length >= 3 ? state.sublist(state.length - 2) : state;
    state = [...kept, request];
  }

  static List<Address> _dedupe(List<Address> list) {
    final seen = <String>{};
    return [for (final a in list) if (seen.add(a.email.toLowerCase())) a];
  }

  static String _prefixed(String prefix, String subject) {
    final s = subject.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith(prefix.toLowerCase()) || (prefix == 'Fwd:' && lower.startsWith('fw:'))) return s;
    return '$prefix $s';
  }
}

/// `On Tue, 14 Oct 2025 at 10:42, Maya Chen <maya@…> wrote:`
String attributionLine(Message m) {
  final date = DateFormat("EEE, d MMM y 'at' HH:mm").format(m.date.toLocal());
  return 'On $date, ${m.from?.format() ?? 'someone'} wrote:';
}

/// The compose window shown maximised, if any.
final maximizedComposeProvider = NotifierProvider<_MaximizedNotifier, int?>(_MaximizedNotifier.new);

class _MaximizedNotifier extends Notifier<int?> {
  @override
  int? build() {
    // Forget the maximised window once it closes.
    ref.listen(composeProvider, (_, next) {
      if (state != null && !next.any((r) => r.id == state)) state = null;
    });
    return null;
  }

  void set(int? id) => state = id;
}

/// Floating compose windows docked to the bottom-right corner. A maximised
/// window moves to the centre over a scrim; its state survives the move
/// because each panel has a global key.
class ComposeHost extends ConsumerWidget {
  const ComposeHost({super.key});

  static final _keys = <int, GlobalKey>{};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(composeProvider);
    final maximized = ref.watch(maximizedComposeProvider);
    _keys.removeWhere((id, _) => !requests.any((r) => r.id == id));
    if (requests.isEmpty) return const SizedBox.shrink();
    GlobalKey keyFor(int id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'compose-$id'));
    final docked = requests.where((r) => r.id != maximized).toList();
    final big = requests.where((r) => r.id == maximized).firstOrNull;
    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            right: 16,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final r in docked)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: ComposePanel(key: keyFor(r.id), request: r, maximized: false),
                  ),
              ],
            ),
          ),
          if (big != null) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => ref.read(maximizedComposeProvider.notifier).set(null),
                child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.32)),
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: ComposePanel(key: keyFor(big.id), request: big, maximized: true),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
