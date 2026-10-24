import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_imap/src/imap/imap_fetch.dart';
import 'package:plume_imap/src/imap/imap_response.dart';
import 'package:plume_imap/src/imap/mutf7.dart';
import 'package:plume_imap/src/imap/uid_set.dart';
import 'package:plume_imap/src/settings.dart';
import 'package:plume_mime/plume_mime.dart';

import 'server_connection.dart';

/// A message stored on the fake server.
final class FakeMessage {
  FakeMessage(
    this.raw, {
    Set<String>? flags,
    DateTime? internalDate,
    this.gmailId,
    this.gmailThreadId,
    Set<String>? labels,
    Set<String>? categories,
  })  : flags = flags ?? {},
        labels = labels ?? {},
        categories = categories ?? {},
        internalDate = internalDate ?? DateTime.utc(2026, 3, 1, 9);

  final Uint8List raw;
  Set<String> flags;
  final DateTime internalDate;
  int modseq = 1;

  /// Gmail: X-GM-MSGID / X-GM-THRID and labels (`\Inbox`, `Work`...).
  BigInt? gmailId;
  BigInt? gmailThreadId;
  Set<String> labels;

  /// Gmail categories: `social`, `promotions`, `updates`, `forums`.
  Set<String> categories;

  late final RawPart root = RawPart.parse(latin1.decode(raw));

  String get text => latin1.decode(raw);
}

/// A folder. Gmail label folders are views over All Mail ([viewLabel]).
final class FakeMailbox {
  FakeMailbox(this.name, {this.attributes = const {}, this.uidValidity = 1000, this.viewLabel, this.noselect = false});

  final String name;
  final Set<String> attributes;
  int uidValidity;
  int uidNext = 1;
  final String? viewLabel;
  final bool noselect;

  /// Whether LIST shows it (Gmail lets users hide labels from IMAP).
  bool listed = true;
  final entries = <(int, FakeMessage)>[];
  final viewUids = <FakeMessage, int>{};
  final expunged = <(int uid, int modseq)>[];

  bool get isView => viewLabel != null;
}

/// One client session's state on the server.
final class _Session {
  _Session(this.conn);

  final ServerConnection conn;
  bool authenticated = false;
  bool utf8 = false;
  bool condstore = false;
  bool qresync = false;
  FakeMailbox? selected;
  bool readOnly = false;

  /// STATUS of [selected] as of SELECT: like Dovecot, a session sees its
  /// selected mailbox's state as of its last sync point.
  Map<String, String>? selectedStatus;
  ReceivedCommand? idling;
}

/// A scripted-in-behaviour IMAP server for provider tests: real sockets,
/// real protocol, mailboxes in memory. Generic mode mimics Dovecot; Gmail
/// mode mimics Gmail's label folders, All Mail and X-GM-EXT-1.
final class FakeImapServer {
  FakeImapServer._(this._server, {required this.gmail, required this.capabilities, required this.username, required this.password}) {
    _server.listen((socket) {
      final conn = ServerConnection(socket);
      connectionsOpened++;
      final session = _Session(conn);
      _sessions.add(session);
      unawaited(_serve(session).whenComplete(() {
        _sessions.remove(session);
        unawaited(conn.close());
      }));
    });
    if (gmail) {
      for (final (name, attrs, label) in [
        ('INBOX', <String>{}, r'\Inbox'),
        ('[Gmail]/All Mail', {r'\All'}, null),
        ('[Gmail]/Drafts', {r'\Drafts'}, r'\Draft'),
        ('[Gmail]/Important', {r'\Important'}, r'\Important'),
        ('[Gmail]/Sent Mail', {r'\Sent'}, r'\Sent'),
        ('[Gmail]/Spam', {r'\Junk'}, null),
        ('[Gmail]/Starred', {r'\Flagged'}, r'\Starred'),
        ('[Gmail]/Trash', {r'\Trash'}, null),
      ]) {
        mailboxes[name] = FakeMailbox(name, attributes: attrs, viewLabel: label, uidValidity: 7 + mailboxes.length);
      }
      mailboxes['[Gmail]'] = FakeMailbox('[Gmail]', noselect: true);
    } else {
      for (final (name, attrs) in [
        ('INBOX', <String>{}),
        ('Sent', {r'\Sent'}),
        ('Drafts', {r'\Drafts'}),
        ('Trash', {r'\Trash'}),
        ('Junk', {r'\Junk'}),
      ]) {
        mailboxes[name] = FakeMailbox(name, attributes: attrs, uidValidity: 100 + mailboxes.length);
      }
    }
  }

  static const genericCapabilities = {
    'IMAP4rev1', 'LITERAL+', 'SASL-IR', 'ID', 'ENABLE', 'IDLE', 'UIDPLUS', 'MOVE', 'ESEARCH', 'SPECIAL-USE', //
    'LIST-EXTENDED', 'LIST-STATUS', 'CONDSTORE', 'NAMESPACE', 'UNSELECT', 'AUTH=PLAIN',
  };

  static const gmailCapabilities = {
    'IMAP4rev1', 'UNSELECT', 'IDLE', 'NAMESPACE', 'QUOTA', 'ID', 'XLIST', 'CHILDREN', 'X-GM-EXT-1', 'UIDPLUS', //
    'ENABLE', 'MOVE', 'CONDSTORE', 'ESEARCH', 'UTF8=ACCEPT', 'LIST-EXTENDED', 'LIST-STATUS', 'LITERAL-',
    'SPECIAL-USE', 'AUTH=PLAIN', 'SASL-IR',
  };

