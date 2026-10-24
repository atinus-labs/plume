import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../connection_check.dart';
import '../settings.dart';

/// Checks whether a mail server of the given protocol answers at an
/// endpoint. Injected into discovery so tests need no network.
typedef ServerProbe = Future<bool> Function(ServerEndpoint endpoint, MailProtocol protocol);

/// Connects to [endpoint] and accepts it if it greets like an IMAP server
/// (`* OK`) or an SMTP server (`220`). SSL/TLS endpoints must present a
/// valid certificate for the host. Nothing is sent; the connection is
/// dropped right after the greeting.
Future<bool> probeGreeting(
  ServerEndpoint endpoint,
  MailProtocol protocol, {
  Duration timeout = const Duration(seconds: 6),
  SecurityContext? securityContext,
}) async {
  Socket? socket;
  final Future<Socket> connecting = endpoint.security == ConnectionSecurity.tls
      ? SecureSocket.connect(endpoint.host, endpoint.port, context: securityContext, timeout: timeout)
      : Socket.connect(endpoint.host, endpoint.port, timeout: timeout);
  try {
    socket = await connecting.timeout(timeout);
    final line = await _firstLine(socket).timeout(timeout);
    return switch (protocol) {
      MailProtocol.imap => line.startsWith('* OK'),
      MailProtocol.smtp => line.startsWith(RegExp('220(?:[ -]|\$)')),
    };
  } on TimeoutException {
    // Close the socket if it still arrives.
    connecting.then((s) => s.destroy(), onError: (Object _) {}).ignore();
    return false;
  } on Object {
    return false;
  } finally {
    socket?.destroy();
  }
}

Future<String> _firstLine(Socket socket) async {
  final bytes = <int>[];
  await for (final chunk in socket) {
    bytes.addAll(chunk);
    final newline = bytes.indexOf(0x0A);
    if (newline >= 0) return utf8.decode(bytes.sublist(0, newline), allowMalformed: true).trimRight();
    if (bytes.length > 4096) break;
  }
  return '';
}
