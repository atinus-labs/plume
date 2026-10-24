@Tags(['live'])
library;

import 'package:plume_imap/plume_imap.dart';
import 'package:test/test.dart';

/// Against real servers; run with `dart test --run-skipped -t live`.
void main() {
  test('SMTP reaches the sign-in step at Gmail over both security modes', () async {
    // Empty credentials are refused before any password is checked, so this
    // does not count as a failed login attempt.
    for (final endpoint in const [
      ServerEndpoint(host: 'smtp.gmail.com', port: 465, security: ConnectionSecurity.tls),
      ServerEndpoint(host: 'smtp.gmail.com', port: 587, security: ConnectionSecurity.startTls),
    ]) {
      await expectLater(
        checkSmtpLogin(endpoint, '', ''),
        throwsA(isA<ConnectionCheckException>().having((e) => e.failure, 'failure', isNot(ConnectionFailure.tls))),
      );
    }
  });
}
