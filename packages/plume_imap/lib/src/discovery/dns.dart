import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final Logger _log = Logger('plume.discovery');

/// One mail exchanger for a domain.
final class MxRecord {
  const MxRecord(this.preference, this.host);

  /// Lower is preferred.
  final int preference;

  /// Lower case, without the trailing dot.
  final String host;

  @override
  bool operator ==(Object other) => other is MxRecord && other.preference == preference && other.host == host;

  @override
  int get hashCode => Object.hash(preference, host);

  @override
  String toString() => '$preference $host';
}

/// Looks up the MX records of a domain, most preferred first. Empty when
/// the domain has none or the lookup failed.
typedef MxLookup = Future<List<MxRecord>> Function(String domain);

/// A minimal DNS client for MX queries (RFC 1035), since dart:io has no API
/// for them.
///
/// Queries go over UDP to the system's nameservers from `/etc/resolv.conf`
/// (systemd-resolved's 127.0.0.53 on most desktops), in order, retrying
/// over TCP when an answer is truncated. Deliberately not DNS-over-HTTPS:
/// that would tell a third party which domains the user has mail at.
///
/// Answers are only accepted from the server that was asked, with the
/// query's random ID and question echoed back.
final class DnsClient {
  DnsClient({
    this.resolvConfPath = '/etc/resolv.conf',
    this._nameservers,
    this.port = 53,
    this.timeout = const Duration(seconds: 3),
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Where nameservers are read from when none are given.
  final String resolvConfPath;

  /// Overrides [resolvConfPath].
  final List<InternetAddress>? _nameservers;

  /// Nameserver port; tests use a fake server on another port.
  final int port;

  /// Per nameserver.
  final Duration timeout;
  final Random _random;

  static const _typeMx = 15;
  static const _classIn = 1;

  /// The MX records of [domain], most preferred first. Never throws:
  /// failures are logged and give an empty list.
  Future<List<MxRecord>> lookupMx(String domain) async {
    final servers = _nameservers ?? await readNameservers(resolvConfPath);
    for (final server in servers.take(3)) {
      try {
        final records = await _query(server, domain);
        if (records != null) return records;
      } on Object catch (e) {
        _log.fine('MX lookup via ${server.address} failed: ${e.runtimeType}');
      }
    }
    return const [];
  }

  /// Nameservers listed in the resolv.conf at [path]; 127.0.0.1 when there
  /// are none (the resolver library's default).
  static Future<List<InternetAddress>> readNameservers(String path) async {
    final servers = <InternetAddress>[];
    try {
      for (final line in await File(path).readAsLines()) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 2 || fields[0] != 'nameserver') continue;
        final address = InternetAddress.tryParse(fields[1]);
        if (address != null) servers.add(address);
      }
    } on IOException {
      // No resolv.conf: use the default below.
    }
    return servers.isEmpty ? [InternetAddress.loopbackIPv4] : servers;
  }

  /// Returns the records, an empty list for "no such domain / no MX", or
  /// null when this server could not answer (try the next one).
  Future<List<MxRecord>?> _query(InternetAddress server, String domain) async {
    final id = _random.nextInt(0x10000);
    final query = encodeMxQuery(id, domain);
    var response = await _udp(server, query, id);
    if (response == null) return null;
    if (response.truncated) {
      _log.fine('DNS answer truncated; retrying over TCP');
      response = await _tcp(server, query, id);
      if (response == null) return null;
    }
    return response.records;
  }

  Future<DnsResponse?> _udp(InternetAddress server, Uint8List query, int id) async {
    final socket = await RawDatagramSocket.bind(
      server.type == InternetAddressType.IPv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4,
      0,
    );
    final result = Completer<DnsResponse?>();
    final timer = Timer(timeout, () {
      if (!result.isCompleted) result.complete(null);
    });
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || result.isCompleted) return;
      // Ignore anything not from the server we asked, or not our answer:
      // a blind spoofer has to guess both the port and the ID.
      if (datagram.address != server || datagram.port != port) return;
      final response = DnsResponse.tryParse(datagram.data, id: id, question: query);
      if (response != null) result.complete(response);
    });
    try {
      socket.send(query, server, port);
      return await result.future;
    } finally {
      timer.cancel();
      socket.close();
    }
  }

  Future<DnsResponse?> _tcp(InternetAddress server, Uint8List query, int id) async {
    final socket = await Socket.connect(server, port, timeout: timeout);
    try {
      socket.add([query.length >> 8, query.length & 0xFF, ...query]);
      await socket.flush();
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in socket.timeout(timeout)) {
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        if (bytes.length < 2) continue;
        final length = (bytes[0] << 8) | bytes[1];
        if (bytes.length >= length + 2) {
          return DnsResponse.tryParse(Uint8List.sublistView(bytes, 2, length + 2), id: id, question: query);
        }
        if (bytes.length > 65537) break;
      }
      return null;
    } on TimeoutException {
      return null;
    } finally {
      socket.destroy();
    }
  }
}

