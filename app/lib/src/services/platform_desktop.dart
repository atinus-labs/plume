import '../platform/linux/linux_desktop.dart';
import 'accounts.dart';
import 'desktop.dart';
import 'gmail_connector.dart';
import 'imap_connector.dart';
import 'secret_store.dart';

/// The desktop integration for the current platform.
DesktopIntegration createDesktopIntegration({required bool startHidden}) =>
    linuxDesktopSupported ? LinuxDesktop(startHidden: startHidden) : HeadlessDesktop();

/// Account connectors available on this build.
List<AccountConnector> platformConnectors(SecretStore secrets) => [GmailConnector(secrets), ImapConnector(secrets)];
