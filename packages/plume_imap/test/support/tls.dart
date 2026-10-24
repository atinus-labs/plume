import 'dart:io';

/// A self-signed certificate for 127.0.0.1/localhost (or [commonName])
/// generated with openssl, plus contexts for a server using it and a
/// client trusting it.
final class TestCertificate {
  TestCertificate._(this.certPath, this.keyPath);

  final String certPath;
  final String keyPath;

  static Future<TestCertificate> generate(Directory dir, {String commonName = 'localhost', bool ipSan = true}) async {
    final cert = '${dir.path}/$commonName.crt';
    final key = '${dir.path}/$commonName.key';
    final san = ipSan ? 'DNS:$commonName,IP:127.0.0.1' : 'DNS:$commonName';
    final r = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '2', //
      '-subj', '/CN=$commonName',
      '-addext', 'subjectAltName=$san',
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-keyout', key, '-out', cert,
    ]);
    if (r.exitCode != 0) throw StateError('openssl failed: ${r.stderr}');
    return TestCertificate._(cert, key);
  }

  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  SecurityContext clientContext() => SecurityContext(withTrustedRoots: false)..setTrustedCertificates(certPath);
}
