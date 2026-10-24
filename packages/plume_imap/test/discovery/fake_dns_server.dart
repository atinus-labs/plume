import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_imap/src/discovery/dns.dart';

/// A query as the fake server saw it.
final class DnsQuery {
  DnsQuery(this.raw) : id = (raw[0] << 8) | raw[1], name = _name(raw);

  final Uint8List raw;
  final int id;
  final String name;

  static String _name(Uint8List raw) {
    final labels = <String>[];
    var i = 12;
    while (raw[i] != 0) {
      labels.add(String.fromCharCodes(raw, i + 1, i + 1 + raw[i]));
      i += 1 + raw[i];
    }
    return labels.join('.');
  }
}

/// Datagrams to send back for a query (none: stay silent).
typedef DnsHandler = List<Uint8List> Function(DnsQuery query);

/// A scriptable DNS server on a loopback address, UDP plus TCP on the
/// same port for truncation fallback.
final class FakeDnsServer {
  FakeDnsServer._(this._udp, this._tcp);

  final RawDatagramSocket _udp;
  final ServerSocket? _tcp;

  DnsHandler udp = (q) => [dnsResponse(q)];
  DnsHandler tcp = (q) => [dnsResponse(q)];
  final udpQueries = <DnsQuery>[];
  final tcpQueries = <DnsQuery>[];

  InternetAddress get address => _udp.address;
  int get port => _udp.port;

  static Future<FakeDnsServer> start({String address = '127.0.0.1', int port = 0}) async {
    final host = InternetAddress(address);
    final udp = await RawDatagramSocket.bind(host, port);
    final tcp = await ServerSocket.bind(host, udp.port);
    final server = FakeDnsServer._(udp, tcp);
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = udp.receive();
      if (datagram == null) return;
      final query = DnsQuery(datagram.data);
      server.udpQueries.add(query);
      for (final reply in server.udp(query)) {
        udp.send(reply, datagram.address, datagram.port);
      }
    });
    tcp.listen((socket) async {
      final bytes = <int>[];
      await for (final chunk in socket) {
        bytes.addAll(chunk);
        if (bytes.length >= 2 && bytes.length >= ((bytes[0] << 8) | bytes[1]) + 2) break;
      }
      final query = DnsQuery(Uint8List.fromList(bytes.sublist(2)));
      server.tcpQueries.add(query);
      for (final reply in server.tcp(query)) {
        socket.add([reply.length >> 8, reply.length & 0xFF, ...reply]);
      }
      await socket.flush();
      await socket.close();
    });
    return server;
  }

  Future<void> close() async {
    _udp.close();
    await _tcp?.close();
  }
}

/// A response to [query]: MX records as (preference, host), optionally
/// preceded by a CNAME. Exchange names under the queried name are
/// compressed with a pointer to the question, as real servers do.
Uint8List dnsResponse(
  DnsQuery query, {
  List<(int, String)> mx = const [],
  int? id,
  int rcode = 0,
  bool truncated = false,
  String? questionName,
  String? cname,
}) {
  final name = questionName ?? query.name;
  final out = BytesBuilder();
  final flags = 0x8180 | (truncated ? 0x0200 : 0) | rcode;
  final answers = mx.length + (cname == null ? 0 : 1);
  out
    ..add(_u16(id ?? query.id))
    ..add(_u16(flags))
    ..add(_u16(1))
    ..add(_u16(answers))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(encodeName(name))
    ..add(_u16(15))
    ..add(_u16(1));
  if (cname != null) {
    final target = encodeName(cname);
    out
      ..add([0xC0, 12])
      ..add(_u16(5))
      ..add(_u16(1))
      ..add([0, 0, 1, 44])
      ..add(_u16(target.length))
      ..add(target);
  }
  for (final (preference, host) in mx) {
    final Uint8List exchange;
    if (host.endsWith('.$name')) {
      final prefix = host.substring(0, host.length - name.length - 1);
      final labels = encodeName(prefix);
      // Drop the root byte and point at the question name instead.
      exchange = Uint8List.fromList([...labels.sublist(0, labels.length - 1), 0xC0, 12]);
    } else if (host.isEmpty) {
      exchange = Uint8List.fromList([0]);
    } else {
      exchange = encodeName(host);
    }
    out
      ..add([0xC0, 12])
      ..add(_u16(15))
      ..add(_u16(1))
      ..add([0, 0, 1, 44])
      ..add(_u16(exchange.length + 2))
      ..add(_u16(preference))
      ..add(exchange);
  }
  return out.toBytes();
}

List<int> _u16(int v) => [v >> 8 & 0xFF, v & 0xFF];