/// Builds a recursive MX query for [domain] with [id].
Uint8List encodeMxQuery(int id, String domain) {
  final out = BytesBuilder()
    ..add([id >> 8, id & 0xFF, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]) // RD; one question
    ..add(encodeName(domain))
    ..add([0, DnsClient._typeMx, 0, DnsClient._classIn]);
  return out.toBytes();
}

/// [name] in DNS wire format. Throws [ArgumentError] for names that cannot
/// be encoded (non-ASCII, empty or overlong labels).
Uint8List encodeName(String name) {
  final out = BytesBuilder();
  final trimmed = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
  for (final label in trimmed.split('.')) {
    final bytes = label.codeUnits;
    if (bytes.isEmpty || bytes.length > 63 || bytes.any((b) => b > 0x7E || b <= 0x20)) {
      throw ArgumentError.value(name, 'name', 'not a valid DNS name');
    }
    out
      ..addByte(bytes.length)
      ..add(bytes);
  }
  out.addByte(0);
  return out.toBytes();
}

/// The parts of a DNS response an MX lookup needs.
final class DnsResponse {
  const DnsResponse._(this.truncated, this.records);

  /// TC: the answer did not fit in a UDP datagram.
  final bool truncated;

  /// MX records, most preferred first; empty for NXDOMAIN or no MX. A null
  /// MX (RFC 7505, "this domain accepts no mail") is left out.
  final List<MxRecord> records;

  /// Parses [data] as the answer to [question] (the query bytes) with
  /// [id]. Returns null for anything that is not a well-formed answer to
  /// that question, or a server failure (so the next server is tried).
  static DnsResponse? tryParse(Uint8List data, {required int id, required Uint8List question}) {
    try {
      return _parse(data, id, question);
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static DnsResponse? _parse(Uint8List data, int id, Uint8List question) {
    if (data.length < 12) return null;
    final view = ByteData.sublistView(data);
    if (view.getUint16(0) != id) return null;
    final flags = view.getUint16(2);
    if (flags & 0x8000 == 0) return null; // not a response
    final truncated = flags & 0x0200 != 0;
    final rcode = flags & 0x000F;
    if (rcode == 3) return const DnsResponse._(false, []); // NXDOMAIN
    if (rcode != 0) return null; // SERVFAIL, REFUSED...
    final qdcount = view.getUint16(4);
    final ancount = view.getUint16(6);
    if (qdcount != 1) return null;

    // The question must be ours (names compare case-insensitively).
    var offset = 12;
    final (qname, afterName) = _readName(data, offset);
    final (expected, _) = _readName(question, 12);
    if (qname.toLowerCase() != expected.toLowerCase()) return null;
    offset = afterName;
    if (view.getUint16(offset) != DnsClient._typeMx || view.getUint16(offset + 2) != DnsClient._classIn) return null;
    offset += 4;
    if (truncated) return const DnsResponse._(true, []);

    final records = <MxRecord>[];
    for (var i = 0; i < ancount; i++) {
      final (_, afterOwner) = _readName(data, offset);
      offset = afterOwner;
      final type = view.getUint16(offset);
      final klass = view.getUint16(offset + 2);
      final length = view.getUint16(offset + 8);
      final rdata = offset + 10;
      if (rdata + length > data.length) return null;
      // CNAMEs and other records may precede the MX answers.
      if (type == DnsClient._typeMx && klass == DnsClient._classIn) {
        final preference = view.getUint16(rdata);
        final (host, _) = _readName(data, rdata + 2);
        if (host.isNotEmpty) records.add(MxRecord(preference, host.toLowerCase()));
      }
      offset = rdata + length;
    }
    records.sort((a, b) => a.preference.compareTo(b.preference));
    return DnsResponse._(false, records);
  }

  /// Reads a possibly compressed name at [offset]. Returns it (without the
  /// trailing dot; empty for the root) and the offset after it.
  static (String, int) _readName(Uint8List data, int offset) {
    final labels = <String>[];
    var position = offset;
    int? end;
    var jumps = 0;
    while (true) {
      final length = data[position];
      if (length == 0) {
        end ??= position + 1;
        break;
      }
      if (length & 0xC0 == 0xC0) {
        // Compression pointer; bounded so a malicious loop cannot hang us.
        if (++jumps > 32) throw const FormatException('DNS name compression loop');
        end ??= position + 2;
        position = ((length & 0x3F) << 8) | data[position + 1];
        continue;
      }
      if (length & 0xC0 != 0) throw const FormatException('Unknown DNS label type');
      labels.add(String.fromCharCodes(data, position + 1, position + 1 + length));
      position += 1 + length;
      if (labels.length > 127) throw const FormatException('DNS name too long');
    }
    return (labels.join('.'), end);
  }
}
