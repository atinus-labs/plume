import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plume_imap/plume_imap.dart';
import 'package:plume_imap/src/smtp/smtp_client.dart';
import 'package:plume_imap/src/smtp/smtp_data.dart';
import 'package:plume_imap/src/smtp/smtp_exception.dart';
import 'package:plume_imap/src/smtp/smtp_reply.dart';
import 'package:test/test.dart';

void main() {
  group('SmtpReplyParser', () {
    test('joins multi-line replies and strips enhanced codes', () {
      final parser = SmtpReplyParser();
      expect(parser.add('534-5.7.9 Application-specific password required. Learn more at'), isNull);
      expect(parser.isPartial, isTrue);
      final reply = parser.add('534 5.7.9  https://support.google.com/mail/?p=InvalidSecondFactor x12 - gsmtp')!;
      expect(reply.code, 534);
      expect(reply.enhancedCode, '5.7.9');
      expect(reply.isPermanent, isTrue);
      expect(
        reply.message,
        'Application-specific password required. Learn more at '
        'https://support.google.com/mail/?p=InvalidSecondFactor x12 - gsmtp',
      );
      expect(parser.isPartial, isFalse);
    });

    test('accepts a bare code and text without enhanced codes', () {
      final parser = SmtpReplyParser();
      expect(parser.add('250')!.lines, ['']);
      final reply = parser.add('421 Service not available, closing channel')!;
      expect(reply.enhancedCode, isNull);
      expect(reply.isTransient, isTrue);
      expect(reply.message, 'Service not available, closing channel');
    });

    test('rejects lines that are not SMTP', () {
      expect(() => SmtpReplyParser().add('* OK IMAP4rev1 ready'), throwsFormatException);
      expect(() => SmtpReplyParser().add('+OK POP3 ready'), throwsFormatException);
      expect(() => SmtpReplyParser().add('25 short'), throwsFormatException);
    });
  });

  group('SmtpPayload', () {
    String encode(String s) => latin1.decode(SmtpPayload.encode(Uint8List.fromList(latin1.encode(s))).bytes);

    test('normalizes bare LF and bare CR to CRLF and terminates', () {
      expect(encode('a\nb\rc\r\nd'), 'a\r\nb\r\nc\r\nd\r\n.\r\n');
      expect(encode('ends with newline\n'), 'ends with newline\r\n.\r\n');
      expect(encode('blank\n\nline'), 'blank\r\n\r\nline\r\n.\r\n');
    });

    test('dot-stuffs lines starting with a dot', () {
      expect(encode('.\n..\n.x\nnot.this\n.'), '..\r\n...\r\n..x\r\nnot.this\r\n..\r\n.\r\n');
    });

    test('detects 8-bit content and where it is', () {
      final body = SmtpPayload.encode(Uint8List.fromList(utf8.encode('Subject: hi\r\n\r\nGrüße')));
      expect(body.has8BitBody, isTrue);
      expect(body.has8BitHeaders, isFalse);
      final header = SmtpPayload.encode(Uint8List.fromList(utf8.encode('Subject: Grüße\r\n\r\nhi')));
      expect(header.has8BitHeaders, isTrue);
      final ascii = SmtpPayload.encode(Uint8List.fromList(utf8.encode('Subject: hi\r\n\r\nhi')));
      expect(ascii.has8BitBody, isFalse);
    });
  });

  group('smtpConnectionError', () {
    const endpoint = ServerEndpoint(host: 'smtp.example.org', port: 587, security: ConnectionSecurity.startTls);

    test('unknown host', () {
      final e = smtpConnectionError(
        const SocketException(
          "Failed host lookup: 'smtp.example.org'",
          osError: OSError('Name or service not known', -2),
        ),
        endpoint,
      );
      expect(e.kind, SmtpErrorKind.hostNotFound);
      expect(e.message, contains('smtp.example.org'));
    });

    test('resolver unreachable means offline, not a wrong name', () {
      final e = smtpConnectionError(
        const SocketException(
          "Failed host lookup: 'smtp.example.org'",
          osError: OSError('Temporary failure in name resolution', -3),
        ),
        endpoint,
      );
      expect(e.kind, SmtpErrorKind.unreachable);
    });

    test('refused and timed out connections', () {
      expect(
        smtpConnectionError(
          const SocketException('Connection refused', osError: OSError('Connection refused', 111)),
          endpoint,
        ).kind,
        SmtpErrorKind.unreachable,
      );
      expect(
        smtpConnectionError(
          const SocketException('Connection timed out', osError: OSError('timed out', 110)),
          endpoint,
        ).kind,
        SmtpErrorKind.timeout,
      );
    });

    test('certificate versus other TLS errors', () {
      expect(
        smtpConnectionError(
          const HandshakeException('CERTIFICATE_VERIFY_FAILED: self signed certificate'),
          endpoint,
        ).kind,
        SmtpErrorKind.certificate,
      );
      expect(smtpConnectionError(const HandshakeException('WRONG_VERSION_NUMBER'), endpoint).kind, SmtpErrorKind.tls);
    });
  });
}
