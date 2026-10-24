/// Provider-neutral mail domain: models, provider and store contracts, and
/// the sync engine. Pure Dart, no Flutter dependency.
library;

export 'src/models/account.dart';
export 'src/models/address.dart';
export 'src/models/filter.dart';
export 'src/models/mailbox.dart';
export 'src/models/message.dart';
export 'src/models/outgoing.dart';
export 'src/models/thread.dart';
export 'src/ops/mail_operation.dart';
export 'src/provider/errors.dart';
export 'src/provider/mail_provider.dart';
export 'src/store/mail_store.dart';
export 'src/store/sync_store.dart';
export 'src/sync/account_status.dart';
export 'src/sync/backoff.dart' show Backoff;
export 'src/sync/mail_engine.dart';