  static Future<FakeImapServer> start({
    bool gmail = false,
    Set<String>? capabilities,
    String username = 'ana@example.org',
    String password = 'secret',
  }) async =>
      FakeImapServer._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        gmail: gmail,
        capabilities: capabilities ?? (gmail ? gmailCapabilities : genericCapabilities),
        username: username,
        password: password,
      );

  final ServerSocket _server;
  final bool gmail;
  Set<String> capabilities;
  final String username;
  String password;
  final mailboxes = <String, FakeMailbox>{};
  final _sessions = <_Session>[];
  int connectionsOpened = 0;
  int _modseq = 10;
  BigInt _nextGmailId = BigInt.parse('1800000000000000000');

  /// Every command received (`NAME args`), across connections.
  final log = <String>[];

  /// Answers a command instead of the server (return true when handled).
  bool Function(ReceivedCommand cmd, ServerConnection conn)? intercept;

  /// Commands to never answer (for timeout tests), by name.
  final hang = <String>{};

  int get port => _server.port;
  int get openConnections => _sessions.length;

  ServerEndpoint get endpoint => ServerEndpoint(host: '127.0.0.1', port: port, security: ConnectionSecurity.none);

  Future<void> close() async {
    await _server.close();
    for (final s in [..._sessions]) {
      await s.conn.close();
    }
  }

  /// Commands logged with [name] (e.g. `UID MOVE`).
  List<String> commands(String name) => [for (final l in log) if (l == name || l.startsWith('$name ')) l];

  void clearLog() => log.clear();

  // Test helpers ------------------------------------------------------------

  FakeMailbox addMailbox(String name, {Set<String> attributes = const {}}) {
    final box = gmail
        ? FakeMailbox(name, attributes: attributes, viewLabel: name, uidValidity: 500 + mailboxes.length)
        : FakeMailbox(name, attributes: attributes, uidValidity: 100 + mailboxes.length);
    return mailboxes[name] = box;
  }

  FakeMailbox get allMail => mailboxes['[Gmail]/All Mail']!;

  /// Adds a message. In Gmail mode [mailbox] is All Mail, Trash or Spam
  /// for real folders, or a label folder (the label is added).
  FakeMessage deliver(
    String mailbox,
    String raw, {
    Set<String>? flags,
    DateTime? date,
    Set<String> labels = const {},
    Set<String> categories = const {},
    BigInt? threadId,
  }) {
    final bytes = Uint8List.fromList(utf8.encode(raw.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')));
    // Arrival time: as given, else the Date header (as if delivered then).
    final arrival = date ?? parseRfc5322Date(RawPart.parse(latin1.decode(bytes)).headerValue('Date'));
    final m = FakeMessage(bytes, flags: flags, internalDate: arrival, categories: {...categories});
    if (gmail) {
      m.gmailId = _nextGmailId;
      _nextGmailId += BigInt.one;
      m.gmailThreadId = threadId ?? m.gmailId;
      m.labels = {...labels};
    }
    _add(mailboxes[mailbox]!, m);
    return m;
  }

  void _add(FakeMailbox box, FakeMessage m) {
    m.modseq = ++_modseq;
    if (box.isView) {
      m.labels.add(box.viewLabel!);
      _add(allMail, m);
      return;
    }
    box.entries.add((box.uidNext++, m));
    _notify(box);
    if (gmail && box == allMail) {
      for (final v in mailboxes.values.where((v) => v.isView)) {
        _notify(v);
      }
    }
  }

  /// Contents in UID order. Views assign their own UIDs lazily, in All
  /// Mail order, like Gmail's label folders.
  List<(int, FakeMessage)> contents(FakeMailbox box) {
    if (!box.isView) return box.entries;
    final out = <(int, FakeMessage)>[];
    for (final (_, m) in allMail.entries) {
      if (!m.labels.contains(box.viewLabel)) continue;
      final uid = box.viewUids.putIfAbsent(m, () => box.uidNext++);
      out.add((uid, m));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// Removes messages from [box] (expunge). In a Gmail view this removes
  /// the label; in All Mail, Trash or Spam it deletes.
  void remove(FakeMailbox box, Iterable<FakeMessage> messages) => _remove(box, messages);

  void _remove(FakeMailbox box, Iterable<FakeMessage> messages, {_Session? actor}) {
    final set = messages.toSet();
    final before = contents(box);
    final seqs = [for (var i = 0; i < before.length; i++) if (set.contains(before[i].$2)) i + 1].reversed.toList();
    if (box.isView) {
      for (final m in set) {
        m.labels.remove(box.viewLabel);
        m.modseq = ++_modseq;
        final uid = box.viewUids.remove(m);
        if (uid != null) box.expunged.add((uid, _modseq));
      }
    } else {
      for (final e in [...box.entries]) {
        if (set.contains(e.$2)) {
          box.entries.remove(e);
          box.expunged.add((e.$1, ++_modseq));
        }
      }
      if (gmail && box == allMail) {
        for (final v in mailboxes.values.where((v) => v.isView)) {
          for (final m in set) {
            final uid = v.viewUids.remove(m);
            if (uid != null) v.expunged.add((uid, _modseq));
          }
        }
      }
    }
    for (final s in _sessions) {
      if (s.selected != box) continue;
      if (s == actor || s.idling != null) {
        for (final seq in seqs) {
          s.conn.send('* $seq EXPUNGE');
        }
      }
    }
  }

  /// Changes flags as another client would.
  void setFlags(FakeMessage m, Set<String> flags) {
    m.flags = flags;
    m.modseq = ++_modseq;
  }

  /// Gmail: changes labels as another client would.
  void setLabels(FakeMessage m, Set<String> labels) {
    m.labels = labels;
    m.modseq = ++_modseq;
  }

  /// Gmail: moves a message between All Mail, Trash and Spam as the web
  /// interface would.
  void gmailMove(FakeMessage m, String from, String to) {
    remove(mailboxes[from]!, [m]);
    if (to != allMail.name) m.labels.clear();
    _add(mailboxes[to]!, m);
  }

  /// Gives a folder a new UIDVALIDITY with renumbered messages.
  void resetUidValidity(String name) {
    final box = mailboxes[name]!;
    final messages = [for (final e in box.entries) e.$2];
    box
      ..uidValidity += 1000
      ..uidNext = 1
      ..entries.clear();
    for (final m in messages) {
      box.entries.add((box.uidNext++, m));
    }
  }

  int highestModSeq(FakeMailbox box) {
    var h = 1;
    for (final (_, m) in contents(box)) {
      if (m.modseq > h) h = m.modseq;
    }
    for (final (_, ms) in box.expunged) {
      if (ms > h) h = ms;
    }
    return h;
  }

  void _notify(FakeMailbox box) {
    for (final s in _sessions) {
      if (s.selected == box && s.idling != null) s.conn.send('* ${contents(box).length} EXISTS');
    }
  }

  // Protocol ----------------------------------------------------------------

  String get _capabilityLine => capabilities.join(' ');

  Future<void> _serve(_Session s) async {
    final c = s.conn;
    c.send('* OK [CAPABILITY $_capabilityLine] Fake IMAP ready');
    while (true) {
      final cmd = await c.readCommand();
      if (cmd == null) return;
      log.add(cmd.args.isEmpty ? cmd.name : '${cmd.name} ${cmd.args}');
      if (hang.contains(cmd.name)) continue;
      if (intercept?.call(cmd, c) ?? false) continue;
      try {
        if (!await _handle(s, cmd)) return;
      } on _Bad catch (e) {
        c.send('${cmd.tag} BAD ${e.message}');
      } on SocketException {
        return; // The client went away mid-command (e.g. during IDLE).
      }
    }
  }

  /// Arguments of a command, parsed with the client's own response parser.
  static List<ImapValue> _args(ReceivedCommand cmd) {
    final pieces = <String>[];
    var rest = cmd.args;
    final marker = RegExp(r'\{\d+\}');
    while (true) {
      final m = marker.firstMatch(rest);
      if (m == null) break;
      pieces.add(rest.substring(0, m.end));
      rest = rest.substring(m.end);
    }
    pieces.add(rest);
    final lines = ['* X ${pieces.first}', ...pieces.skip(1)];
    return ImapParser.parse(RawResponse(lines, cmd.literals)).data;
  }

  String _decodeName(_Session s, String name) =>
      name.toUpperCase() == 'INBOX' ? 'INBOX' : (s.utf8 ? name : ModifiedUtf7.decode(name));

  String _encodeName(_Session s, String name) => s.utf8 ? name : ModifiedUtf7.encode(name);

  Future<bool> _handle(_Session s, ReceivedCommand cmd) async {
    final c = s.conn;
    final tag = cmd.tag;
    final args = _args(cmd);
    switch (cmd.name) {
      case 'CAPABILITY':
        c
          ..send('* CAPABILITY $_capabilityLine')
          ..send('$tag OK CAPABILITY completed');
      case 'NOOP':
        c.send('$tag OK NOOP completed');
      case 'LOGOUT':
        c
          ..send('* BYE logging out')
          ..send('$tag OK LOGOUT completed');
        return false;
      case 'ID':
        c
          ..send('* ID ("name" "FakeIMAP")')
          ..send('$tag OK ID completed');
      case 'LOGIN':
        _login(s, tag, args[0].text ?? '', args[1].text ?? '');
      case 'AUTHENTICATE':
        var payload = args.length > 1 ? args[1].text : null;
        if (payload == null) {
          c.send('+ ');
          payload = await c.readLine();
        }
        final parts = utf8.decode(base64.decode(payload)).split('\u0000');
        _login(s, tag, parts.length > 1 ? parts[1] : '', parts.length > 2 ? parts[2] : '');
      case 'ENABLE':
        final enabled = <String>[];
        for (final a in args) {
          final cap = a.text!.toUpperCase();
          if (!capabilities.contains(cap)) continue;
          enabled.add(cap);
          if (cap == 'UTF8=ACCEPT') s.utf8 = true;
          if (cap == 'CONDSTORE') s.condstore = true;
          if (cap == 'QRESYNC') {
            s
              ..qresync = true
              ..condstore = true;
          }
        }
        c
          ..send('* ENABLED ${enabled.join(' ')}')
          ..send('$tag OK ENABLE completed');
      case 'NAMESPACE':
        c
          ..send('* NAMESPACE (("" "/")) NIL NIL')
          ..send('$tag OK NAMESPACE completed');
      case 'LIST':
        _list(s, tag, args);
      case 'STATUS':
        final box = mailboxes[_decodeName(s, args[0].text!)];
        if (box == null || box.noselect) {
          c.send('$tag NO [NONEXISTENT] No such mailbox');
        } else {
          c
            ..send('* STATUS ${_quote(_encodeName(s, box.name))} (${_statusFor(s, box, [for (final v in args[1].items) v.text!])})')
            ..send('$tag OK STATUS completed');
        }
      case 'SELECT' || 'EXAMINE':
        _select(s, cmd, args);
      case 'UNSELECT' || 'CLOSE':
        s
          ..selected = null
          ..selectedStatus = null;
        c.send('$tag OK done');
      case 'CREATE':
        final name = _decodeName(s, args[0].text!);
        if (mailboxes.containsKey(name)) {
          c.send('$tag NO [ALREADYEXISTS] Mailbox exists');
        } else {
          addMailbox(name);
          c.send('$tag OK CREATE completed');
        }
      case 'SUBSCRIBE':
        c.send('$tag OK SUBSCRIBE completed');
      case 'APPEND':
        _append(s, tag, args);
      case 'IDLE':
        s.idling = cmd;
        c.send('+ idling');
        final done = await c.readLine();
        s.idling = null;
        if (done.toUpperCase() != 'DONE') throw _Bad('Expected DONE');
        c.send('$tag OK IDLE terminated');
      case 'FETCH' || 'UID FETCH':
        _fetch(s, tag, args, byUid: cmd.name.startsWith('UID'));
      case 'UID SEARCH' || 'SEARCH':
        _search(s, tag, args, byUid: cmd.name.startsWith('UID'));
      case 'UID STORE' || 'STORE':
        _store(s, tag, args);
      case 'UID MOVE' || 'UID COPY':
        _moveOrCopy(s, tag, args, move: cmd.name == 'UID MOVE');
      case 'EXPUNGE' || 'UID EXPUNGE':
        final box = _requireSelected(s);
        final restrict = cmd.name == 'UID EXPUNGE' ? UidSet.parse(args[0].text!) : null;
        final victims = [
          for (final (uid, m) in contents(box))
            if (m.flags.contains(r'\Deleted') && (restrict == null || restrict.contains(uid))) m,
        ];
        _remove(box, victims, actor: s);
        c.send('$tag OK EXPUNGE completed');
      default:
        c.send('$tag BAD Unknown command ${cmd.name}');
    }
    return true;
  }

  void _login(_Session s, String tag, String user, String pass) {
    if (user == username && pass == password) {
      s.authenticated = true;
      s.conn.send('$tag OK [CAPABILITY $_capabilityLine] Logged in');
    } else {
      s.conn.send(gmail
          ? '$tag NO [ALERT] Application-specific password required: https://support.google.com/accounts/answer/185833 (Failure)'
          : '$tag NO [AUTHENTICATIONFAILED] Authentication failed.');
    }
  }

  FakeMailbox _requireSelected(_Session s) => s.selected ?? (throw _Bad('No mailbox selected'));

  static String _quote(String s) {
    if (s.codeUnits.any((u) => u > 0x7E || u < 0x20)) {
      final bytes = utf8.encode(s);
      return '{${bytes.length}}\r\n${utf8.decode(bytes)}';
    }
    return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  String _statusFor(_Session s, FakeMailbox box, List<String> items) {
    final cached = s.selected == box ? s.selectedStatus : null;
    if (cached == null) return _status(box, items);
    return [for (final i in items) cached[i.toUpperCase()] ?? _status(box, [i])].join(' ');
  }

  String _status(FakeMailbox box, List<String> items) {
    final list = contents(box);
    return [
      for (final i in items)
        switch (i.toUpperCase()) {
          'MESSAGES' => 'MESSAGES ${list.length}',
          'UIDNEXT' => 'UIDNEXT ${box.isView ? _viewNext(box) : box.uidNext}',
          'UIDVALIDITY' => 'UIDVALIDITY ${box.uidValidity}',
          'UNSEEN' => 'UNSEEN ${list.where((e) => !e.$2.flags.contains(r'\Seen')).length}',
          'HIGHESTMODSEQ' => 'HIGHESTMODSEQ ${highestModSeq(box)}',
          'RECENT' => 'RECENT 0',
          _ => throw _Bad('Unknown status item $i'),
        },
    ].join(' ');
  }

  int _viewNext(FakeMailbox box) {
    contents(box); // assigns pending UIDs
    return box.uidNext;
  }

  void _list(_Session s, String tag, List<ImapValue> args) {
    final returns = args.length > 3 ? args[3].items : const <ImapValue>[];
    List<String>? statusItems;
    for (var i = 0; i < returns.length; i++) {
      if (returns[i].text?.toUpperCase() == 'STATUS' && i + 1 < returns.length) {
        statusItems = [for (final v in returns[i + 1].items) v.text!];
      }
    }
    final names = mailboxes.keys.toList()..sort((a, b) => a == 'INBOX' ? -1 : (b == 'INBOX' ? 1 : a.compareTo(b)));
    for (final name in names) {
      final box = mailboxes[name]!;
      if (!box.listed) continue;
      final attrs = {...box.attributes, if (box.noselect) r'\Noselect'};
      s.conn.send('* LIST (${attrs.join(' ')}) "/" ${_quote(_encodeName(s, name))}');
      if (statusItems != null && !box.noselect) {
        s.conn.send('* STATUS ${_quote(_encodeName(s, name))} (${_statusFor(s, box, statusItems)})');
      }
    }
    s.conn.send('$tag OK LIST completed');
  }

  void _select(_Session s, ReceivedCommand cmd, List<ImapValue> args) {
    final c = s.conn;
    final box = mailboxes[_decodeName(s, args[0].text!)];
    if (box == null || box.noselect) {
      s.selected = null;
      c.send('${cmd.tag} NO [NONEXISTENT] Mailbox does not exist');
      return;
    }
    const items = ['MESSAGES', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN', 'HIGHESTMODSEQ'];
    s
      ..selected = box
      ..readOnly = cmd.name == 'EXAMINE'
      ..selectedStatus = {for (final i in items) i: _status(box, [i])};
    final list = contents(box);
    c
      ..send(r'* FLAGS (\Answered \Flagged \Deleted \Seen \Draft)')
      ..send(r'* OK [PERMANENTFLAGS (\Answered \Flagged \Deleted \Seen \Draft \*)] Flags permitted.')
      ..send('* ${list.length} EXISTS')
      ..send('* 0 RECENT')
      ..send('* OK [UIDVALIDITY ${box.uidValidity}] UIDs valid')
      ..send('* OK [UIDNEXT ${box.isView ? _viewNext(box) : box.uidNext}] Predicted next UID');
    if (s.condstore || capabilities.contains('CONDSTORE')) c.send('* OK [HIGHESTMODSEQ ${highestModSeq(box)}] Highest');
    if (args.length > 1 && s.qresync) {
      final params = args[1].items;
      for (var i = 0; i < params.length; i++) {
        if (params[i].text?.toUpperCase() != 'QRESYNC' || i + 1 >= params.length) continue;
        final q = params[i + 1].items;
        final uv = q[0].asInt;
        final since = q[1].asInt!;
        final known = q.length > 2 ? UidSet.parse(q[2].text!) : null;
        if (uv == box.uidValidity) {
          final gone = [
            for (final (uid, ms) in box.expunged)
              if (ms > since && (known == null || known.contains(uid))) uid,
          ];
          if (gone.isNotEmpty) c.send('* VANISHED (EARLIER) ${UidSet.of(gone)}');
          for (var k = 0; k < list.length; k++) {
            final (uid, m) = list[k];
            if (m.modseq > since) c.send('* ${k + 1} FETCH (UID $uid FLAGS (${m.flags.join(' ')}) MODSEQ (${m.modseq}))');
          }
        }
      }
    }
    c.send('${cmd.tag} OK [${s.readOnly ? 'READ-ONLY' : 'READ-WRITE'}] ${cmd.name} completed');
  }

  void _append(_Session s, String tag, List<ImapValue> args) {
    final box = mailboxes[_decodeName(s, args[0].text!)];
    if (box == null) {
      s.conn.send('$tag NO [TRYCREATE] Mailbox does not exist');
      return;
    }
    var flags = <String>{};
    DateTime? date;
    Uint8List? data;
    for (final a in args.skip(1)) {
      if (a is ImapList) flags = {for (final f in a.items) f.text!};
      if (a is ImapString && a.isLiteral) data = a.bytes;
      if (a is ImapString && !a.isLiteral) date = parseInternalDate(a.text);
    }
    final m = FakeMessage(data!, flags: flags, internalDate: date ?? DateTime.now().toUtc());
    if (gmail) {
      m.gmailId = _nextGmailId;
      _nextGmailId += BigInt.one;
      m.gmailThreadId = m.gmailId;
    }
    _add(box, m);
    if (box.isView) contents(box); // assigns the view UID
    final uid = box.isView ? box.viewUids[m]! : box.entries.last.$1;
    s.conn.send('$tag OK [APPENDUID ${box.uidValidity} $uid] APPEND completed');
  }

  /// Resolves a sequence/UID set against the selected mailbox.
  List<(int seq, int uid, FakeMessage m)> _resolve(FakeMailbox box, String set, {required bool byUid}) {
    final list = contents(box);
    if (list.isEmpty) return const [];
    final maxValue = byUid ? list.last.$1 : list.length;
    final ranges = <(int, int)>[];
    for (final piece in set.split(',')) {
      int value(String v) => v == '*' ? maxValue : int.parse(v);
      final colon = piece.indexOf(':');
      if (colon < 0) {
        final v = value(piece);
        ranges.add((v, v));
      } else {
        final a = value(piece.substring(0, colon));
        final b = value(piece.substring(colon + 1));
        ranges.add(a <= b ? (a, b) : (b, a));
      }
    }
    bool inSet(int v) => ranges.any((r) => v >= r.$1 && v <= r.$2);
    return [
      for (var i = 0; i < list.length; i++)
        if (inSet(byUid ? list[i].$1 : i + 1)) (i + 1, list[i].$1, list[i].$2),
    ];
  }

  void _fetch(_Session s, String tag, List<ImapValue> args, {required bool byUid}) {
    final box = _requireSelected(s);
    final items = args[1] is ImapList ? args[1].items.map((v) => v.text!).toList() : [args[1].text!];
    int? changedSince;
    var vanished = false;
    if (args.length > 2) {
      final mods = args[2].items;
      for (var i = 0; i < mods.length; i++) {
        final k = mods[i].text?.toUpperCase();
        if (k == 'CHANGEDSINCE') changedSince = mods[i + 1].asInt;
        if (k == 'VANISHED') vanished = true;
      }
    }
    if (vanished && changedSince != null && s.qresync) {
      final set = UidSet.parse(args[0].text!.replaceAll('*', '999999999'));
      final gone = [for (final (uid, ms) in box.expunged) if (ms > changedSince && set.contains(uid)) uid];
      if (gone.isNotEmpty) s.conn.send('* VANISHED (EARLIER) ${UidSet.of(gone)}');
    }
    for (final (seq, uid, m) in _resolve(box, args[0].text!, byUid: byUid)) {
      if (changedSince != null && m.modseq <= changedSince) continue;
      final parts = <String>[];
      final literals = <List<int>>[];
      void addString(String key, List<int> bytes) {
        parts.add('$key {${bytes.length}}');
        literals.add(bytes);
      }

      final names = [...items];
      if (byUid && !names.any((n) => n.toUpperCase() == 'UID')) names.insert(0, 'UID');
      if (changedSince != null && !names.any((n) => n.toUpperCase() == 'MODSEQ')) names.add('MODSEQ');
      for (final item in names) {
        final upper = item.toUpperCase();
        switch (upper) {
          case 'UID':
            parts.add('UID $uid');
          case 'FLAGS':
            parts.add('FLAGS (${m.flags.join(' ')})');
          case 'INTERNALDATE':
            parts.add('INTERNALDATE "${formatInternalDate(m.internalDate)}"');
          case 'RFC822.SIZE':
            parts.add('RFC822.SIZE ${m.raw.length}');
          case 'MODSEQ':
            parts.add('MODSEQ (${m.modseq})');
          case 'X-GM-MSGID':
            parts.add('X-GM-MSGID ${m.gmailId}');
          case 'X-GM-THRID':
            parts.add('X-GM-THRID ${m.gmailThreadId}');
          case 'X-GM-LABELS':
            final labels = [for (final l in m.labels) l.startsWith(r'\') ? l : _quote(_encodeName(s, l))];
            parts.add('X-GM-LABELS (${labels.join(' ')})');
          case 'ENVELOPE':
            parts.add('ENVELOPE ${_envelope(m.root)}');
          case 'BODYSTRUCTURE':
            parts.add('BODYSTRUCTURE ${_bodyStructure(m.root)}');
          default:
            if (upper.startsWith('BODY[') || upper.startsWith('BODY.PEEK[')) {
              final open = item.indexOf('[');
              final close = item.indexOf(']');
              final section = item.substring(open + 1, close);
              final partial = RegExp(r'<(\d+)\.(\d+)>$').firstMatch(item);
              var bytes = _section(m, section);
              var key = 'BODY[$section]';
              if (partial != null) {
                final start = int.parse(partial.group(1)!);
                final len = int.parse(partial.group(2)!);
                bytes = bytes.length <= start ? <int>[] : bytes.sublist(start, (start + len).clamp(0, bytes.length));
                key = '$key<$start>';
              }
              if (!upper.startsWith('BODY.PEEK') && !s.readOnly) m.flags.add(r'\Seen');
              addString(key, bytes);
            } else {
              throw _Bad('Unsupported fetch item $item');
            }
        }
      }
      // Literals: render each "{n}" followed by its bytes.
      final out = BytesBuilder();
      out.add(utf8.encode('* $seq FETCH ('));
      var li = 0;
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) out.add(utf8.encode(' '));
        final p = parts[i];
        if (p.endsWith('}') && RegExp(r'\{\d+\}$').hasMatch(p)) {
          out
            ..add(utf8.encode('$p\r\n'))
            ..add(literals[li++]);
        } else {
          out.add(_wire(p));
        }
      }
      out.add(utf8.encode(')\r\n'));
      s.conn.sendBytes(out.takeBytes());
    }
    s.conn.send('$tag OK FETCH completed');
  }

  /// Text with embedded `{n}\r\n` literal markers from [_quote], as bytes.
  static List<int> _wire(String p) => utf8.encode(p);

  List<int> _section(FakeMessage m, String section) {
    final upper = section.toUpperCase();
    if (upper.isEmpty) return m.raw;
    if (upper == 'HEADER') return latin1.encode('${m.root.header}\r\n\r\n');
    if (upper == 'TEXT') return latin1.encode(m.root.body);
    if (upper.startsWith('HEADER.FIELDS')) {
      final open = section.indexOf('(');
      final names = section.substring(open + 1, section.lastIndexOf(')')).split(' ').map((n) => n.toLowerCase()).toSet();
      final out = StringBuffer();
      for (final h in m.root.rawHeaders) {
        if (names.contains(h.$1.toLowerCase())) out.write('${h.$2}\r\n');
      }
      out.write('\r\n');
      return latin1.encode(out.toString());
    }
    var part = m.root;
    final numbers = upper.split('.');
    for (var i = 0; i < numbers.length; i++) {
      final n = int.tryParse(numbers[i]);
      if (n == null) {
        if (numbers[i] == 'MIME') return latin1.encode('${part.header}\r\n\r\n');
        break;
      }
      if (part.children.isEmpty) {
        if (n != 1) return const [];
        if (part.embedded != null && i + 1 < numbers.length) {
          part = part.embedded!;
        }
        continue;
      }
      if (n < 1 || n > part.children.length) return const [];
      part = part.children[n - 1];
      if (part.embedded != null && i + 1 < numbers.length) part = part.embedded!;
    }
    return latin1.encode(part.body);
  }

  String _nstring(String? v) => v == null ? 'NIL' : _quote(v);

  String _addresses(String? header) {
    final list = parseAddressHeader(header);
    if (list.isEmpty) return 'NIL';
    return '(${[
      for (final a in list)
        '(${_nstring(a.name)} NIL ${_quote(a.email.split('@').first)} ${_quote(a.email.contains('@') ? a.email.split('@').last : '')})',
    ].join()})';
  }

  String _envelope(RawPart root) {
    String? h(String name) => root.headerValue(name);
    final from = _addresses(h('From'));
    return '(${_nstring(h('Date'))} ${_nstring(h('Subject'))} $from ${_addresses(h('Sender') ?? h('From'))} '
        '${_addresses(h('Reply-To') ?? h('From'))} ${_addresses(h('To'))} ${_addresses(h('Cc'))} ${_addresses(h('Bcc'))} '
        '${_nstring(h('In-Reply-To'))} ${_nstring(h('Message-ID'))})';
  }

  String _params(HeaderValue v, {Set<String> skip = const {}}) {
    final entries = [for (final e in v.params.entries) if (!skip.contains(e.key)) '${_quote(e.key.toUpperCase())} ${_quote(e.value)}'];
    return entries.isEmpty ? 'NIL' : '(${entries.join(' ')})';
  }

  String _bodyStructure(RawPart part) {
    final ct = HeaderValue.parse(part.headerValue('Content-Type') ?? 'text/plain; charset=us-ascii');
    final type = ct.value.contains('/') ? ct.value : 'text/plain';
    final slash = type.indexOf('/');
    final disposition = HeaderValue.parse(part.headerValue('Content-Disposition'));
    final disp = disposition.value.isEmpty ? 'NIL' : '(${_quote(disposition.value.toUpperCase())} ${_params(disposition)})';
    if (part.children.isNotEmpty) {
      return '(${part.children.map(_bodyStructure).join()} ${_quote(type.substring(slash + 1).toUpperCase())} '
          '${_params(ct)} $disp NIL NIL)';
    }
    final enc = part.headerValue('Content-Transfer-Encoding')?.trim() ?? '7BIT';
    final size = part.body.length;
    final basic = '${_quote(type.substring(0, slash).toUpperCase())} ${_quote(type.substring(slash + 1).toUpperCase())} '
        '${_params(ct)} ${_nstring(part.headerValue('Content-ID'))} NIL ${_quote(enc.toUpperCase())} $size';
    final lines = '\n'.allMatches(part.body).length;
    if (type.startsWith('text/')) return '($basic $lines NIL $disp NIL NIL)';
    if (type == 'message/rfc822' && part.embedded != null) {
      return '($basic ${_envelope(part.embedded!)} ${_bodyStructure(part.embedded!)} $lines NIL $disp NIL NIL)';
    }
    return '($basic NIL $disp NIL NIL)';
  }

  void _search(_Session s, String tag, List<ImapValue> args, {required bool byUid}) {
    final box = _requireSelected(s);
    var i = 0;
    var esearch = false;
    if (i < args.length && args[i].text?.toUpperCase() == 'RETURN') {
      esearch = true;
      i += 2;
    }
    if (i < args.length && args[i].text?.toUpperCase() == 'CHARSET') i += 2;
    final keys = args.sublist(i);
    final list = contents(box);
    final hits = <int>[];
    for (var k = 0; k < list.length; k++) {
      final (uid, m) = list[k];
      var pos = 0;
      bool all = true;
      while (pos < keys.length) {
        final (ok, next) = _matchKey(s, keys, pos, uid, k + 1, m, box);
        all &= ok;
        pos = next;
      }
      if (all) hits.add(byUid ? uid : k + 1);
    }
    if (esearch) {
      s.conn.send('* ESEARCH (TAG "$tag")${byUid ? ' UID' : ''}${hits.isEmpty ? '' : ' ALL ${UidSet.of(hits)}'}');
    } else {
      s.conn.send('* SEARCH${hits.map((h) => ' $h').join()}');
    }
    s.conn.send('$tag OK SEARCH completed');
  }

  (bool, int) _matchKey(_Session s, List<ImapValue> keys, int pos, int uid, int seq, FakeMessage m, FakeMailbox box) {
    final key = keys[pos];
    if (key is ImapList) {
      var p = 0;
      var all = true;
      while (p < key.items.length) {
        final (ok, next) = _matchKey(s, key.items, p, uid, seq, m, box);
        all &= ok;
        p = next;
      }
      return (all, pos + 1);
    }
    final k = key.text!.toUpperCase();
    String arg(int offset) => keys[pos + offset].text ?? '';
    bool contains(String? haystack, String needle) => (haystack ?? '').toLowerCase().contains(needle.toLowerCase());
    final root = m.root;
    switch (k) {
      case 'ALL':
        return (true, pos + 1);
      case 'UID':
        return (UidSet.parse(arg(1).replaceAll('*', '${1 << 30}')).contains(uid), pos + 2);
      case 'SEEN':
        return (m.flags.contains(r'\Seen'), pos + 1);
      case 'UNSEEN':
        return (!m.flags.contains(r'\Seen'), pos + 1);
      case 'DELETED':
        return (m.flags.contains(r'\Deleted'), pos + 1);
      case 'SUBJECT' || 'FROM' || 'TO' || 'CC':
        return (contains(decodeHeaderValue(root.headerValue(k) ?? ''), arg(1)), pos + 2);
      case 'BODY':
        return (contains(utf8.decode(latin1.encode(root.body), allowMalformed: true), arg(1)), pos + 2);
      case 'TEXT':
        return (contains(utf8.decode(m.raw, allowMalformed: true), arg(1)) || contains(decodeHeaderValue(root.header), arg(1)), pos + 2);
      case 'HEADER':
        return (contains(root.headerValue(arg(1)), arg(2)), pos + 3);
      case 'OR':
        final (a, next) = _matchKey(s, keys, pos + 1, uid, seq, m, box);
        final (b, after) = _matchKey(s, keys, next, uid, seq, m, box);
        return (a || b, after);
      case 'NOT':
        final (a, next) = _matchKey(s, keys, pos + 1, uid, seq, m, box);
        return (!a, next);
      case 'X-GM-MSGID':
        return (m.gmailId.toString() == arg(1), pos + 2);
      case 'X-GM-THRID':
        return (m.gmailThreadId.toString() == arg(1), pos + 2);
      case 'X-GM-LABELS':
        final wanted = _decodeName(s, arg(1));
        return (m.labels.any((l) => l.toLowerCase() == wanted.toLowerCase()), pos + 2);
      case 'X-GM-RAW':
        return (_gmailRaw(m, arg(1)), pos + 2);
    }
    // A sequence set.
    if (RegExp(r'^[\d:*,]+$').hasMatch(k)) return (UidSet.parse(k.replaceAll('*', '${1 << 30}')).contains(seq), pos + 1);
    throw _Bad('Unsupported search key $k');
  }

  bool _gmailRaw(FakeMessage m, String query) {
    for (final term in query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
      final lower = term.toLowerCase();
      final ok = switch (lower) {
        'in:inbox' => m.labels.contains(r'\Inbox'),
        'in:drafts' || 'in:draft' => m.labels.contains(r'\Draft'),
        'in:sent' => m.labels.contains(r'\Sent'),
        'is:important' => m.labels.contains(r'\Important'),
        'is:starred' => m.labels.contains(r'\Starred'),
        'category:primary' => m.categories.isEmpty,
        _ when lower.startsWith('category:') => m.categories.contains(lower.substring(9)),
        _ => utf8.decode(m.raw, allowMalformed: true).toLowerCase().contains(lower),
      };
      if (!ok) return false;
    }
    return true;
  }

  void _store(_Session s, String tag, List<ImapValue> args) {
    final box = _requireSelected(s);
    final action = args[1].text!.toUpperCase();
    final values = {for (final v in args[2].items) v is ImapAtom ? v.value : _decodeName(s, v.text!)};
    for (final (_, _, m) in _resolve(box, args[0].text!, byUid: true)) {
      if (action.contains('X-GM-LABELS')) {
        if (action.startsWith('+')) {
          m.labels.addAll(values);
        } else if (action.startsWith('-')) {
          m.labels.removeAll(values);
        } else {
          m.labels = values;
        }
      } else if (action.startsWith('+')) {
        m.flags.addAll(values);
      } else if (action.startsWith('-')) {
        m.flags.removeAll(values);
      } else {
        m.flags = values;
      }
      m.modseq = ++_modseq;
    }
    s.conn.send('$tag OK STORE completed');
  }

  void _moveOrCopy(_Session s, String tag, List<ImapValue> args, {required bool move}) {
    final box = _requireSelected(s);
    final dest = mailboxes[_decodeName(s, args[1].text!)];
    if (dest == null) {
      s.conn.send('$tag NO [TRYCREATE] Mailbox does not exist');
      return;
    }
    final targets = _resolve(box, args[0].text!, byUid: true);
    final src = <int>[];
    final dst = <int>[];
    final moved = <FakeMessage>[];
    for (final (_, uid, m) in targets) {
      src.add(uid);
      FakeMessage copy;
      if (gmail && move) {
        copy = m;
        if (dest.isView && !box.isView && box != allMail) {
          // Out of Trash/Spam into a label folder (restore): back into All
          // Mail, with a new UID there.
          _remove(box, [m], actor: s);
          m.labels.add(dest.viewLabel!);
          _add(allMail, m);
        } else if (dest.isView) {
          // Between labels: only labels change.
          if (box.isView) m.labels.remove(box.viewLabel);
          m.labels.add(dest.viewLabel!);
          m.modseq = ++_modseq;
        } else {
          // Into Trash or Spam: the message leaves All Mail and every label
          // folder, and (over IMAP) loses its labels.
          _remove(box.isView ? allMail : box, [m], actor: box.isView ? null : s);
          if (dest != allMail) m.labels.clear();
          _add(dest, m);
        }
      } else {
        copy = FakeMessage(m.raw, flags: {...m.flags}..remove(r'\Deleted'), internalDate: m.internalDate)
          ..gmailId = m.gmailId
          ..gmailThreadId = m.gmailThreadId
          ..labels = {...m.labels};
        _add(dest, copy);
        if (move) moved.add(m);
      }
      if (dest.isView) contents(dest);
      dst.add(dest.isView ? dest.viewUids[copy]! : dest.entries.last.$1);
    }
    if (!gmail && move) _remove(box, moved, actor: s);
    final code = capabilities.contains('UIDPLUS') && src.isNotEmpty ? '[COPYUID ${dest.uidValidity} ${src.join(',')} ${dst.join(',')}] ' : '';
    if (move && code.isNotEmpty) s.conn.send('* OK $code');
    s.conn.send('$tag OK ${move ? '' : code}${move ? 'MOVE' : 'COPY'} completed');
  }
}

final class _Bad implements Exception {
  _Bad(this.message);

  final String message;
}

/// A raw MIME entity, kept undecoded so that `BODY[n]` returns the bytes
/// as they are in the message.
final class RawPart {
  RawPart(this.header, this.body, this.rawHeaders, this.children, this.embedded);

  final String header;
  final String body;

  /// (name, full unfolded-as-sent line(s))
  final List<(String, String)> rawHeaders;
  final List<RawPart> children;
  final RawPart? embedded;

  String? headerValue(String name) {
    for (final h in parseHeaderBlock(header)) {
      if (h.name.toLowerCase() == name.toLowerCase()) return h.value;
    }
    return null;
  }

  static RawPart parse(String raw) {
    final m = RegExp(r'\r?\n\r?\n').firstMatch(raw);
    final header = m == null ? raw : raw.substring(0, m.start);
    final body = m == null ? '' : raw.substring(m.end);
    final rawHeaders = <(String, String)>[];
    for (final line in header.split(RegExp(r'\r\n(?![ \t])'))) {
      final colon = line.indexOf(':');
      if (colon > 0) rawHeaders.add((line.substring(0, colon).trim(), line));
    }
    final part = RawPart(header, body, rawHeaders, const [], null);
    final ct = HeaderValue.parse(part.headerValue('Content-Type'));
    final boundary = ct['boundary'];
    if (ct.value.startsWith('multipart/') && boundary != null) {
      final children = <RawPart>[];
      final delimiter = RegExp('(?:^|\\r\\n)--${RegExp.escape(boundary)}(--)?[ \\t]*(?:\\r\\n|\$)');
      int? start;
      for (final d in delimiter.allMatches(body)) {
        if (start != null) children.add(RawPart.parse(body.substring(start, d.start)));
        if (d.group(1) != null) break;
        start = d.end;
      }
      return RawPart(header, body, rawHeaders, children, null);
    }
    if (ct.value == 'message/rfc822') return RawPart(header, body, rawHeaders, const [], RawPart.parse(body));
    return part;
  }
}
