/// SQLite (drift) implementation of the Plume [MailStore].
///
/// ```dart
/// final store = DriftMailStore.open('/path/to/plume/mail.sqlite');
/// ```
library;

import 'package:plume_core/plume_core.dart';

export 'src/codecs.dart' show OutgoingMessageCodec;
export 'src/database.dart' show PlumeDatabase, configureConnection;
export 'src/drift_mail_store.dart';
export 'src/html_text.dart' show decodeHtmlEntities, htmlToText;
