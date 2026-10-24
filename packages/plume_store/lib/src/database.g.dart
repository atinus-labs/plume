// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class Accounts extends Table with TableInfo<Accounts, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Accounts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'ok\'',
    defaultValue: const CustomExpression('\'ok\''),
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _providerConfigMeta = const VerificationMeta(
    'providerConfig',
  );
  late final GeneratedColumn<String> providerConfig = GeneratedColumn<String>(
    'provider_config',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    provider,
    email,
    displayName,
    avatarUrl,
    color,
    sortOrder,
    status,
    signature,
    providerConfig,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    }
    if (data.containsKey('provider_config')) {
      context.handle(
        _providerConfigMeta,
        providerConfig.isAcceptableOrUnknown(
          data['provider_config']!,
          _providerConfigMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      ),
      providerConfig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_config'],
      ),
    );
  }

  @override
  Accounts createAlias(String alias) {
    return Accounts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String id;
  final String provider;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final int color;
  final int sortOrder;
  final String status;
  final String? signature;

  /// Provider connection settings as a JSON object (v2).
  final String? providerConfig;
  const AccountRow({
    required this.id,
    required this.provider,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.color,
    required this.sortOrder,
    required this.status,
    this.signature,
    this.providerConfig,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['provider'] = Variable<String>(provider);
    map['email'] = Variable<String>(email);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['color'] = Variable<int>(color);
    map['sort_order'] = Variable<int>(sortOrder);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<String>(signature);
    }
    if (!nullToAbsent || providerConfig != null) {
      map['provider_config'] = Variable<String>(providerConfig);
    }
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      provider: Value(provider),
      email: Value(email),
      displayName: Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      color: Value(color),
      sortOrder: Value(sortOrder),
      status: Value(status),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
      providerConfig: providerConfig == null && nullToAbsent
          ? const Value.absent()
          : Value(providerConfig),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      id: serializer.fromJson<String>(json['id']),
      provider: serializer.fromJson<String>(json['provider']),
      email: serializer.fromJson<String>(json['email']),
      displayName: serializer.fromJson<String>(json['display_name']),
      avatarUrl: serializer.fromJson<String?>(json['avatar_url']),
      color: serializer.fromJson<int>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sort_order']),
      status: serializer.fromJson<String>(json['status']),
      signature: serializer.fromJson<String?>(json['signature']),
      providerConfig: serializer.fromJson<String?>(json['provider_config']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'provider': serializer.toJson<String>(provider),
      'email': serializer.toJson<String>(email),
      'display_name': serializer.toJson<String>(displayName),
      'avatar_url': serializer.toJson<String?>(avatarUrl),
      'color': serializer.toJson<int>(color),
      'sort_order': serializer.toJson<int>(sortOrder),
      'status': serializer.toJson<String>(status),
      'signature': serializer.toJson<String?>(signature),
      'provider_config': serializer.toJson<String?>(providerConfig),
    };
  }

  AccountRow copyWith({
    String? id,
    String? provider,
    String? email,
    String? displayName,
    Value<String?> avatarUrl = const Value.absent(),
    int? color,
    int? sortOrder,
    String? status,
    Value<String?> signature = const Value.absent(),
    Value<String?> providerConfig = const Value.absent(),
  }) => AccountRow(
    id: id ?? this.id,
    provider: provider ?? this.provider,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
    status: status ?? this.status,
    signature: signature.present ? signature.value : this.signature,
    providerConfig: providerConfig.present
        ? providerConfig.value
        : this.providerConfig,
  );
  AccountRow copyWithCompanion(AccountsCompanion data) {
    return AccountRow(
      id: data.id.present ? data.id.value : this.id,
      provider: data.provider.present ? data.provider.value : this.provider,
      email: data.email.present ? data.email.value : this.email,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      status: data.status.present ? data.status.value : this.status,
      signature: data.signature.present ? data.signature.value : this.signature,
      providerConfig: data.providerConfig.present
          ? data.providerConfig.value
          : this.providerConfig,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('status: $status, ')
          ..write('signature: $signature, ')
          ..write('providerConfig: $providerConfig')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    provider,
    email,
    displayName,
    avatarUrl,
    color,
    sortOrder,
    status,
    signature,
    providerConfig,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.id == this.id &&
          other.provider == this.provider &&
          other.email == this.email &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.status == this.status &&
          other.signature == this.signature &&
          other.providerConfig == this.providerConfig);
}

class AccountsCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> id;
  final Value<String> provider;
  final Value<String> email;
  final Value<String> displayName;
  final Value<String?> avatarUrl;
  final Value<int> color;
  final Value<int> sortOrder;
  final Value<String> status;
  final Value<String?> signature;
  final Value<String?> providerConfig;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.provider = const Value.absent(),
    this.email = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.signature = const Value.absent(),
    this.providerConfig = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String provider,
    required String email,
    required String displayName,
    this.avatarUrl = const Value.absent(),
    required int color,
    this.sortOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.signature = const Value.absent(),
    this.providerConfig = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       provider = Value(provider),
       email = Value(email),
       displayName = Value(displayName),
       color = Value(color);
  static Insertable<AccountRow> custom({
    Expression<String>? id,
    Expression<String>? provider,
    Expression<String>? email,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<int>? color,
    Expression<int>? sortOrder,
    Expression<String>? status,
    Expression<String>? signature,
    Expression<String>? providerConfig,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (provider != null) 'provider': provider,
      if (email != null) 'email': email,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (status != null) 'status': status,
      if (signature != null) 'signature': signature,
      if (providerConfig != null) 'provider_config': providerConfig,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? provider,
    Value<String>? email,
    Value<String>? displayName,
    Value<String?>? avatarUrl,
    Value<int>? color,
    Value<int>? sortOrder,
    Value<String>? status,
    Value<String?>? signature,
    Value<String?>? providerConfig,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      status: status ?? this.status,
      signature: signature ?? this.signature,
      providerConfig: providerConfig ?? this.providerConfig,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (providerConfig.present) {
      map['provider_config'] = Variable<String>(providerConfig.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('email: $email, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('status: $status, ')
          ..write('signature: $signature, ')
          ..write('providerConfig: $providerConfig, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Mailboxes extends Table with TableInfo<Mailboxes, MailboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Mailboxes(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES accounts(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'user\'',
    defaultValue: const CustomExpression('\'user\''),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _unreadThreadsMeta = const VerificationMeta(
    'unreadThreads',
  );
  late final GeneratedColumn<int> unreadThreads = GeneratedColumn<int>(
    'unread_threads',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _totalThreadsMeta = const VerificationMeta(
    'totalThreads',
  );
  late final GeneratedColumn<int> totalThreads = GeneratedColumn<int>(
    'total_threads',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    name,
    role,
    category,
    kind,
    parentId,
    color,
    unreadThreads,
    totalThreads,
    sortOrder,
    hidden,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mailboxes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MailboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('unread_threads')) {
      context.handle(
        _unreadThreadsMeta,
        unreadThreads.isAcceptableOrUnknown(
          data['unread_threads']!,
          _unreadThreadsMeta,
        ),
      );
    }
    if (data.containsKey('total_threads')) {
      context.handle(
        _totalThreadsMeta,
        totalThreads.isAcceptableOrUnknown(
          data['total_threads']!,
          _totalThreadsMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  MailboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MailboxRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      ),
      unreadThreads: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_threads'],
      )!,
      totalThreads: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_threads'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
    );
  }

  @override
  Mailboxes createAlias(String alias) {
    return Mailboxes(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const ['PRIMARY KEY(account_id, id)'];
  @override
  bool get dontWriteConstraints => true;
}

class MailboxRow extends DataClass implements Insertable<MailboxRow> {
  final String accountId;
  final String id;
  final String name;
  final String? role;
  final String? category;
  final String kind;
  final String? parentId;
  final int? color;
  final int unreadThreads;
  final int totalThreads;
  final int sortOrder;
  final bool hidden;
  const MailboxRow({
    required this.accountId,
    required this.id,
    required this.name,
    this.role,
    this.category,
    required this.kind,
    this.parentId,
    this.color,
    required this.unreadThreads,
    required this.totalThreads,
    required this.sortOrder,
    required this.hidden,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || role != null) {
      map['role'] = Variable<String>(role);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<int>(color);
    }
    map['unread_threads'] = Variable<int>(unreadThreads);
    map['total_threads'] = Variable<int>(totalThreads);
    map['sort_order'] = Variable<int>(sortOrder);
    map['hidden'] = Variable<bool>(hidden);
    return map;
  }

  MailboxesCompanion toCompanion(bool nullToAbsent) {
    return MailboxesCompanion(
      accountId: Value(accountId),
      id: Value(id),
      name: Value(name),
      role: role == null && nullToAbsent ? const Value.absent() : Value(role),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      kind: Value(kind),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      unreadThreads: Value(unreadThreads),
      totalThreads: Value(totalThreads),
      sortOrder: Value(sortOrder),
      hidden: Value(hidden),
    );
  }

  factory MailboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MailboxRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String?>(json['role']),
      category: serializer.fromJson<String?>(json['category']),
      kind: serializer.fromJson<String>(json['kind']),
      parentId: serializer.fromJson<String?>(json['parent_id']),
      color: serializer.fromJson<int?>(json['color']),
      unreadThreads: serializer.fromJson<int>(json['unread_threads']),
      totalThreads: serializer.fromJson<int>(json['total_threads']),
      sortOrder: serializer.fromJson<int>(json['sort_order']),
      hidden: serializer.fromJson<bool>(json['hidden']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String?>(role),
      'category': serializer.toJson<String?>(category),
      'kind': serializer.toJson<String>(kind),
      'parent_id': serializer.toJson<String?>(parentId),
      'color': serializer.toJson<int?>(color),
      'unread_threads': serializer.toJson<int>(unreadThreads),
      'total_threads': serializer.toJson<int>(totalThreads),
      'sort_order': serializer.toJson<int>(sortOrder),
      'hidden': serializer.toJson<bool>(hidden),
    };
  }

  MailboxRow copyWith({
    String? accountId,
    String? id,
    String? name,
    Value<String?> role = const Value.absent(),
    Value<String?> category = const Value.absent(),
    String? kind,
    Value<String?> parentId = const Value.absent(),
    Value<int?> color = const Value.absent(),
    int? unreadThreads,
    int? totalThreads,
    int? sortOrder,
    bool? hidden,
  }) => MailboxRow(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    name: name ?? this.name,
    role: role.present ? role.value : this.role,
    category: category.present ? category.value : this.category,
    kind: kind ?? this.kind,
    parentId: parentId.present ? parentId.value : this.parentId,
    color: color.present ? color.value : this.color,
    unreadThreads: unreadThreads ?? this.unreadThreads,
    totalThreads: totalThreads ?? this.totalThreads,
    sortOrder: sortOrder ?? this.sortOrder,
    hidden: hidden ?? this.hidden,
  );
  MailboxRow copyWithCompanion(MailboxesCompanion data) {
    return MailboxRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      category: data.category.present ? data.category.value : this.category,
      kind: data.kind.present ? data.kind.value : this.kind,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      color: data.color.present ? data.color.value : this.color,
      unreadThreads: data.unreadThreads.present
          ? data.unreadThreads.value
          : this.unreadThreads,
      totalThreads: data.totalThreads.present
          ? data.totalThreads.value
          : this.totalThreads,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MailboxRow(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('category: $category, ')
          ..write('kind: $kind, ')
          ..write('parentId: $parentId, ')
          ..write('color: $color, ')
          ..write('unreadThreads: $unreadThreads, ')
          ..write('totalThreads: $totalThreads, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('hidden: $hidden')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    id,
    name,
    role,
    category,
    kind,
    parentId,
    color,
    unreadThreads,
    totalThreads,
    sortOrder,
    hidden,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MailboxRow &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.name == this.name &&
          other.role == this.role &&
          other.category == this.category &&
          other.kind == this.kind &&
          other.parentId == this.parentId &&
          other.color == this.color &&
          other.unreadThreads == this.unreadThreads &&
          other.totalThreads == this.totalThreads &&
          other.sortOrder == this.sortOrder &&
          other.hidden == this.hidden);
}

class MailboxesCompanion extends UpdateCompanion<MailboxRow> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String> name;
  final Value<String?> role;
  final Value<String?> category;
  final Value<String> kind;
  final Value<String?> parentId;
  final Value<int?> color;
  final Value<int> unreadThreads;
  final Value<int> totalThreads;
  final Value<int> sortOrder;
  final Value<bool> hidden;
  const MailboxesCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.category = const Value.absent(),
    this.kind = const Value.absent(),
    this.parentId = const Value.absent(),
    this.color = const Value.absent(),
    this.unreadThreads = const Value.absent(),
    this.totalThreads = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.hidden = const Value.absent(),
  });
  MailboxesCompanion.insert({
    required String accountId,
    required String id,
    required String name,
    this.role = const Value.absent(),
    this.category = const Value.absent(),
    this.kind = const Value.absent(),
    this.parentId = const Value.absent(),
    this.color = const Value.absent(),
    this.unreadThreads = const Value.absent(),
    this.totalThreads = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.hidden = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       name = Value(name);
  static Insertable<MailboxRow> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? role,
    Expression<String>? category,
    Expression<String>? kind,
    Expression<String>? parentId,
    Expression<int>? color,
    Expression<int>? unreadThreads,
    Expression<int>? totalThreads,
    Expression<int>? sortOrder,
    Expression<bool>? hidden,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (category != null) 'category': category,
      if (kind != null) 'kind': kind,
      if (parentId != null) 'parent_id': parentId,
      if (color != null) 'color': color,
      if (unreadThreads != null) 'unread_threads': unreadThreads,
      if (totalThreads != null) 'total_threads': totalThreads,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (hidden != null) 'hidden': hidden,
    });
  }

  MailboxesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String>? name,
    Value<String?>? role,
    Value<String?>? category,
    Value<String>? kind,
    Value<String?>? parentId,
    Value<int?>? color,
    Value<int>? unreadThreads,
    Value<int>? totalThreads,
    Value<int>? sortOrder,
    Value<bool>? hidden,
  }) {
    return MailboxesCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      category: category ?? this.category,
      kind: kind ?? this.kind,
      parentId: parentId ?? this.parentId,
      color: color ?? this.color,
      unreadThreads: unreadThreads ?? this.unreadThreads,
      totalThreads: totalThreads ?? this.totalThreads,
      sortOrder: sortOrder ?? this.sortOrder,
      hidden: hidden ?? this.hidden,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (unreadThreads.present) {
      map['unread_threads'] = Variable<int>(unreadThreads.value);
    }
    if (totalThreads.present) {
      map['total_threads'] = Variable<int>(totalThreads.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MailboxesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('category: $category, ')
          ..write('kind: $kind, ')
          ..write('parentId: $parentId, ')
          ..write('color: $color, ')
          ..write('unreadThreads: $unreadThreads, ')
          ..write('totalThreads: $totalThreads, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('hidden: $hidden')
          ..write(')'))
        .toString();
  }
}

class Messages extends Table with TableInfo<Messages, MessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Messages(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  late final GeneratedColumn<int> rowId = GeneratedColumn<int>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES accounts(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'\'',
    defaultValue: const CustomExpression('\'\''),
  );
  static const VerificationMeta _fromAddrMeta = const VerificationMeta(
    'fromAddr',
  );
  late final GeneratedColumn<String> fromAddr = GeneratedColumn<String>(
    'from_addr',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _toAddrsMeta = const VerificationMeta(
    'toAddrs',
  );
  late final GeneratedColumn<String> toAddrs = GeneratedColumn<String>(
    'to_addrs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _ccAddrsMeta = const VerificationMeta(
    'ccAddrs',
  );
  late final GeneratedColumn<String> ccAddrs = GeneratedColumn<String>(
    'cc_addrs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _bccAddrsMeta = const VerificationMeta(
    'bccAddrs',
  );
  late final GeneratedColumn<String> bccAddrs = GeneratedColumn<String>(
    'bcc_addrs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _replyToAddrsMeta = const VerificationMeta(
    'replyToAddrs',
  );
  late final GeneratedColumn<String> replyToAddrs = GeneratedColumn<String>(
    'reply_to_addrs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  late final GeneratedColumn<int> date = GeneratedColumn<int>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _snippetMeta = const VerificationMeta(
    'snippet',
  );
  late final GeneratedColumn<String> snippet = GeneratedColumn<String>(
    'snippet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'\'',
    defaultValue: const CustomExpression('\'\''),
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT TRUE',
    defaultValue: const CustomExpression('TRUE'),
  );
  static const VerificationMeta _isFlaggedMeta = const VerificationMeta(
    'isFlagged',
  );
  late final GeneratedColumn<bool> isFlagged = GeneratedColumn<bool>(
    'is_flagged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _isDraftMeta = const VerificationMeta(
    'isDraft',
  );
  late final GeneratedColumn<bool> isDraft = GeneratedColumn<bool>(
    'is_draft',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _hasAttachmentsMeta = const VerificationMeta(
    'hasAttachments',
  );
  late final GeneratedColumn<bool> hasAttachments = GeneratedColumn<bool>(
    'has_attachments',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _attachmentsMeta = const VerificationMeta(
    'attachments',
  );
  late final GeneratedColumn<String> attachments = GeneratedColumn<String>(
    'attachments',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _messageIdHeaderMeta = const VerificationMeta(
    'messageIdHeader',
  );
  late final GeneratedColumn<String> messageIdHeader = GeneratedColumn<String>(
    'message_id_header',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _inReplyToMeta = const VerificationMeta(
    'inReplyTo',
  );
  late final GeneratedColumn<String> inReplyTo = GeneratedColumn<String>(
    'in_reply_to',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _refsMeta = const VerificationMeta('refs');
  late final GeneratedColumn<String> refs = GeneratedColumn<String>(
    'refs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _listUnsubscribeMeta = const VerificationMeta(
    'listUnsubscribe',
  );
  late final GeneratedColumn<String> listUnsubscribe = GeneratedColumn<String>(
    'list_unsubscribe',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    rowId,
    accountId,
    id,
    threadId,
    subject,
    fromAddr,
    toAddrs,
    ccAddrs,
    bccAddrs,
    replyToAddrs,
    date,
    snippet,
    isRead,
    isFlagged,
    isDraft,
    hasAttachments,
    attachments,
    messageIdHeader,
    inReplyTo,
    refs,
    listUnsubscribe,
    size,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    }
    if (data.containsKey('from_addr')) {
      context.handle(
        _fromAddrMeta,
        fromAddr.isAcceptableOrUnknown(data['from_addr']!, _fromAddrMeta),
      );
    }
    if (data.containsKey('to_addrs')) {
      context.handle(
        _toAddrsMeta,
        toAddrs.isAcceptableOrUnknown(data['to_addrs']!, _toAddrsMeta),
      );
    }
    if (data.containsKey('cc_addrs')) {
      context.handle(
        _ccAddrsMeta,
        ccAddrs.isAcceptableOrUnknown(data['cc_addrs']!, _ccAddrsMeta),
      );
    }
    if (data.containsKey('bcc_addrs')) {
      context.handle(
        _bccAddrsMeta,
        bccAddrs.isAcceptableOrUnknown(data['bcc_addrs']!, _bccAddrsMeta),
      );
    }
    if (data.containsKey('reply_to_addrs')) {
      context.handle(
        _replyToAddrsMeta,
        replyToAddrs.isAcceptableOrUnknown(
          data['reply_to_addrs']!,
          _replyToAddrsMeta,
        ),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('snippet')) {
      context.handle(
        _snippetMeta,
        snippet.isAcceptableOrUnknown(data['snippet']!, _snippetMeta),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    if (data.containsKey('is_flagged')) {
      context.handle(
        _isFlaggedMeta,
        isFlagged.isAcceptableOrUnknown(data['is_flagged']!, _isFlaggedMeta),
      );
    }
    if (data.containsKey('is_draft')) {
      context.handle(
        _isDraftMeta,
        isDraft.isAcceptableOrUnknown(data['is_draft']!, _isDraftMeta),
      );
    }
    if (data.containsKey('has_attachments')) {
      context.handle(
        _hasAttachmentsMeta,
        hasAttachments.isAcceptableOrUnknown(
          data['has_attachments']!,
          _hasAttachmentsMeta,
        ),
      );
    }
    if (data.containsKey('attachments')) {
      context.handle(
        _attachmentsMeta,
        attachments.isAcceptableOrUnknown(
          data['attachments']!,
          _attachmentsMeta,
        ),
      );
    }
    if (data.containsKey('message_id_header')) {
      context.handle(
        _messageIdHeaderMeta,
        messageIdHeader.isAcceptableOrUnknown(
          data['message_id_header']!,
          _messageIdHeaderMeta,
        ),
      );
    }
    if (data.containsKey('in_reply_to')) {
      context.handle(
        _inReplyToMeta,
        inReplyTo.isAcceptableOrUnknown(data['in_reply_to']!, _inReplyToMeta),
      );
    }
    if (data.containsKey('refs')) {
      context.handle(
        _refsMeta,
        refs.isAcceptableOrUnknown(data['refs']!, _refsMeta),
      );
    }
    if (data.containsKey('list_unsubscribe')) {
      context.handle(
        _listUnsubscribeMeta,
        listUnsubscribe.isAcceptableOrUnknown(
          data['list_unsubscribe']!,
          _listUnsubscribeMeta,
        ),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {accountId, id},
  ];
  @override
  MessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageRow(
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      fromAddr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_addr'],
      ),
      toAddrs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_addrs'],
      ),
      ccAddrs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cc_addrs'],
      ),
      bccAddrs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bcc_addrs'],
      ),
      replyToAddrs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_addrs'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date'],
      )!,
      snippet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snippet'],
      )!,
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      isFlagged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_flagged'],
      )!,
      isDraft: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_draft'],
      )!,
      hasAttachments: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_attachments'],
      )!,
      attachments: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments'],
      ),
      messageIdHeader: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id_header'],
      ),
      inReplyTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}in_reply_to'],
      ),
      refs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refs'],
      ),
      listUnsubscribe: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_unsubscribe'],
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
    );
  }

  @override
  Messages createAlias(String alias) {
    return Messages(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['UNIQUE(account_id, id)'];
  @override
  bool get dontWriteConstraints => true;
}

class MessageRow extends DataClass implements Insertable<MessageRow> {
  final int rowId;
  final String accountId;
  final String id;
  final String threadId;
  final String subject;
  final String? fromAddr;
  final String? toAddrs;
  final String? ccAddrs;
  final String? bccAddrs;
  final String? replyToAddrs;
  final int date;
  final String snippet;
  final bool isRead;
  final bool isFlagged;
  final bool isDraft;
  final bool hasAttachments;
  final String? attachments;
  final String? messageIdHeader;
  final String? inReplyTo;
  final String? refs;
  final String? listUnsubscribe;
  final int size;
  const MessageRow({
    required this.rowId,
    required this.accountId,
    required this.id,
    required this.threadId,
    required this.subject,
    this.fromAddr,
    this.toAddrs,
    this.ccAddrs,
    this.bccAddrs,
    this.replyToAddrs,
    required this.date,
    required this.snippet,
    required this.isRead,
    required this.isFlagged,
    required this.isDraft,
    required this.hasAttachments,
    this.attachments,
    this.messageIdHeader,
    this.inReplyTo,
    this.refs,
    this.listUnsubscribe,
    required this.size,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<int>(rowId);
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['thread_id'] = Variable<String>(threadId);
    map['subject'] = Variable<String>(subject);
    if (!nullToAbsent || fromAddr != null) {
      map['from_addr'] = Variable<String>(fromAddr);
    }
    if (!nullToAbsent || toAddrs != null) {
      map['to_addrs'] = Variable<String>(toAddrs);
    }
    if (!nullToAbsent || ccAddrs != null) {
      map['cc_addrs'] = Variable<String>(ccAddrs);
    }
    if (!nullToAbsent || bccAddrs != null) {
      map['bcc_addrs'] = Variable<String>(bccAddrs);
    }
    if (!nullToAbsent || replyToAddrs != null) {
      map['reply_to_addrs'] = Variable<String>(replyToAddrs);
    }
    map['date'] = Variable<int>(date);
    map['snippet'] = Variable<String>(snippet);
    map['is_read'] = Variable<bool>(isRead);
    map['is_flagged'] = Variable<bool>(isFlagged);
    map['is_draft'] = Variable<bool>(isDraft);
    map['has_attachments'] = Variable<bool>(hasAttachments);
    if (!nullToAbsent || attachments != null) {
      map['attachments'] = Variable<String>(attachments);
    }
    if (!nullToAbsent || messageIdHeader != null) {
      map['message_id_header'] = Variable<String>(messageIdHeader);
    }
    if (!nullToAbsent || inReplyTo != null) {
      map['in_reply_to'] = Variable<String>(inReplyTo);
    }
    if (!nullToAbsent || refs != null) {
      map['refs'] = Variable<String>(refs);
    }
    if (!nullToAbsent || listUnsubscribe != null) {
      map['list_unsubscribe'] = Variable<String>(listUnsubscribe);
    }
    map['size'] = Variable<int>(size);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      rowId: Value(rowId),
      accountId: Value(accountId),
      id: Value(id),
      threadId: Value(threadId),
      subject: Value(subject),
      fromAddr: fromAddr == null && nullToAbsent
          ? const Value.absent()
          : Value(fromAddr),
      toAddrs: toAddrs == null && nullToAbsent
          ? const Value.absent()
          : Value(toAddrs),
      ccAddrs: ccAddrs == null && nullToAbsent
          ? const Value.absent()
          : Value(ccAddrs),
      bccAddrs: bccAddrs == null && nullToAbsent
          ? const Value.absent()
          : Value(bccAddrs),
      replyToAddrs: replyToAddrs == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToAddrs),
      date: Value(date),
      snippet: Value(snippet),
      isRead: Value(isRead),
      isFlagged: Value(isFlagged),
      isDraft: Value(isDraft),
      hasAttachments: Value(hasAttachments),
      attachments: attachments == null && nullToAbsent
          ? const Value.absent()
          : Value(attachments),
      messageIdHeader: messageIdHeader == null && nullToAbsent
          ? const Value.absent()
          : Value(messageIdHeader),
      inReplyTo: inReplyTo == null && nullToAbsent
          ? const Value.absent()
          : Value(inReplyTo),
      refs: refs == null && nullToAbsent ? const Value.absent() : Value(refs),
      listUnsubscribe: listUnsubscribe == null && nullToAbsent
          ? const Value.absent()
          : Value(listUnsubscribe),
      size: Value(size),
    );
  }

  factory MessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageRow(
      rowId: serializer.fromJson<int>(json['row_id']),
      accountId: serializer.fromJson<String>(json['account_id']),
      id: serializer.fromJson<String>(json['id']),
      threadId: serializer.fromJson<String>(json['thread_id']),
      subject: serializer.fromJson<String>(json['subject']),
      fromAddr: serializer.fromJson<String?>(json['from_addr']),
      toAddrs: serializer.fromJson<String?>(json['to_addrs']),
      ccAddrs: serializer.fromJson<String?>(json['cc_addrs']),
      bccAddrs: serializer.fromJson<String?>(json['bcc_addrs']),
      replyToAddrs: serializer.fromJson<String?>(json['reply_to_addrs']),
      date: serializer.fromJson<int>(json['date']),
      snippet: serializer.fromJson<String>(json['snippet']),
      isRead: serializer.fromJson<bool>(json['is_read']),
      isFlagged: serializer.fromJson<bool>(json['is_flagged']),
      isDraft: serializer.fromJson<bool>(json['is_draft']),
      hasAttachments: serializer.fromJson<bool>(json['has_attachments']),
      attachments: serializer.fromJson<String?>(json['attachments']),
      messageIdHeader: serializer.fromJson<String?>(json['message_id_header']),
      inReplyTo: serializer.fromJson<String?>(json['in_reply_to']),
      refs: serializer.fromJson<String?>(json['refs']),
      listUnsubscribe: serializer.fromJson<String?>(json['list_unsubscribe']),
      size: serializer.fromJson<int>(json['size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'row_id': serializer.toJson<int>(rowId),
      'account_id': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'thread_id': serializer.toJson<String>(threadId),
      'subject': serializer.toJson<String>(subject),
      'from_addr': serializer.toJson<String?>(fromAddr),
      'to_addrs': serializer.toJson<String?>(toAddrs),
      'cc_addrs': serializer.toJson<String?>(ccAddrs),
      'bcc_addrs': serializer.toJson<String?>(bccAddrs),
      'reply_to_addrs': serializer.toJson<String?>(replyToAddrs),
      'date': serializer.toJson<int>(date),
      'snippet': serializer.toJson<String>(snippet),
      'is_read': serializer.toJson<bool>(isRead),
      'is_flagged': serializer.toJson<bool>(isFlagged),
      'is_draft': serializer.toJson<bool>(isDraft),
      'has_attachments': serializer.toJson<bool>(hasAttachments),
      'attachments': serializer.toJson<String?>(attachments),
      'message_id_header': serializer.toJson<String?>(messageIdHeader),
      'in_reply_to': serializer.toJson<String?>(inReplyTo),
      'refs': serializer.toJson<String?>(refs),
      'list_unsubscribe': serializer.toJson<String?>(listUnsubscribe),
      'size': serializer.toJson<int>(size),
    };
  }

  MessageRow copyWith({
    int? rowId,
    String? accountId,
    String? id,
    String? threadId,
    String? subject,
    Value<String?> fromAddr = const Value.absent(),
    Value<String?> toAddrs = const Value.absent(),
    Value<String?> ccAddrs = const Value.absent(),
    Value<String?> bccAddrs = const Value.absent(),
    Value<String?> replyToAddrs = const Value.absent(),
    int? date,
    String? snippet,
    bool? isRead,
    bool? isFlagged,
    bool? isDraft,
    bool? hasAttachments,
    Value<String?> attachments = const Value.absent(),
    Value<String?> messageIdHeader = const Value.absent(),
    Value<String?> inReplyTo = const Value.absent(),
    Value<String?> refs = const Value.absent(),
    Value<String?> listUnsubscribe = const Value.absent(),
    int? size,
  }) => MessageRow(
    rowId: rowId ?? this.rowId,
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    threadId: threadId ?? this.threadId,
    subject: subject ?? this.subject,
    fromAddr: fromAddr.present ? fromAddr.value : this.fromAddr,
    toAddrs: toAddrs.present ? toAddrs.value : this.toAddrs,
    ccAddrs: ccAddrs.present ? ccAddrs.value : this.ccAddrs,
    bccAddrs: bccAddrs.present ? bccAddrs.value : this.bccAddrs,
    replyToAddrs: replyToAddrs.present ? replyToAddrs.value : this.replyToAddrs,
    date: date ?? this.date,
    snippet: snippet ?? this.snippet,
    isRead: isRead ?? this.isRead,
    isFlagged: isFlagged ?? this.isFlagged,
    isDraft: isDraft ?? this.isDraft,
    hasAttachments: hasAttachments ?? this.hasAttachments,
    attachments: attachments.present ? attachments.value : this.attachments,
    messageIdHeader: messageIdHeader.present
        ? messageIdHeader.value
        : this.messageIdHeader,
    inReplyTo: inReplyTo.present ? inReplyTo.value : this.inReplyTo,
    refs: refs.present ? refs.value : this.refs,
    listUnsubscribe: listUnsubscribe.present
        ? listUnsubscribe.value
        : this.listUnsubscribe,
    size: size ?? this.size,
  );
  MessageRow copyWithCompanion(MessagesCompanion data) {
    return MessageRow(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      subject: data.subject.present ? data.subject.value : this.subject,
      fromAddr: data.fromAddr.present ? data.fromAddr.value : this.fromAddr,
      toAddrs: data.toAddrs.present ? data.toAddrs.value : this.toAddrs,
      ccAddrs: data.ccAddrs.present ? data.ccAddrs.value : this.ccAddrs,
      bccAddrs: data.bccAddrs.present ? data.bccAddrs.value : this.bccAddrs,
      replyToAddrs: data.replyToAddrs.present
          ? data.replyToAddrs.value
          : this.replyToAddrs,
      date: data.date.present ? data.date.value : this.date,
      snippet: data.snippet.present ? data.snippet.value : this.snippet,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      isFlagged: data.isFlagged.present ? data.isFlagged.value : this.isFlagged,
      isDraft: data.isDraft.present ? data.isDraft.value : this.isDraft,
      hasAttachments: data.hasAttachments.present
          ? data.hasAttachments.value
          : this.hasAttachments,
      attachments: data.attachments.present
          ? data.attachments.value
          : this.attachments,
      messageIdHeader: data.messageIdHeader.present
          ? data.messageIdHeader.value
          : this.messageIdHeader,
      inReplyTo: data.inReplyTo.present ? data.inReplyTo.value : this.inReplyTo,
      refs: data.refs.present ? data.refs.value : this.refs,
      listUnsubscribe: data.listUnsubscribe.present
          ? data.listUnsubscribe.value
          : this.listUnsubscribe,
      size: data.size.present ? data.size.value : this.size,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageRow(')
          ..write('rowId: $rowId, ')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('subject: $subject, ')
          ..write('fromAddr: $fromAddr, ')
          ..write('toAddrs: $toAddrs, ')
          ..write('ccAddrs: $ccAddrs, ')
          ..write('bccAddrs: $bccAddrs, ')
          ..write('replyToAddrs: $replyToAddrs, ')
          ..write('date: $date, ')
          ..write('snippet: $snippet, ')
          ..write('isRead: $isRead, ')
          ..write('isFlagged: $isFlagged, ')
          ..write('isDraft: $isDraft, ')
          ..write('hasAttachments: $hasAttachments, ')
          ..write('attachments: $attachments, ')
          ..write('messageIdHeader: $messageIdHeader, ')
          ..write('inReplyTo: $inReplyTo, ')
          ..write('refs: $refs, ')
          ..write('listUnsubscribe: $listUnsubscribe, ')
          ..write('size: $size')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    rowId,
    accountId,
    id,
    threadId,
    subject,
    fromAddr,
    toAddrs,
    ccAddrs,
    bccAddrs,
    replyToAddrs,
    date,
    snippet,
    isRead,
    isFlagged,
    isDraft,
    hasAttachments,
    attachments,
    messageIdHeader,
    inReplyTo,
    refs,
    listUnsubscribe,
    size,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageRow &&
          other.rowId == this.rowId &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.threadId == this.threadId &&
          other.subject == this.subject &&
          other.fromAddr == this.fromAddr &&
          other.toAddrs == this.toAddrs &&
          other.ccAddrs == this.ccAddrs &&
          other.bccAddrs == this.bccAddrs &&
          other.replyToAddrs == this.replyToAddrs &&
          other.date == this.date &&
          other.snippet == this.snippet &&
          other.isRead == this.isRead &&
          other.isFlagged == this.isFlagged &&
          other.isDraft == this.isDraft &&
          other.hasAttachments == this.hasAttachments &&
          other.attachments == this.attachments &&
          other.messageIdHeader == this.messageIdHeader &&
          other.inReplyTo == this.inReplyTo &&
          other.refs == this.refs &&
          other.listUnsubscribe == this.listUnsubscribe &&
          other.size == this.size);
}

class MessagesCompanion extends UpdateCompanion<MessageRow> {
  final Value<int> rowId;
  final Value<String> accountId;
  final Value<String> id;
  final Value<String> threadId;
  final Value<String> subject;
  final Value<String?> fromAddr;
  final Value<String?> toAddrs;
  final Value<String?> ccAddrs;
  final Value<String?> bccAddrs;
  final Value<String?> replyToAddrs;
  final Value<int> date;
  final Value<String> snippet;
  final Value<bool> isRead;
  final Value<bool> isFlagged;
  final Value<bool> isDraft;
  final Value<bool> hasAttachments;
  final Value<String?> attachments;
  final Value<String?> messageIdHeader;
  final Value<String?> inReplyTo;
  final Value<String?> refs;
  final Value<String?> listUnsubscribe;
  final Value<int> size;
  const MessagesCompanion({
    this.rowId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.threadId = const Value.absent(),
    this.subject = const Value.absent(),
    this.fromAddr = const Value.absent(),
    this.toAddrs = const Value.absent(),
    this.ccAddrs = const Value.absent(),
    this.bccAddrs = const Value.absent(),
    this.replyToAddrs = const Value.absent(),
    this.date = const Value.absent(),
    this.snippet = const Value.absent(),
    this.isRead = const Value.absent(),
    this.isFlagged = const Value.absent(),
    this.isDraft = const Value.absent(),
    this.hasAttachments = const Value.absent(),
    this.attachments = const Value.absent(),
    this.messageIdHeader = const Value.absent(),
    this.inReplyTo = const Value.absent(),
    this.refs = const Value.absent(),
    this.listUnsubscribe = const Value.absent(),
    this.size = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.rowId = const Value.absent(),
    required String accountId,
    required String id,
    required String threadId,
    this.subject = const Value.absent(),
    this.fromAddr = const Value.absent(),
    this.toAddrs = const Value.absent(),
    this.ccAddrs = const Value.absent(),
    this.bccAddrs = const Value.absent(),
    this.replyToAddrs = const Value.absent(),
    required int date,
    this.snippet = const Value.absent(),
    this.isRead = const Value.absent(),
    this.isFlagged = const Value.absent(),
    this.isDraft = const Value.absent(),
    this.hasAttachments = const Value.absent(),
    this.attachments = const Value.absent(),
    this.messageIdHeader = const Value.absent(),
    this.inReplyTo = const Value.absent(),
    this.refs = const Value.absent(),
    this.listUnsubscribe = const Value.absent(),
    this.size = const Value.absent(),
  }) : accountId = Value(accountId),
       id = Value(id),
       threadId = Value(threadId),
       date = Value(date);
  static Insertable<MessageRow> custom({
    Expression<int>? rowId,
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? threadId,
    Expression<String>? subject,
    Expression<String>? fromAddr,
    Expression<String>? toAddrs,
    Expression<String>? ccAddrs,
    Expression<String>? bccAddrs,
    Expression<String>? replyToAddrs,
    Expression<int>? date,
    Expression<String>? snippet,
    Expression<bool>? isRead,
    Expression<bool>? isFlagged,
    Expression<bool>? isDraft,
    Expression<bool>? hasAttachments,
    Expression<String>? attachments,
    Expression<String>? messageIdHeader,
    Expression<String>? inReplyTo,
    Expression<String>? refs,
    Expression<String>? listUnsubscribe,
    Expression<int>? size,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (threadId != null) 'thread_id': threadId,
      if (subject != null) 'subject': subject,
      if (fromAddr != null) 'from_addr': fromAddr,
      if (toAddrs != null) 'to_addrs': toAddrs,
      if (ccAddrs != null) 'cc_addrs': ccAddrs,
      if (bccAddrs != null) 'bcc_addrs': bccAddrs,
      if (replyToAddrs != null) 'reply_to_addrs': replyToAddrs,
      if (date != null) 'date': date,
      if (snippet != null) 'snippet': snippet,
      if (isRead != null) 'is_read': isRead,
      if (isFlagged != null) 'is_flagged': isFlagged,
      if (isDraft != null) 'is_draft': isDraft,
      if (hasAttachments != null) 'has_attachments': hasAttachments,
      if (attachments != null) 'attachments': attachments,
      if (messageIdHeader != null) 'message_id_header': messageIdHeader,
      if (inReplyTo != null) 'in_reply_to': inReplyTo,
      if (refs != null) 'refs': refs,
      if (listUnsubscribe != null) 'list_unsubscribe': listUnsubscribe,
      if (size != null) 'size': size,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? rowId,
    Value<String>? accountId,
    Value<String>? id,
    Value<String>? threadId,
    Value<String>? subject,
    Value<String?>? fromAddr,
    Value<String?>? toAddrs,
    Value<String?>? ccAddrs,
    Value<String?>? bccAddrs,
    Value<String?>? replyToAddrs,
    Value<int>? date,
    Value<String>? snippet,
    Value<bool>? isRead,
    Value<bool>? isFlagged,
    Value<bool>? isDraft,
    Value<bool>? hasAttachments,
    Value<String?>? attachments,
    Value<String?>? messageIdHeader,
    Value<String?>? inReplyTo,
    Value<String?>? refs,
    Value<String?>? listUnsubscribe,
    Value<int>? size,
  }) {
    return MessagesCompanion(
      rowId: rowId ?? this.rowId,
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      subject: subject ?? this.subject,
      fromAddr: fromAddr ?? this.fromAddr,
      toAddrs: toAddrs ?? this.toAddrs,
      ccAddrs: ccAddrs ?? this.ccAddrs,
      bccAddrs: bccAddrs ?? this.bccAddrs,
      replyToAddrs: replyToAddrs ?? this.replyToAddrs,
      date: date ?? this.date,
      snippet: snippet ?? this.snippet,
      isRead: isRead ?? this.isRead,
      isFlagged: isFlagged ?? this.isFlagged,
      isDraft: isDraft ?? this.isDraft,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      attachments: attachments ?? this.attachments,
      messageIdHeader: messageIdHeader ?? this.messageIdHeader,
      inReplyTo: inReplyTo ?? this.inReplyTo,
      refs: refs ?? this.refs,
      listUnsubscribe: listUnsubscribe ?? this.listUnsubscribe,
      size: size ?? this.size,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<int>(rowId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (fromAddr.present) {
      map['from_addr'] = Variable<String>(fromAddr.value);
    }
    if (toAddrs.present) {
      map['to_addrs'] = Variable<String>(toAddrs.value);
    }
    if (ccAddrs.present) {
      map['cc_addrs'] = Variable<String>(ccAddrs.value);
    }
    if (bccAddrs.present) {
      map['bcc_addrs'] = Variable<String>(bccAddrs.value);
    }
    if (replyToAddrs.present) {
      map['reply_to_addrs'] = Variable<String>(replyToAddrs.value);
    }
    if (date.present) {
      map['date'] = Variable<int>(date.value);
    }
    if (snippet.present) {
      map['snippet'] = Variable<String>(snippet.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (isFlagged.present) {
      map['is_flagged'] = Variable<bool>(isFlagged.value);
    }
    if (isDraft.present) {
      map['is_draft'] = Variable<bool>(isDraft.value);
    }
    if (hasAttachments.present) {
      map['has_attachments'] = Variable<bool>(hasAttachments.value);
    }
    if (attachments.present) {
      map['attachments'] = Variable<String>(attachments.value);
    }
    if (messageIdHeader.present) {
      map['message_id_header'] = Variable<String>(messageIdHeader.value);
    }
    if (inReplyTo.present) {
      map['in_reply_to'] = Variable<String>(inReplyTo.value);
    }
    if (refs.present) {
      map['refs'] = Variable<String>(refs.value);
    }
    if (listUnsubscribe.present) {
      map['list_unsubscribe'] = Variable<String>(listUnsubscribe.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('rowId: $rowId, ')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('subject: $subject, ')
          ..write('fromAddr: $fromAddr, ')
          ..write('toAddrs: $toAddrs, ')
          ..write('ccAddrs: $ccAddrs, ')
          ..write('bccAddrs: $bccAddrs, ')
          ..write('replyToAddrs: $replyToAddrs, ')
          ..write('date: $date, ')
          ..write('snippet: $snippet, ')
          ..write('isRead: $isRead, ')
          ..write('isFlagged: $isFlagged, ')
          ..write('isDraft: $isDraft, ')
          ..write('hasAttachments: $hasAttachments, ')
          ..write('attachments: $attachments, ')
          ..write('messageIdHeader: $messageIdHeader, ')
          ..write('inReplyTo: $inReplyTo, ')
          ..write('refs: $refs, ')
          ..write('listUnsubscribe: $listUnsubscribe, ')
          ..write('size: $size')
          ..write(')'))
        .toString();
  }
}

class MessageMailboxes extends Table
    with TableInfo<MessageMailboxes, MessageMailboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MessageMailboxes(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _mailboxIdMeta = const VerificationMeta(
    'mailboxId',
  );
  late final GeneratedColumn<String> mailboxId = GeneratedColumn<String>(
    'mailbox_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, messageId, mailboxId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_mailboxes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageMailboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('mailbox_id')) {
      context.handle(
        _mailboxIdMeta,
        mailboxId.isAcceptableOrUnknown(data['mailbox_id']!, _mailboxIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mailboxIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, messageId, mailboxId};
  @override
  MessageMailboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageMailboxRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      mailboxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mailbox_id'],
      )!,
    );
  }

  @override
  MessageMailboxes createAlias(String alias) {
    return MessageMailboxes(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(account_id, message_id, mailbox_id)',
    'FOREIGN KEY(account_id, message_id)REFERENCES messages(account_id, id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class MessageMailboxRow extends DataClass
    implements Insertable<MessageMailboxRow> {
  final String accountId;
  final String messageId;
  final String mailboxId;
  const MessageMailboxRow({
    required this.accountId,
    required this.messageId,
    required this.mailboxId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['message_id'] = Variable<String>(messageId);
    map['mailbox_id'] = Variable<String>(mailboxId);
    return map;
  }

  MessageMailboxesCompanion toCompanion(bool nullToAbsent) {
    return MessageMailboxesCompanion(
      accountId: Value(accountId),
      messageId: Value(messageId),
      mailboxId: Value(mailboxId),
    );
  }

  factory MessageMailboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageMailboxRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      messageId: serializer.fromJson<String>(json['message_id']),
      mailboxId: serializer.fromJson<String>(json['mailbox_id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'message_id': serializer.toJson<String>(messageId),
      'mailbox_id': serializer.toJson<String>(mailboxId),
    };
  }

  MessageMailboxRow copyWith({
    String? accountId,
    String? messageId,
    String? mailboxId,
  }) => MessageMailboxRow(
    accountId: accountId ?? this.accountId,
    messageId: messageId ?? this.messageId,
    mailboxId: mailboxId ?? this.mailboxId,
  );
  MessageMailboxRow copyWithCompanion(MessageMailboxesCompanion data) {
    return MessageMailboxRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      mailboxId: data.mailboxId.present ? data.mailboxId.value : this.mailboxId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageMailboxRow(')
          ..write('accountId: $accountId, ')
          ..write('messageId: $messageId, ')
          ..write('mailboxId: $mailboxId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, messageId, mailboxId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageMailboxRow &&
          other.accountId == this.accountId &&
          other.messageId == this.messageId &&
          other.mailboxId == this.mailboxId);
}

class MessageMailboxesCompanion extends UpdateCompanion<MessageMailboxRow> {
  final Value<String> accountId;
  final Value<String> messageId;
  final Value<String> mailboxId;
  const MessageMailboxesCompanion({
    this.accountId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.mailboxId = const Value.absent(),
  });
  MessageMailboxesCompanion.insert({
    required String accountId,
    required String messageId,
    required String mailboxId,
  }) : accountId = Value(accountId),
       messageId = Value(messageId),
       mailboxId = Value(mailboxId);
  static Insertable<MessageMailboxRow> custom({
    Expression<String>? accountId,
    Expression<String>? messageId,
    Expression<String>? mailboxId,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (messageId != null) 'message_id': messageId,
      if (mailboxId != null) 'mailbox_id': mailboxId,
    });
  }

  MessageMailboxesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? messageId,
    Value<String>? mailboxId,
  }) {
    return MessageMailboxesCompanion(
      accountId: accountId ?? this.accountId,
      messageId: messageId ?? this.messageId,
      mailboxId: mailboxId ?? this.mailboxId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (mailboxId.present) {
      map['mailbox_id'] = Variable<String>(mailboxId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageMailboxesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('messageId: $messageId, ')
          ..write('mailboxId: $mailboxId')
          ..write(')'))
        .toString();
  }
}

class Threads extends Table with TableInfo<Threads, ThreadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Threads(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES accounts(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _snippetMeta = const VerificationMeta(
    'snippet',
  );
  late final GeneratedColumn<String> snippet = GeneratedColumn<String>(
    'snippet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lastDateMeta = const VerificationMeta(
    'lastDate',
  );
  late final GeneratedColumn<int> lastDate = GeneratedColumn<int>(
    'last_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _messageCountMeta = const VerificationMeta(
    'messageCount',
  );
  late final GeneratedColumn<int> messageCount = GeneratedColumn<int>(
    'message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _flaggedMeta = const VerificationMeta(
    'flagged',
  );
  late final GeneratedColumn<bool> flagged = GeneratedColumn<bool>(
    'flagged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _hasAttachmentsMeta = const VerificationMeta(
    'hasAttachments',
  );
  late final GeneratedColumn<bool> hasAttachments = GeneratedColumn<bool>(
    'has_attachments',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _draftCountMeta = const VerificationMeta(
    'draftCount',
  );
  late final GeneratedColumn<int> draftCount = GeneratedColumn<int>(
    'draft_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _activeCountMeta = const VerificationMeta(
    'activeCount',
  );
  late final GeneratedColumn<int> activeCount = GeneratedColumn<int>(
    'active_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _participantsMeta = const VerificationMeta(
    'participants',
  );
  late final GeneratedColumn<String> participants = GeneratedColumn<String>(
    'participants',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _mailboxIdsMeta = const VerificationMeta(
    'mailboxIds',
  );
  late final GeneratedColumn<String> mailboxIds = GeneratedColumn<String>(
    'mailbox_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    id,
    subject,
    snippet,
    lastDate,
    messageCount,
    unreadCount,
    flagged,
    hasAttachments,
    draftCount,
    activeCount,
    participants,
    mailboxIds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'threads';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThreadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('snippet')) {
      context.handle(
        _snippetMeta,
        snippet.isAcceptableOrUnknown(data['snippet']!, _snippetMeta),
      );
    } else if (isInserting) {
      context.missing(_snippetMeta);
    }
    if (data.containsKey('last_date')) {
      context.handle(
        _lastDateMeta,
        lastDate.isAcceptableOrUnknown(data['last_date']!, _lastDateMeta),
      );
    } else if (isInserting) {
      context.missing(_lastDateMeta);
    }
    if (data.containsKey('message_count')) {
      context.handle(
        _messageCountMeta,
        messageCount.isAcceptableOrUnknown(
          data['message_count']!,
          _messageCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageCountMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unreadCountMeta);
    }
    if (data.containsKey('flagged')) {
      context.handle(
        _flaggedMeta,
        flagged.isAcceptableOrUnknown(data['flagged']!, _flaggedMeta),
      );
    } else if (isInserting) {
      context.missing(_flaggedMeta);
    }
    if (data.containsKey('has_attachments')) {
      context.handle(
        _hasAttachmentsMeta,
        hasAttachments.isAcceptableOrUnknown(
          data['has_attachments']!,
          _hasAttachmentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasAttachmentsMeta);
    }
    if (data.containsKey('draft_count')) {
      context.handle(
        _draftCountMeta,
        draftCount.isAcceptableOrUnknown(data['draft_count']!, _draftCountMeta),
      );
    } else if (isInserting) {
      context.missing(_draftCountMeta);
    }
    if (data.containsKey('active_count')) {
      context.handle(
        _activeCountMeta,
        activeCount.isAcceptableOrUnknown(
          data['active_count']!,
          _activeCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activeCountMeta);
    }
    if (data.containsKey('participants')) {
      context.handle(
        _participantsMeta,
        participants.isAcceptableOrUnknown(
          data['participants']!,
          _participantsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participantsMeta);
    }
    if (data.containsKey('mailbox_ids')) {
      context.handle(
        _mailboxIdsMeta,
        mailboxIds.isAcceptableOrUnknown(data['mailbox_ids']!, _mailboxIdsMeta),
      );
    } else if (isInserting) {
      context.missing(_mailboxIdsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, id};
  @override
  ThreadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreadRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      snippet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snippet'],
      )!,
      lastDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_date'],
      )!,
      messageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_count'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      flagged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}flagged'],
      )!,
      hasAttachments: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_attachments'],
      )!,
      draftCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}draft_count'],
      )!,
      activeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_count'],
      )!,
      participants: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participants'],
      )!,
      mailboxIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mailbox_ids'],
      )!,
    );
  }

  @override
  Threads createAlias(String alias) {
    return Threads(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const ['PRIMARY KEY(account_id, id)'];
  @override
  bool get dontWriteConstraints => true;
}

class ThreadRow extends DataClass implements Insertable<ThreadRow> {
  final String accountId;
  final String id;
  final String subject;
  final String snippet;
  final int lastDate;
  final int messageCount;
  final int unreadCount;
  final bool flagged;
  final bool hasAttachments;
  final int draftCount;
  final int activeCount;
  final String participants;
  final String mailboxIds;
  const ThreadRow({
    required this.accountId,
    required this.id,
    required this.subject,
    required this.snippet,
    required this.lastDate,
    required this.messageCount,
    required this.unreadCount,
    required this.flagged,
    required this.hasAttachments,
    required this.draftCount,
    required this.activeCount,
    required this.participants,
    required this.mailboxIds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['id'] = Variable<String>(id);
    map['subject'] = Variable<String>(subject);
    map['snippet'] = Variable<String>(snippet);
    map['last_date'] = Variable<int>(lastDate);
    map['message_count'] = Variable<int>(messageCount);
    map['unread_count'] = Variable<int>(unreadCount);
    map['flagged'] = Variable<bool>(flagged);
    map['has_attachments'] = Variable<bool>(hasAttachments);
    map['draft_count'] = Variable<int>(draftCount);
    map['active_count'] = Variable<int>(activeCount);
    map['participants'] = Variable<String>(participants);
    map['mailbox_ids'] = Variable<String>(mailboxIds);
    return map;
  }

  ThreadsCompanion toCompanion(bool nullToAbsent) {
    return ThreadsCompanion(
      accountId: Value(accountId),
      id: Value(id),
      subject: Value(subject),
      snippet: Value(snippet),
      lastDate: Value(lastDate),
      messageCount: Value(messageCount),
      unreadCount: Value(unreadCount),
      flagged: Value(flagged),
      hasAttachments: Value(hasAttachments),
      draftCount: Value(draftCount),
      activeCount: Value(activeCount),
      participants: Value(participants),
      mailboxIds: Value(mailboxIds),
    );
  }

  factory ThreadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreadRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      id: serializer.fromJson<String>(json['id']),
      subject: serializer.fromJson<String>(json['subject']),
      snippet: serializer.fromJson<String>(json['snippet']),
      lastDate: serializer.fromJson<int>(json['last_date']),
      messageCount: serializer.fromJson<int>(json['message_count']),
      unreadCount: serializer.fromJson<int>(json['unread_count']),
      flagged: serializer.fromJson<bool>(json['flagged']),
      hasAttachments: serializer.fromJson<bool>(json['has_attachments']),
      draftCount: serializer.fromJson<int>(json['draft_count']),
      activeCount: serializer.fromJson<int>(json['active_count']),
      participants: serializer.fromJson<String>(json['participants']),
      mailboxIds: serializer.fromJson<String>(json['mailbox_ids']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'id': serializer.toJson<String>(id),
      'subject': serializer.toJson<String>(subject),
      'snippet': serializer.toJson<String>(snippet),
      'last_date': serializer.toJson<int>(lastDate),
      'message_count': serializer.toJson<int>(messageCount),
      'unread_count': serializer.toJson<int>(unreadCount),
      'flagged': serializer.toJson<bool>(flagged),
      'has_attachments': serializer.toJson<bool>(hasAttachments),
      'draft_count': serializer.toJson<int>(draftCount),
      'active_count': serializer.toJson<int>(activeCount),
      'participants': serializer.toJson<String>(participants),
      'mailbox_ids': serializer.toJson<String>(mailboxIds),
    };
  }

  ThreadRow copyWith({
    String? accountId,
    String? id,
    String? subject,
    String? snippet,
    int? lastDate,
    int? messageCount,
    int? unreadCount,
    bool? flagged,
    bool? hasAttachments,
    int? draftCount,
    int? activeCount,
    String? participants,
    String? mailboxIds,
  }) => ThreadRow(
    accountId: accountId ?? this.accountId,
    id: id ?? this.id,
    subject: subject ?? this.subject,
    snippet: snippet ?? this.snippet,
    lastDate: lastDate ?? this.lastDate,
    messageCount: messageCount ?? this.messageCount,
    unreadCount: unreadCount ?? this.unreadCount,
    flagged: flagged ?? this.flagged,
    hasAttachments: hasAttachments ?? this.hasAttachments,
    draftCount: draftCount ?? this.draftCount,
    activeCount: activeCount ?? this.activeCount,
    participants: participants ?? this.participants,
    mailboxIds: mailboxIds ?? this.mailboxIds,
  );
  ThreadRow copyWithCompanion(ThreadsCompanion data) {
    return ThreadRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      id: data.id.present ? data.id.value : this.id,
      subject: data.subject.present ? data.subject.value : this.subject,
      snippet: data.snippet.present ? data.snippet.value : this.snippet,
      lastDate: data.lastDate.present ? data.lastDate.value : this.lastDate,
      messageCount: data.messageCount.present
          ? data.messageCount.value
          : this.messageCount,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      flagged: data.flagged.present ? data.flagged.value : this.flagged,
      hasAttachments: data.hasAttachments.present
          ? data.hasAttachments.value
          : this.hasAttachments,
      draftCount: data.draftCount.present
          ? data.draftCount.value
          : this.draftCount,
      activeCount: data.activeCount.present
          ? data.activeCount.value
          : this.activeCount,
      participants: data.participants.present
          ? data.participants.value
          : this.participants,
      mailboxIds: data.mailboxIds.present
          ? data.mailboxIds.value
          : this.mailboxIds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreadRow(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('snippet: $snippet, ')
          ..write('lastDate: $lastDate, ')
          ..write('messageCount: $messageCount, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('flagged: $flagged, ')
          ..write('hasAttachments: $hasAttachments, ')
          ..write('draftCount: $draftCount, ')
          ..write('activeCount: $activeCount, ')
          ..write('participants: $participants, ')
          ..write('mailboxIds: $mailboxIds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    id,
    subject,
    snippet,
    lastDate,
    messageCount,
    unreadCount,
    flagged,
    hasAttachments,
    draftCount,
    activeCount,
    participants,
    mailboxIds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreadRow &&
          other.accountId == this.accountId &&
          other.id == this.id &&
          other.subject == this.subject &&
          other.snippet == this.snippet &&
          other.lastDate == this.lastDate &&
          other.messageCount == this.messageCount &&
          other.unreadCount == this.unreadCount &&
          other.flagged == this.flagged &&
          other.hasAttachments == this.hasAttachments &&
          other.draftCount == this.draftCount &&
          other.activeCount == this.activeCount &&
          other.participants == this.participants &&
          other.mailboxIds == this.mailboxIds);
}

class ThreadsCompanion extends UpdateCompanion<ThreadRow> {
  final Value<String> accountId;
  final Value<String> id;
  final Value<String> subject;
  final Value<String> snippet;
  final Value<int> lastDate;
  final Value<int> messageCount;
  final Value<int> unreadCount;
  final Value<bool> flagged;
  final Value<bool> hasAttachments;
  final Value<int> draftCount;
  final Value<int> activeCount;
  final Value<String> participants;
  final Value<String> mailboxIds;
  const ThreadsCompanion({
    this.accountId = const Value.absent(),
    this.id = const Value.absent(),
    this.subject = const Value.absent(),
    this.snippet = const Value.absent(),
    this.lastDate = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.flagged = const Value.absent(),
    this.hasAttachments = const Value.absent(),
    this.draftCount = const Value.absent(),
    this.activeCount = const Value.absent(),
    this.participants = const Value.absent(),
    this.mailboxIds = const Value.absent(),
  });
  ThreadsCompanion.insert({
    required String accountId,
    required String id,
    required String subject,
    required String snippet,
    required int lastDate,
    required int messageCount,
    required int unreadCount,
    required bool flagged,
    required bool hasAttachments,
    required int draftCount,
    required int activeCount,
    required String participants,
    required String mailboxIds,
  }) : accountId = Value(accountId),
       id = Value(id),
       subject = Value(subject),
       snippet = Value(snippet),
       lastDate = Value(lastDate),
       messageCount = Value(messageCount),
       unreadCount = Value(unreadCount),
       flagged = Value(flagged),
       hasAttachments = Value(hasAttachments),
       draftCount = Value(draftCount),
       activeCount = Value(activeCount),
       participants = Value(participants),
       mailboxIds = Value(mailboxIds);
  static Insertable<ThreadRow> custom({
    Expression<String>? accountId,
    Expression<String>? id,
    Expression<String>? subject,
    Expression<String>? snippet,
    Expression<int>? lastDate,
    Expression<int>? messageCount,
    Expression<int>? unreadCount,
    Expression<bool>? flagged,
    Expression<bool>? hasAttachments,
    Expression<int>? draftCount,
    Expression<int>? activeCount,
    Expression<String>? participants,
    Expression<String>? mailboxIds,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (id != null) 'id': id,
      if (subject != null) 'subject': subject,
      if (snippet != null) 'snippet': snippet,
      if (lastDate != null) 'last_date': lastDate,
      if (messageCount != null) 'message_count': messageCount,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (flagged != null) 'flagged': flagged,
      if (hasAttachments != null) 'has_attachments': hasAttachments,
      if (draftCount != null) 'draft_count': draftCount,
      if (activeCount != null) 'active_count': activeCount,
      if (participants != null) 'participants': participants,
      if (mailboxIds != null) 'mailbox_ids': mailboxIds,
    });
  }

  ThreadsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? id,
    Value<String>? subject,
    Value<String>? snippet,
    Value<int>? lastDate,
    Value<int>? messageCount,
    Value<int>? unreadCount,
    Value<bool>? flagged,
    Value<bool>? hasAttachments,
    Value<int>? draftCount,
    Value<int>? activeCount,
    Value<String>? participants,
    Value<String>? mailboxIds,
  }) {
    return ThreadsCompanion(
      accountId: accountId ?? this.accountId,
      id: id ?? this.id,
      subject: subject ?? this.subject,
      snippet: snippet ?? this.snippet,
      lastDate: lastDate ?? this.lastDate,
      messageCount: messageCount ?? this.messageCount,
      unreadCount: unreadCount ?? this.unreadCount,
      flagged: flagged ?? this.flagged,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      draftCount: draftCount ?? this.draftCount,
      activeCount: activeCount ?? this.activeCount,
      participants: participants ?? this.participants,
      mailboxIds: mailboxIds ?? this.mailboxIds,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (snippet.present) {
      map['snippet'] = Variable<String>(snippet.value);
    }
    if (lastDate.present) {
      map['last_date'] = Variable<int>(lastDate.value);
    }
    if (messageCount.present) {
      map['message_count'] = Variable<int>(messageCount.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (flagged.present) {
      map['flagged'] = Variable<bool>(flagged.value);
    }
    if (hasAttachments.present) {
      map['has_attachments'] = Variable<bool>(hasAttachments.value);
    }
    if (draftCount.present) {
      map['draft_count'] = Variable<int>(draftCount.value);
    }
    if (activeCount.present) {
      map['active_count'] = Variable<int>(activeCount.value);
    }
    if (participants.present) {
      map['participants'] = Variable<String>(participants.value);
    }
    if (mailboxIds.present) {
      map['mailbox_ids'] = Variable<String>(mailboxIds.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('id: $id, ')
          ..write('subject: $subject, ')
          ..write('snippet: $snippet, ')
          ..write('lastDate: $lastDate, ')
          ..write('messageCount: $messageCount, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('flagged: $flagged, ')
          ..write('hasAttachments: $hasAttachments, ')
          ..write('draftCount: $draftCount, ')
          ..write('activeCount: $activeCount, ')
          ..write('participants: $participants, ')
          ..write('mailboxIds: $mailboxIds')
          ..write(')'))
        .toString();
  }
}

class ThreadMailboxes extends Table
    with TableInfo<ThreadMailboxes, ThreadMailboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ThreadMailboxes(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _mailboxIdMeta = const VerificationMeta(
    'mailboxId',
  );
  late final GeneratedColumn<String> mailboxId = GeneratedColumn<String>(
    'mailbox_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lastDateMeta = const VerificationMeta(
    'lastDate',
  );
  late final GeneratedColumn<int> lastDate = GeneratedColumn<int>(
    'last_date',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _unreadMeta = const VerificationMeta('unread');
  late final GeneratedColumn<bool> unread = GeneratedColumn<bool>(
    'unread',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    threadId,
    mailboxId,
    lastDate,
    unread,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thread_mailboxes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThreadMailboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('mailbox_id')) {
      context.handle(
        _mailboxIdMeta,
        mailboxId.isAcceptableOrUnknown(data['mailbox_id']!, _mailboxIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mailboxIdMeta);
    }
    if (data.containsKey('last_date')) {
      context.handle(
        _lastDateMeta,
        lastDate.isAcceptableOrUnknown(data['last_date']!, _lastDateMeta),
      );
    } else if (isInserting) {
      context.missing(_lastDateMeta);
    }
    if (data.containsKey('unread')) {
      context.handle(
        _unreadMeta,
        unread.isAcceptableOrUnknown(data['unread']!, _unreadMeta),
      );
    } else if (isInserting) {
      context.missing(_unreadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, threadId, mailboxId};
  @override
  ThreadMailboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreadMailboxRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      mailboxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mailbox_id'],
      )!,
      lastDate: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_date'],
      )!,
      unread: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}unread'],
      )!,
    );
  }

  @override
  ThreadMailboxes createAlias(String alias) {
    return ThreadMailboxes(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(account_id, thread_id, mailbox_id)',
    'FOREIGN KEY(account_id, thread_id)REFERENCES threads(account_id, id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ThreadMailboxRow extends DataClass
    implements Insertable<ThreadMailboxRow> {
  final String accountId;
  final String threadId;
  final String mailboxId;
  final int lastDate;
  final bool unread;
  const ThreadMailboxRow({
    required this.accountId,
    required this.threadId,
    required this.mailboxId,
    required this.lastDate,
    required this.unread,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['thread_id'] = Variable<String>(threadId);
    map['mailbox_id'] = Variable<String>(mailboxId);
    map['last_date'] = Variable<int>(lastDate);
    map['unread'] = Variable<bool>(unread);
    return map;
  }

  ThreadMailboxesCompanion toCompanion(bool nullToAbsent) {
    return ThreadMailboxesCompanion(
      accountId: Value(accountId),
      threadId: Value(threadId),
      mailboxId: Value(mailboxId),
      lastDate: Value(lastDate),
      unread: Value(unread),
    );
  }

  factory ThreadMailboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreadMailboxRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      threadId: serializer.fromJson<String>(json['thread_id']),
      mailboxId: serializer.fromJson<String>(json['mailbox_id']),
      lastDate: serializer.fromJson<int>(json['last_date']),
      unread: serializer.fromJson<bool>(json['unread']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'thread_id': serializer.toJson<String>(threadId),
      'mailbox_id': serializer.toJson<String>(mailboxId),
      'last_date': serializer.toJson<int>(lastDate),
      'unread': serializer.toJson<bool>(unread),
    };
  }

  ThreadMailboxRow copyWith({
    String? accountId,
    String? threadId,
    String? mailboxId,
    int? lastDate,
    bool? unread,
  }) => ThreadMailboxRow(
    accountId: accountId ?? this.accountId,
    threadId: threadId ?? this.threadId,
    mailboxId: mailboxId ?? this.mailboxId,
    lastDate: lastDate ?? this.lastDate,
    unread: unread ?? this.unread,
  );
  ThreadMailboxRow copyWithCompanion(ThreadMailboxesCompanion data) {
    return ThreadMailboxRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      mailboxId: data.mailboxId.present ? data.mailboxId.value : this.mailboxId,
      lastDate: data.lastDate.present ? data.lastDate.value : this.lastDate,
      unread: data.unread.present ? data.unread.value : this.unread,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreadMailboxRow(')
          ..write('accountId: $accountId, ')
          ..write('threadId: $threadId, ')
          ..write('mailboxId: $mailboxId, ')
          ..write('lastDate: $lastDate, ')
          ..write('unread: $unread')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, threadId, mailboxId, lastDate, unread);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreadMailboxRow &&
          other.accountId == this.accountId &&
          other.threadId == this.threadId &&
          other.mailboxId == this.mailboxId &&
          other.lastDate == this.lastDate &&
          other.unread == this.unread);
}

class ThreadMailboxesCompanion extends UpdateCompanion<ThreadMailboxRow> {
  final Value<String> accountId;
  final Value<String> threadId;
  final Value<String> mailboxId;
  final Value<int> lastDate;
  final Value<bool> unread;
  const ThreadMailboxesCompanion({
    this.accountId = const Value.absent(),
    this.threadId = const Value.absent(),
    this.mailboxId = const Value.absent(),
    this.lastDate = const Value.absent(),
    this.unread = const Value.absent(),
  });
  ThreadMailboxesCompanion.insert({
    required String accountId,
    required String threadId,
    required String mailboxId,
    required int lastDate,
    required bool unread,
  }) : accountId = Value(accountId),
       threadId = Value(threadId),
       mailboxId = Value(mailboxId),
       lastDate = Value(lastDate),
       unread = Value(unread);
  static Insertable<ThreadMailboxRow> custom({
    Expression<String>? accountId,
    Expression<String>? threadId,
    Expression<String>? mailboxId,
    Expression<int>? lastDate,
    Expression<bool>? unread,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (threadId != null) 'thread_id': threadId,
      if (mailboxId != null) 'mailbox_id': mailboxId,
      if (lastDate != null) 'last_date': lastDate,
      if (unread != null) 'unread': unread,
    });
  }

  ThreadMailboxesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? threadId,
    Value<String>? mailboxId,
    Value<int>? lastDate,
    Value<bool>? unread,
  }) {
    return ThreadMailboxesCompanion(
      accountId: accountId ?? this.accountId,
      threadId: threadId ?? this.threadId,
      mailboxId: mailboxId ?? this.mailboxId,
      lastDate: lastDate ?? this.lastDate,
      unread: unread ?? this.unread,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (mailboxId.present) {
      map['mailbox_id'] = Variable<String>(mailboxId.value);
    }
    if (lastDate.present) {
      map['last_date'] = Variable<int>(lastDate.value);
    }
    if (unread.present) {
      map['unread'] = Variable<bool>(unread.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadMailboxesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('threadId: $threadId, ')
          ..write('mailboxId: $mailboxId, ')
          ..write('lastDate: $lastDate, ')
          ..write('unread: $unread')
          ..write(')'))
        .toString();
  }
}

class Bodies extends Table with TableInfo<Bodies, BodyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Bodies(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _htmlMeta = const VerificationMeta('html');
  late final GeneratedColumn<String> html = GeneratedColumn<String>(
    'html',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _plainMeta = const VerificationMeta('plain');
  late final GeneratedColumn<String> plain = GeneratedColumn<String>(
    'plain',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, messageId, html, plain];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bodies';
  @override
  VerificationContext validateIntegrity(
    Insertable<BodyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('html')) {
      context.handle(
        _htmlMeta,
        html.isAcceptableOrUnknown(data['html']!, _htmlMeta),
      );
    }
    if (data.containsKey('plain')) {
      context.handle(
        _plainMeta,
        plain.isAcceptableOrUnknown(data['plain']!, _plainMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, messageId};
  @override
  BodyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BodyRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      html: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}html'],
      ),
      plain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plain'],
      ),
    );
  }

  @override
  Bodies createAlias(String alias) {
    return Bodies(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(account_id, message_id)',
    'FOREIGN KEY(account_id, message_id)REFERENCES messages(account_id, id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class BodyRow extends DataClass implements Insertable<BodyRow> {
  final String accountId;
  final String messageId;
  final String? html;
  final String? plain;
  const BodyRow({
    required this.accountId,
    required this.messageId,
    this.html,
    this.plain,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['message_id'] = Variable<String>(messageId);
    if (!nullToAbsent || html != null) {
      map['html'] = Variable<String>(html);
    }
    if (!nullToAbsent || plain != null) {
      map['plain'] = Variable<String>(plain);
    }
    return map;
  }

  BodiesCompanion toCompanion(bool nullToAbsent) {
    return BodiesCompanion(
      accountId: Value(accountId),
      messageId: Value(messageId),
      html: html == null && nullToAbsent ? const Value.absent() : Value(html),
      plain: plain == null && nullToAbsent
          ? const Value.absent()
          : Value(plain),
    );
  }

  factory BodyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BodyRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      messageId: serializer.fromJson<String>(json['message_id']),
      html: serializer.fromJson<String?>(json['html']),
      plain: serializer.fromJson<String?>(json['plain']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'message_id': serializer.toJson<String>(messageId),
      'html': serializer.toJson<String?>(html),
      'plain': serializer.toJson<String?>(plain),
    };
  }

  BodyRow copyWith({
    String? accountId,
    String? messageId,
    Value<String?> html = const Value.absent(),
    Value<String?> plain = const Value.absent(),
  }) => BodyRow(
    accountId: accountId ?? this.accountId,
    messageId: messageId ?? this.messageId,
    html: html.present ? html.value : this.html,
    plain: plain.present ? plain.value : this.plain,
  );
  BodyRow copyWithCompanion(BodiesCompanion data) {
    return BodyRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      html: data.html.present ? data.html.value : this.html,
      plain: data.plain.present ? data.plain.value : this.plain,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BodyRow(')
          ..write('accountId: $accountId, ')
          ..write('messageId: $messageId, ')
          ..write('html: $html, ')
          ..write('plain: $plain')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, messageId, html, plain);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BodyRow &&
          other.accountId == this.accountId &&
          other.messageId == this.messageId &&
          other.html == this.html &&
          other.plain == this.plain);
}

class BodiesCompanion extends UpdateCompanion<BodyRow> {
  final Value<String> accountId;
  final Value<String> messageId;
  final Value<String?> html;
  final Value<String?> plain;
  final Value<int> rowid;
  const BodiesCompanion({
    this.accountId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.html = const Value.absent(),
    this.plain = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BodiesCompanion.insert({
    required String accountId,
    required String messageId,
    this.html = const Value.absent(),
    this.plain = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       messageId = Value(messageId);
  static Insertable<BodyRow> custom({
    Expression<String>? accountId,
    Expression<String>? messageId,
    Expression<String>? html,
    Expression<String>? plain,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (messageId != null) 'message_id': messageId,
      if (html != null) 'html': html,
      if (plain != null) 'plain': plain,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BodiesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? messageId,
    Value<String?>? html,
    Value<String?>? plain,
    Value<int>? rowid,
  }) {
    return BodiesCompanion(
      accountId: accountId ?? this.accountId,
      messageId: messageId ?? this.messageId,
      html: html ?? this.html,
      plain: plain ?? this.plain,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (html.present) {
      map['html'] = Variable<String>(html.value);
    }
    if (plain.present) {
      map['plain'] = Variable<String>(plain.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BodiesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('messageId: $messageId, ')
          ..write('html: $html, ')
          ..write('plain: $plain, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class BodyParts extends Table with TableInfo<BodyParts, BodyPartRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  BodyParts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _contentIdMeta = const VerificationMeta(
    'contentId',
  );
  late final GeneratedColumn<String> contentId = GeneratedColumn<String>(
    'content_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  late final GeneratedColumn<Uint8List> data = GeneratedColumn<Uint8List>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, messageId, contentId, data];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'body_parts';
  @override
  VerificationContext validateIntegrity(
    Insertable<BodyPartRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('content_id')) {
      context.handle(
        _contentIdMeta,
        contentId.isAcceptableOrUnknown(data['content_id']!, _contentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contentIdMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, messageId, contentId};
  @override
  BodyPartRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BodyPartRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      contentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}data'],
      )!,
    );
  }

  @override
  BodyParts createAlias(String alias) {
    return BodyParts(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(account_id, message_id, content_id)',
    'FOREIGN KEY(account_id, message_id)REFERENCES bodies(account_id, message_id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class BodyPartRow extends DataClass implements Insertable<BodyPartRow> {
  final String accountId;
  final String messageId;
  final String contentId;
  final Uint8List data;
  const BodyPartRow({
    required this.accountId,
    required this.messageId,
    required this.contentId,
    required this.data,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['message_id'] = Variable<String>(messageId);
    map['content_id'] = Variable<String>(contentId);
    map['data'] = Variable<Uint8List>(data);
    return map;
  }

  BodyPartsCompanion toCompanion(bool nullToAbsent) {
    return BodyPartsCompanion(
      accountId: Value(accountId),
      messageId: Value(messageId),
      contentId: Value(contentId),
      data: Value(data),
    );
  }

  factory BodyPartRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BodyPartRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      messageId: serializer.fromJson<String>(json['message_id']),
      contentId: serializer.fromJson<String>(json['content_id']),
      data: serializer.fromJson<Uint8List>(json['data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'message_id': serializer.toJson<String>(messageId),
      'content_id': serializer.toJson<String>(contentId),
      'data': serializer.toJson<Uint8List>(data),
    };
  }

  BodyPartRow copyWith({
    String? accountId,
    String? messageId,
    String? contentId,
    Uint8List? data,
  }) => BodyPartRow(
    accountId: accountId ?? this.accountId,
    messageId: messageId ?? this.messageId,
    contentId: contentId ?? this.contentId,
    data: data ?? this.data,
  );
  BodyPartRow copyWithCompanion(BodyPartsCompanion data) {
    return BodyPartRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      contentId: data.contentId.present ? data.contentId.value : this.contentId,
      data: data.data.present ? data.data.value : this.data,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BodyPartRow(')
          ..write('accountId: $accountId, ')
          ..write('messageId: $messageId, ')
          ..write('contentId: $contentId, ')
          ..write('data: $data')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    messageId,
    contentId,
    $driftBlobEquality.hash(data),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BodyPartRow &&
          other.accountId == this.accountId &&
          other.messageId == this.messageId &&
          other.contentId == this.contentId &&
          $driftBlobEquality.equals(other.data, this.data));
}

class BodyPartsCompanion extends UpdateCompanion<BodyPartRow> {
  final Value<String> accountId;
  final Value<String> messageId;
  final Value<String> contentId;
  final Value<Uint8List> data;
  final Value<int> rowid;
  const BodyPartsCompanion({
    this.accountId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.contentId = const Value.absent(),
    this.data = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BodyPartsCompanion.insert({
    required String accountId,
    required String messageId,
    required String contentId,
    required Uint8List data,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       messageId = Value(messageId),
       contentId = Value(contentId),
       data = Value(data);
  static Insertable<BodyPartRow> custom({
    Expression<String>? accountId,
    Expression<String>? messageId,
    Expression<String>? contentId,
    Expression<Uint8List>? data,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (messageId != null) 'message_id': messageId,
      if (contentId != null) 'content_id': contentId,
      if (data != null) 'data': data,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BodyPartsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? messageId,
    Value<String>? contentId,
    Value<Uint8List>? data,
    Value<int>? rowid,
  }) {
    return BodyPartsCompanion(
      accountId: accountId ?? this.accountId,
      messageId: messageId ?? this.messageId,
      contentId: contentId ?? this.contentId,
      data: data ?? this.data,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (contentId.present) {
      map['content_id'] = Variable<String>(contentId.value);
    }
    if (data.present) {
      map['data'] = Variable<Uint8List>(data.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BodyPartsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('messageId: $messageId, ')
          ..write('contentId: $contentId, ')
          ..write('data: $data, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Contacts extends Table with TableInfo<Contacts, ContactRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Contacts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _useCountMeta = const VerificationMeta(
    'useCount',
  );
  late final GeneratedColumn<int> useCount = GeneratedColumn<int>(
    'use_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _lastUsedMeta = const VerificationMeta(
    'lastUsed',
  );
  late final GeneratedColumn<int> lastUsed = GeneratedColumn<int>(
    'last_used',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [email, name, useCount, lastUsed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContactRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('use_count')) {
      context.handle(
        _useCountMeta,
        useCount.isAcceptableOrUnknown(data['use_count']!, _useCountMeta),
      );
    }
    if (data.containsKey('last_used')) {
      context.handle(
        _lastUsedMeta,
        lastUsed.isAcceptableOrUnknown(data['last_used']!, _lastUsedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {email};
  @override
  ContactRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContactRow(
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      useCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}use_count'],
      )!,
      lastUsed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_used'],
      )!,
    );
  }

  @override
  Contacts createAlias(String alias) {
    return Contacts(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  bool get dontWriteConstraints => true;
}

class ContactRow extends DataClass implements Insertable<ContactRow> {
  final String email;
  final String? name;
  final int useCount;
  final int lastUsed;
  const ContactRow({
    required this.email,
    this.name,
    required this.useCount,
    required this.lastUsed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['use_count'] = Variable<int>(useCount);
    map['last_used'] = Variable<int>(lastUsed);
    return map;
  }

  ContactsCompanion toCompanion(bool nullToAbsent) {
    return ContactsCompanion(
      email: Value(email),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      useCount: Value(useCount),
      lastUsed: Value(lastUsed),
    );
  }

  factory ContactRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContactRow(
      email: serializer.fromJson<String>(json['email']),
      name: serializer.fromJson<String?>(json['name']),
      useCount: serializer.fromJson<int>(json['use_count']),
      lastUsed: serializer.fromJson<int>(json['last_used']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'email': serializer.toJson<String>(email),
      'name': serializer.toJson<String?>(name),
      'use_count': serializer.toJson<int>(useCount),
      'last_used': serializer.toJson<int>(lastUsed),
    };
  }

  ContactRow copyWith({
    String? email,
    Value<String?> name = const Value.absent(),
    int? useCount,
    int? lastUsed,
  }) => ContactRow(
    email: email ?? this.email,
    name: name.present ? name.value : this.name,
    useCount: useCount ?? this.useCount,
    lastUsed: lastUsed ?? this.lastUsed,
  );
  ContactRow copyWithCompanion(ContactsCompanion data) {
    return ContactRow(
      email: data.email.present ? data.email.value : this.email,
      name: data.name.present ? data.name.value : this.name,
      useCount: data.useCount.present ? data.useCount.value : this.useCount,
      lastUsed: data.lastUsed.present ? data.lastUsed.value : this.lastUsed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContactRow(')
          ..write('email: $email, ')
          ..write('name: $name, ')
          ..write('useCount: $useCount, ')
          ..write('lastUsed: $lastUsed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(email, name, useCount, lastUsed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactRow &&
          other.email == this.email &&
          other.name == this.name &&
          other.useCount == this.useCount &&
          other.lastUsed == this.lastUsed);
}

class ContactsCompanion extends UpdateCompanion<ContactRow> {
  final Value<String> email;
  final Value<String?> name;
  final Value<int> useCount;
  final Value<int> lastUsed;
  const ContactsCompanion({
    this.email = const Value.absent(),
    this.name = const Value.absent(),
    this.useCount = const Value.absent(),
    this.lastUsed = const Value.absent(),
  });
  ContactsCompanion.insert({
    required String email,
    this.name = const Value.absent(),
    this.useCount = const Value.absent(),
    this.lastUsed = const Value.absent(),
  }) : email = Value(email);
  static Insertable<ContactRow> custom({
    Expression<String>? email,
    Expression<String>? name,
    Expression<int>? useCount,
    Expression<int>? lastUsed,
  }) {
    return RawValuesInsertable({
      if (email != null) 'email': email,
      if (name != null) 'name': name,
      if (useCount != null) 'use_count': useCount,
      if (lastUsed != null) 'last_used': lastUsed,
    });
  }

  ContactsCompanion copyWith({
    Value<String>? email,
    Value<String?>? name,
    Value<int>? useCount,
    Value<int>? lastUsed,
  }) {
    return ContactsCompanion(
      email: email ?? this.email,
      name: name ?? this.name,
      useCount: useCount ?? this.useCount,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (useCount.present) {
      map['use_count'] = Variable<int>(useCount.value);
    }
    if (lastUsed.present) {
      map['last_used'] = Variable<int>(lastUsed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('email: $email, ')
          ..write('name: $name, ')
          ..write('useCount: $useCount, ')
          ..write('lastUsed: $lastUsed')
          ..write(')'))
        .toString();
  }
}

class SyncState extends Table with TableInfo<SyncState, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  SyncState(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES accounts(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, key};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  SyncState createAlias(String alias) {
    return SyncState(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(account_id, "key")',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  final String accountId;
  final String key;
  final String value;
  const SyncStateRow({
    required this.accountId,
    required this.key,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      accountId: Value(accountId),
      key: Value(key),
      value: Value(value),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      accountId: serializer.fromJson<String>(json['account_id']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'account_id': serializer.toJson<String>(accountId),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateRow copyWith({String? accountId, String? key, String? value}) =>
      SyncStateRow(
        accountId: accountId ?? this.accountId,
        key: key ?? this.key,
        value: value ?? this.value,
      );
  SyncStateRow copyWithCompanion(SyncStateCompanion data) {
    return SyncStateRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('accountId: $accountId, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.accountId == this.accountId &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<String> accountId;
  final Value<String> key;
  final Value<String> value;
  const SyncStateCompanion({
    this.accountId = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String accountId,
    required String key,
    required String value,
  }) : accountId = Value(accountId),
       key = Value(key),
       value = Value(value);
  static Insertable<SyncStateRow> custom({
    Expression<String>? accountId,
    Expression<String>? key,
    Expression<String>? value,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? accountId,
    Value<String>? key,
    Value<String>? value,
  }) {
    return SyncStateCompanion(
      accountId: accountId ?? this.accountId,
      key: key ?? this.key,
      value: value ?? this.value,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('accountId: $accountId, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

class PendingOps extends Table with TableInfo<PendingOps, PendingOpRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PendingOps(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES accounts(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _notBeforeMeta = const VerificationMeta(
    'notBefore',
  );
  late final GeneratedColumn<int> notBefore = GeneratedColumn<int>(
    'not_before',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    payload,
    attempts,
    lastError,
    notBefore,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_ops';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingOpRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('not_before')) {
      context.handle(
        _notBeforeMeta,
        notBefore.isAcceptableOrUnknown(data['not_before']!, _notBeforeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingOpRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingOpRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      notBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}not_before'],
      ),
    );
  }

  @override
  PendingOps createAlias(String alias) {
    return PendingOps(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PendingOpRow extends DataClass implements Insertable<PendingOpRow> {
  final int id;
  final String accountId;
  final String payload;
  final int attempts;
  final String? lastError;
  final int? notBefore;
  const PendingOpRow({
    required this.id,
    required this.accountId,
    required this.payload,
    required this.attempts,
    this.lastError,
    this.notBefore,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<String>(accountId);
    map['payload'] = Variable<String>(payload);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || notBefore != null) {
      map['not_before'] = Variable<int>(notBefore);
    }
    return map;
  }

  PendingOpsCompanion toCompanion(bool nullToAbsent) {
    return PendingOpsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      payload: Value(payload),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      notBefore: notBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(notBefore),
    );
  }

  factory PendingOpRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingOpRow(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String>(json['account_id']),
      payload: serializer.fromJson<String>(json['payload']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['last_error']),
      notBefore: serializer.fromJson<int?>(json['not_before']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'account_id': serializer.toJson<String>(accountId),
      'payload': serializer.toJson<String>(payload),
      'attempts': serializer.toJson<int>(attempts),
      'last_error': serializer.toJson<String?>(lastError),
      'not_before': serializer.toJson<int?>(notBefore),
    };
  }

  PendingOpRow copyWith({
    int? id,
    String? accountId,
    String? payload,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<int?> notBefore = const Value.absent(),
  }) => PendingOpRow(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    payload: payload ?? this.payload,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    notBefore: notBefore.present ? notBefore.value : this.notBefore,
  );
  PendingOpRow copyWithCompanion(PendingOpsCompanion data) {
    return PendingOpRow(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      payload: data.payload.present ? data.payload.value : this.payload,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      notBefore: data.notBefore.present ? data.notBefore.value : this.notBefore,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingOpRow(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('payload: $payload, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('notBefore: $notBefore')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, accountId, payload, attempts, lastError, notBefore);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingOpRow &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.payload == this.payload &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.notBefore == this.notBefore);
}

class PendingOpsCompanion extends UpdateCompanion<PendingOpRow> {
  final Value<int> id;
  final Value<String> accountId;
  final Value<String> payload;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int?> notBefore;
  const PendingOpsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.payload = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.notBefore = const Value.absent(),
  });
  PendingOpsCompanion.insert({
    this.id = const Value.absent(),
    required String accountId,
    required String payload,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.notBefore = const Value.absent(),
  }) : accountId = Value(accountId),
       payload = Value(payload);
  static Insertable<PendingOpRow> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? payload,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? notBefore,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (payload != null) 'payload': payload,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (notBefore != null) 'not_before': notBefore,
    });
  }

  PendingOpsCompanion copyWith({
    Value<int>? id,
    Value<String>? accountId,
    Value<String>? payload,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int?>? notBefore,
  }) {
    return PendingOpsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      payload: payload ?? this.payload,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      notBefore: notBefore ?? this.notBefore,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (notBefore.present) {
      map['not_before'] = Variable<int>(notBefore.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingOpsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('payload: $payload, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('notBefore: $notBefore')
          ..write(')'))
        .toString();
  }
}

class Outbox extends Table with TableInfo<Outbox, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Outbox(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES accounts(id)ON DELETE CASCADE',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sendAtMeta = const VerificationMeta('sendAt');
  late final GeneratedColumn<int> sendAt = GeneratedColumn<int>(
    'send_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    payload,
    sendAt,
    state,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('send_at')) {
      context.handle(
        _sendAtMeta,
        sendAt.isAcceptableOrUnknown(data['send_at']!, _sendAtMeta),
      );
    } else if (isInserting) {
      context.missing(_sendAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      sendAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}send_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  Outbox createAlias(String alias) {
    return Outbox(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int id;
  final String accountId;
  final String payload;
  final int sendAt;
  final String state;
  final int attempts;
  final String? lastError;
  const OutboxRow({
    required this.id,
    required this.accountId,
    required this.payload,
    required this.sendAt,
    required this.state,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<String>(accountId);
    map['payload'] = Variable<String>(payload);
    map['send_at'] = Variable<int>(sendAt);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      accountId: Value(accountId),
      payload: Value(payload),
      sendAt: Value(sendAt),
      state: Value(state),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<String>(json['account_id']),
      payload: serializer.fromJson<String>(json['payload']),
      sendAt: serializer.fromJson<int>(json['send_at']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['last_error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'account_id': serializer.toJson<String>(accountId),
      'payload': serializer.toJson<String>(payload),
      'send_at': serializer.toJson<int>(sendAt),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'last_error': serializer.toJson<String?>(lastError),
    };
  }

  OutboxRow copyWith({
    int? id,
    String? accountId,
    String? payload,
    int? sendAt,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxRow(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    payload: payload ?? this.payload,
    sendAt: sendAt ?? this.sendAt,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxRow copyWithCompanion(OutboxCompanion data) {
    return OutboxRow(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      payload: data.payload.present ? data.payload.value : this.payload,
      sendAt: data.sendAt.present ? data.sendAt.value : this.sendAt,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('payload: $payload, ')
          ..write('sendAt: $sendAt, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, accountId, payload, sendAt, state, attempts, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.payload == this.payload &&
          other.sendAt == this.sendAt &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> id;
  final Value<String> accountId;
  final Value<String> payload;
  final Value<int> sendAt;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.payload = const Value.absent(),
    this.sendAt = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String accountId,
    required String payload,
    required int sendAt,
    required String state,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : accountId = Value(accountId),
       payload = Value(payload),
       sendAt = Value(sendAt),
       state = Value(state);
  static Insertable<OutboxRow> custom({
    Expression<int>? id,
    Expression<String>? accountId,
    Expression<String>? payload,
    Expression<int>? sendAt,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (payload != null) 'payload': payload,
      if (sendAt != null) 'send_at': sendAt,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? accountId,
    Value<String>? payload,
    Value<int>? sendAt,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      payload: payload ?? this.payload,
      sendAt: sendAt ?? this.sendAt,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (sendAt.present) {
      map['send_at'] = Variable<int>(sendAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('payload: $payload, ')
          ..write('sendAt: $sendAt, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class Settings extends Table with TableInfo<Settings, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Settings(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  Settings createAlias(String alias) {
    return Settings(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
  @override
  bool get dontWriteConstraints => true;
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
  });
  SettingsCompanion.insert({required String key, required String value})
    : key = Value(key),
      value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
    });
  }

  SettingsCompanion copyWith({Value<String>? key, Value<String>? value}) {
    return SettingsCompanion(key: key ?? this.key, value: value ?? this.value);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

class MessageFts extends Table
    with
        TableInfo<MessageFts, MessageFt>,
        VirtualTableInfo<MessageFts, MessageFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MessageFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _recipientsMeta = const VerificationMeta(
    'recipients',
  );
  late final GeneratedColumn<String> recipients = GeneratedColumn<String>(
    'recipients',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _snippetMeta = const VerificationMeta(
    'snippet',
  );
  late final GeneratedColumn<String> snippet = GeneratedColumn<String>(
    'snippet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    subject,
    sender,
    recipients,
    snippet,
    body,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('recipients')) {
      context.handle(
        _recipientsMeta,
        recipients.isAcceptableOrUnknown(data['recipients']!, _recipientsMeta),
      );
    } else if (isInserting) {
      context.missing(_recipientsMeta);
    }
    if (data.containsKey('snippet')) {
      context.handle(
        _snippetMeta,
        snippet.isAcceptableOrUnknown(data['snippet']!, _snippetMeta),
      );
    } else if (isInserting) {
      context.missing(_snippetMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  MessageFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageFt(
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      recipients: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipients'],
      )!,
      snippet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snippet'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
    );
  }

  @override
  MessageFts createAlias(String alias) {
    return MessageFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(subject, sender, recipients, snippet, body, content = \'\', contentless_delete = 1, tokenize = \'unicode61 remove_diacritics 2\', prefix = \'2 3\')';
}

class MessageFt extends DataClass implements Insertable<MessageFt> {
  final String subject;
  final String sender;
  final String recipients;
  final String snippet;
  final String body;
  const MessageFt({
    required this.subject,
    required this.sender,
    required this.recipients,
    required this.snippet,
    required this.body,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject'] = Variable<String>(subject);
    map['sender'] = Variable<String>(sender);
    map['recipients'] = Variable<String>(recipients);
    map['snippet'] = Variable<String>(snippet);
    map['body'] = Variable<String>(body);
    return map;
  }

  MessageFtsCompanion toCompanion(bool nullToAbsent) {
    return MessageFtsCompanion(
      subject: Value(subject),
      sender: Value(sender),
      recipients: Value(recipients),
      snippet: Value(snippet),
      body: Value(body),
    );
  }

  factory MessageFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageFt(
      subject: serializer.fromJson<String>(json['subject']),
      sender: serializer.fromJson<String>(json['sender']),
      recipients: serializer.fromJson<String>(json['recipients']),
      snippet: serializer.fromJson<String>(json['snippet']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subject': serializer.toJson<String>(subject),
      'sender': serializer.toJson<String>(sender),
      'recipients': serializer.toJson<String>(recipients),
      'snippet': serializer.toJson<String>(snippet),
      'body': serializer.toJson<String>(body),
    };
  }

  MessageFt copyWith({
    String? subject,
    String? sender,
    String? recipients,
    String? snippet,
    String? body,
  }) => MessageFt(
    subject: subject ?? this.subject,
    sender: sender ?? this.sender,
    recipients: recipients ?? this.recipients,
    snippet: snippet ?? this.snippet,
    body: body ?? this.body,
  );
  MessageFt copyWithCompanion(MessageFtsCompanion data) {
    return MessageFt(
      subject: data.subject.present ? data.subject.value : this.subject,
      sender: data.sender.present ? data.sender.value : this.sender,
      recipients: data.recipients.present
          ? data.recipients.value
          : this.recipients,
      snippet: data.snippet.present ? data.snippet.value : this.snippet,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageFt(')
          ..write('subject: $subject, ')
          ..write('sender: $sender, ')
          ..write('recipients: $recipients, ')
          ..write('snippet: $snippet, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(subject, sender, recipients, snippet, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageFt &&
          other.subject == this.subject &&
          other.sender == this.sender &&
          other.recipients == this.recipients &&
          other.snippet == this.snippet &&
          other.body == this.body);
}

class MessageFtsCompanion extends UpdateCompanion<MessageFt> {
  final Value<String> subject;
  final Value<String> sender;
  final Value<String> recipients;
  final Value<String> snippet;
  final Value<String> body;
  final Value<int> rowid;
  const MessageFtsCompanion({
    this.subject = const Value.absent(),
    this.sender = const Value.absent(),
    this.recipients = const Value.absent(),
    this.snippet = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageFtsCompanion.insert({
    required String subject,
    required String sender,
    required String recipients,
    required String snippet,
    required String body,
    this.rowid = const Value.absent(),
  }) : subject = Value(subject),
       sender = Value(sender),
       recipients = Value(recipients),
       snippet = Value(snippet),
       body = Value(body);
  static Insertable<MessageFt> custom({
    Expression<String>? subject,
    Expression<String>? sender,
    Expression<String>? recipients,
    Expression<String>? snippet,
    Expression<String>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subject != null) 'subject': subject,
      if (sender != null) 'sender': sender,
      if (recipients != null) 'recipients': recipients,
      if (snippet != null) 'snippet': snippet,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageFtsCompanion copyWith({
    Value<String>? subject,
    Value<String>? sender,
    Value<String>? recipients,
    Value<String>? snippet,
    Value<String>? body,
    Value<int>? rowid,
  }) {
    return MessageFtsCompanion(
      subject: subject ?? this.subject,
      sender: sender ?? this.sender,
      recipients: recipients ?? this.recipients,
      snippet: snippet ?? this.snippet,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (recipients.present) {
      map['recipients'] = Variable<String>(recipients.value);
    }
    if (snippet.present) {
      map['snippet'] = Variable<String>(snippet.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageFtsCompanion(')
          ..write('subject: $subject, ')
          ..write('sender: $sender, ')
          ..write('recipients: $recipients, ')
          ..write('snippet: $snippet, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$PlumeDatabase extends GeneratedDatabase {
  _$PlumeDatabase(QueryExecutor e) : super(e);
  $PlumeDatabaseManager get managers => $PlumeDatabaseManager(this);
  late final Accounts accounts = Accounts(this);
  late final Mailboxes mailboxes = Mailboxes(this);
  late final Messages messages = Messages(this);
  late final Index messagesByThread = Index(
    'messages_by_thread',
    'CREATE INDEX messages_by_thread ON messages (account_id, thread_id, date)',
  );
  late final MessageMailboxes messageMailboxes = MessageMailboxes(this);
  late final Index messageMailboxesByMailbox = Index(
    'message_mailboxes_by_mailbox',
    'CREATE INDEX message_mailboxes_by_mailbox ON message_mailboxes (account_id, mailbox_id)',
  );
  late final Threads threads = Threads(this);
  late final Index threadsActive = Index(
    'threads_active',
    'CREATE INDEX threads_active ON threads (account_id, last_date DESC, id) WHERE active_count > 0',
  );
  late final Index threadsFlagged = Index(
    'threads_flagged',
    'CREATE INDEX threads_flagged ON threads (account_id, last_date DESC, id) WHERE flagged = 1 AND active_count > 0',
  );
  late final ThreadMailboxes threadMailboxes = ThreadMailboxes(this);
  late final Index threadMailboxesList = Index(
    'thread_mailboxes_list',
    'CREATE INDEX thread_mailboxes_list ON thread_mailboxes (account_id, mailbox_id, last_date DESC, thread_id)',
  );
  late final Index threadMailboxesUnread = Index(
    'thread_mailboxes_unread',
    'CREATE INDEX thread_mailboxes_unread ON thread_mailboxes (account_id, mailbox_id) WHERE unread = 1',
  );
  late final Bodies bodies = Bodies(this);
  late final BodyParts bodyParts = BodyParts(this);
  late final Contacts contacts = Contacts(this);
  late final Index contactsRank = Index(
    'contacts_rank',
    'CREATE INDEX contacts_rank ON contacts (use_count DESC, last_used DESC)',
  );
  late final SyncState syncState = SyncState(this);
  late final PendingOps pendingOps = PendingOps(this);
  late final Index pendingOpsByAccount = Index(
    'pending_ops_by_account',
    'CREATE INDEX pending_ops_by_account ON pending_ops (account_id, id)',
  );
  late final Outbox outbox = Outbox(this);
  late final Index outboxByAccount = Index(
    'outbox_by_account',
    'CREATE INDEX outbox_by_account ON outbox (account_id)',
  );
  late final Settings settings = Settings(this);
  late final MessageFts messageFts = MessageFts(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    mailboxes,
    messages,
    messagesByThread,
    messageMailboxes,
    messageMailboxesByMailbox,
    threads,
    threadsActive,
    threadsFlagged,
    threadMailboxes,
    threadMailboxesList,
    threadMailboxesUnread,
    bodies,
    bodyParts,
    contacts,
    contactsRank,
    syncState,
    pendingOps,
    pendingOpsByAccount,
    outbox,
    outboxByAccount,
    settings,
    messageFts,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('mailboxes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_mailboxes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('threads', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'threads',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('thread_mailboxes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bodies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'bodies',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('body_parts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('sync_state', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('pending_ops', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outbox', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $AccountsCreateCompanionBuilder = AccountsCompanion Function({
  required String id,
  required String provider,
  required String email,
  required String displayName,
  Value<String?> avatarUrl,
  required int color,
  Value<int> sortOrder,
  Value<String> status,
  Value<String?> signature,
  Value<String?> providerConfig,
  Value<int> rowid,
});
typedef $AccountsUpdateCompanionBuilder = AccountsCompanion Function({
  Value<String> id,
  Value<String> provider,
  Value<String> email,
  Value<String> displayName,
  Value<String?> avatarUrl,
  Value<int> color,
  Value<int> sortOrder,
  Value<String> status,
  Value<String?> signature,
  Value<String?> providerConfig,
  Value<int> rowid,
});

final class $AccountsReferences
    extends BaseReferences<_$PlumeDatabase, Accounts, AccountRow> {
  $AccountsReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<Mailboxes, List<MailboxRow>> _mailboxesRefsTable(
    _$PlumeDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.mailboxes,
    aliasName: 'accounts__id__mailboxes__account_id',
  );

  $MailboxesProcessedTableManager get mailboxesRefs {
    final manager = $MailboxesTableManager(
      $_db,
      $_db.mailboxes,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mailboxesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<Messages, List<MessageRow>> _messagesRefsTable(
    _$PlumeDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'accounts__id__messages__account_id',
  );

  $MessagesProcessedTableManager get messagesRefs {
    final manager = $MessagesTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<Threads, List<ThreadRow>> _threadsRefsTable(
    _$PlumeDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.threads,
    aliasName: 'accounts__id__threads__account_id',
  );

  $ThreadsProcessedTableManager get threadsRefs {
    final manager = $ThreadsTableManager(
      $_db,
      $_db.threads,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_threadsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<SyncState, List<SyncStateRow>> _syncStateRefsTable(
    _$PlumeDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.syncState,
    aliasName: 'accounts__id__sync_state__account_id',
  );

  $SyncStateProcessedTableManager get syncStateRefs {
    final manager = $SyncStateTableManager(
      $_db,
      $_db.syncState,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_syncStateRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<PendingOps, List<PendingOpRow>>
  _pendingOpsRefsTable(_$PlumeDatabase db) => MultiTypedResultKey.fromTable(
    db.pendingOps,
    aliasName: 'accounts__id__pending_ops__account_id',
  );

  $PendingOpsProcessedTableManager get pendingOpsRefs {
    final manager = $PendingOpsTableManager(
      $_db,
      $_db.pendingOps,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_pendingOpsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<Outbox, List<OutboxRow>> _outboxRefsTable(
    _$PlumeDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.outbox,
    aliasName: 'accounts__id__outbox__account_id',
  );

  $OutboxProcessedTableManager get outboxRefs {
    final manager = $OutboxTableManager(
      $_db,
      $_db.outbox,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_outboxRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $AccountsFilterComposer extends Composer<_$PlumeDatabase, Accounts> {
  $AccountsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerConfig => $composableBuilder(
    column: $table.providerConfig,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mailboxesRefs(
    Expression<bool> Function($MailboxesFilterComposer f) f,
  ) {
    final $MailboxesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mailboxes,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MailboxesFilterComposer(
            $db: $db,
            $table: $db.mailboxes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> messagesRefs(
    Expression<bool> Function($MessagesFilterComposer f) f,
  ) {
    final $MessagesFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MessagesFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> threadsRefs(
    Expression<bool> Function($ThreadsFilterComposer f) f,
  ) {
    final $ThreadsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ThreadsFilterComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> syncStateRefs(
    Expression<bool> Function($SyncStateFilterComposer f) f,
  ) {
    final $SyncStateFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncState,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SyncStateFilterComposer(
            $db: $db,
            $table: $db.syncState,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pendingOpsRefs(
    Expression<bool> Function($PendingOpsFilterComposer f) f,
  ) {
    final $PendingOpsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pendingOps,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PendingOpsFilterComposer(
            $db: $db,
            $table: $db.pendingOps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outboxRefs(
    Expression<bool> Function($OutboxFilterComposer f) f,
  ) {
    final $OutboxFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outbox,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $OutboxFilterComposer(
            $db: $db,
            $table: $db.outbox,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $AccountsOrderingComposer extends Composer<_$PlumeDatabase, Accounts> {
  $AccountsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerConfig => $composableBuilder(
    column: $table.providerConfig,
    builder: (column) => ColumnOrderings(column),
  );
}

class $AccountsAnnotationComposer extends Composer<_$PlumeDatabase, Accounts> {
  $AccountsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<String> get providerConfig => $composableBuilder(
    column: $table.providerConfig,
    builder: (column) => column,
  );

  Expression<T> mailboxesRefs<T extends Object>(
    Expression<T> Function($MailboxesAnnotationComposer a) f,
  ) {
    final $MailboxesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mailboxes,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MailboxesAnnotationComposer(
            $db: $db,
            $table: $db.mailboxes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($MessagesAnnotationComposer a) f,
  ) {
    final $MessagesAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $MessagesAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> threadsRefs<T extends Object>(
    Expression<T> Function($ThreadsAnnotationComposer a) f,
  ) {
    final $ThreadsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.threads,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $ThreadsAnnotationComposer(
            $db: $db,
            $table: $db.threads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> syncStateRefs<T extends Object>(
    Expression<T> Function($SyncStateAnnotationComposer a) f,
  ) {
    final $SyncStateAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncState,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $SyncStateAnnotationComposer(
            $db: $db,
            $table: $db.syncState,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pendingOpsRefs<T extends Object>(
    Expression<T> Function($PendingOpsAnnotationComposer a) f,
  ) {
    final $PendingOpsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pendingOps,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $PendingOpsAnnotationComposer(
            $db: $db,
            $table: $db.pendingOps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> outboxRefs<T extends Object>(
    Expression<T> Function($OutboxAnnotationComposer a) f,
  ) {
    final $OutboxAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outbox,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $OutboxAnnotationComposer(
            $db: $db,
            $table: $db.outbox,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $AccountsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Accounts,
          AccountRow,
          $AccountsFilterComposer,
          $AccountsOrderingComposer,
          $AccountsAnnotationComposer,
          $AccountsCreateCompanionBuilder,
          $AccountsUpdateCompanionBuilder,
          (AccountRow, $AccountsReferences),
          AccountRow,
          PrefetchHooks Function({
            bool mailboxesRefs,
            bool messagesRefs,
            bool threadsRefs,
            bool syncStateRefs,
            bool pendingOpsRefs,
            bool outboxRefs,
          })
        > {
  $AccountsTableManager(_$PlumeDatabase db, Accounts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $AccountsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $AccountsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $AccountsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> signature = const Value.absent(),
                Value<String?> providerConfig = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                provider: provider,
                email: email,
                displayName: displayName,
                avatarUrl: avatarUrl,
                color: color,
                sortOrder: sortOrder,
                status: status,
                signature: signature,
                providerConfig: providerConfig,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String provider,
                required String email,
                required String displayName,
                Value<String?> avatarUrl = const Value.absent(),
                required int color,
                Value<int> sortOrder = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> signature = const Value.absent(),
                Value<String?> providerConfig = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                provider: provider,
                email: email,
                displayName: displayName,
                avatarUrl: avatarUrl,
                color: color,
                sortOrder: sortOrder,
                status: status,
                signature: signature,
                providerConfig: providerConfig,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Accounts, AccountRow>(table),
                  $AccountsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                mailboxesRefs = false,
                messagesRefs = false,
                threadsRefs = false,
                syncStateRefs = false,
                pendingOpsRefs = false,
                outboxRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mailboxesRefs) db.mailboxes,
                    if (messagesRefs) db.messages,
                    if (threadsRefs) db.threads,
                    if (syncStateRefs) db.syncState,
                    if (pendingOpsRefs) db.pendingOps,
                    if (outboxRefs) db.outbox,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mailboxesRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          Accounts,
                          MailboxRow,
                          Mailboxes
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._mailboxesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).mailboxesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (messagesRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          Accounts,
                          MessageRow,
                          Messages
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).messagesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (threadsRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          Accounts,
                          ThreadRow,
                          Threads
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._threadsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).threadsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (syncStateRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          Accounts,
                          SyncStateRow,
                          SyncState
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._syncStateRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).syncStateRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (pendingOpsRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          Accounts,
                          PendingOpRow,
                          PendingOps
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences
                              ._pendingOpsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).pendingOpsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                      if (outboxRefs)
                        await $_getPrefetchedDataByColumns<
                          AccountRow,
                          Accounts,
                          OutboxRow,
                          Outbox
                        >(
                          currentTable: table,
                          referencedTable: $AccountsReferences._outboxRefsTable(
                            db,
                          ),
                          managerFromTypedResult: (p0) =>
                              $AccountsReferences(db, table, p0).outboxRefs,
                          currentColumn: 'id',
                          referencedColumn: 'account_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $AccountsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Accounts,
      AccountRow,
      $AccountsFilterComposer,
      $AccountsOrderingComposer,
      $AccountsAnnotationComposer,
      $AccountsCreateCompanionBuilder,
      $AccountsUpdateCompanionBuilder,
      (AccountRow, $AccountsReferences),
      AccountRow,
      PrefetchHooks Function({
        bool mailboxesRefs,
        bool messagesRefs,
        bool threadsRefs,
        bool syncStateRefs,
        bool pendingOpsRefs,
        bool outboxRefs,
      })
    >;
typedef $MailboxesCreateCompanionBuilder = MailboxesCompanion Function({
  required String accountId,
  required String id,
  required String name,
  Value<String?> role,
  Value<String?> category,
  Value<String> kind,
  Value<String?> parentId,
  Value<int?> color,
  Value<int> unreadThreads,
  Value<int> totalThreads,
  Value<int> sortOrder,
  Value<bool> hidden,
});
typedef $MailboxesUpdateCompanionBuilder = MailboxesCompanion Function({
  Value<String> accountId,
  Value<String> id,
  Value<String> name,
  Value<String?> role,
  Value<String?> category,
  Value<String> kind,
  Value<String?> parentId,
  Value<int?> color,
  Value<int> unreadThreads,
  Value<int> totalThreads,
  Value<int> sortOrder,
  Value<bool> hidden,
});

final class $MailboxesReferences
    extends BaseReferences<_$PlumeDatabase, Mailboxes, MailboxRow> {
  $MailboxesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$PlumeDatabase db) =>
      db.accounts.createAlias('mailboxes__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MailboxesFilterComposer extends Composer<_$PlumeDatabase, Mailboxes> {
  $MailboxesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadThreads => $composableBuilder(
    column: $table.unreadThreads,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalThreads => $composableBuilder(
    column: $table.totalThreads,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MailboxesOrderingComposer extends Composer<_$PlumeDatabase, Mailboxes> {
  $MailboxesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadThreads => $composableBuilder(
    column: $table.unreadThreads,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalThreads => $composableBuilder(
    column: $table.totalThreads,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MailboxesAnnotationComposer
    extends Composer<_$PlumeDatabase, Mailboxes> {
  $MailboxesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get unreadThreads => $composableBuilder(
    column: $table.unreadThreads,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalThreads => $composableBuilder(
    column: $table.totalThreads,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MailboxesTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Mailboxes,
          MailboxRow,
          $MailboxesFilterComposer,
          $MailboxesOrderingComposer,
          $MailboxesAnnotationComposer,
          $MailboxesCreateCompanionBuilder,
          $MailboxesUpdateCompanionBuilder,
          (MailboxRow, $MailboxesReferences),
          MailboxRow,
          PrefetchHooks Function({bool accountId})
        > {
  $MailboxesTableManager(_$PlumeDatabase db, Mailboxes table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MailboxesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MailboxesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MailboxesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> role = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<int> unreadThreads = const Value.absent(),
                Value<int> totalThreads = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
              }) => MailboxesCompanion(
                accountId: accountId,
                id: id,
                name: name,
                role: role,
                category: category,
                kind: kind,
                parentId: parentId,
                color: color,
                unreadThreads: unreadThreads,
                totalThreads: totalThreads,
                sortOrder: sortOrder,
                hidden: hidden,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                required String name,
                Value<String?> role = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<int> unreadThreads = const Value.absent(),
                Value<int> totalThreads = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
              }) => MailboxesCompanion.insert(
                accountId: accountId,
                id: id,
                name: name,
                role: role,
                category: category,
                kind: kind,
                parentId: parentId,
                color: color,
                unreadThreads: unreadThreads,
                totalThreads: totalThreads,
                sortOrder: sortOrder,
                hidden: hidden,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Mailboxes, MailboxRow>(table),
                  $MailboxesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $MailboxesReferences._accountIdTable(
                          db,
                        ),
                        referencedColumn: $MailboxesReferences
                            ._accountIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $MailboxesProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Mailboxes,
      MailboxRow,
      $MailboxesFilterComposer,
      $MailboxesOrderingComposer,
      $MailboxesAnnotationComposer,
      $MailboxesCreateCompanionBuilder,
      $MailboxesUpdateCompanionBuilder,
      (MailboxRow, $MailboxesReferences),
      MailboxRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $MessagesCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> rowId,
  required String accountId,
  required String id,
  required String threadId,
  Value<String> subject,
  Value<String?> fromAddr,
  Value<String?> toAddrs,
  Value<String?> ccAddrs,
  Value<String?> bccAddrs,
  Value<String?> replyToAddrs,
  required int date,
  Value<String> snippet,
  Value<bool> isRead,
  Value<bool> isFlagged,
  Value<bool> isDraft,
  Value<bool> hasAttachments,
  Value<String?> attachments,
  Value<String?> messageIdHeader,
  Value<String?> inReplyTo,
  Value<String?> refs,
  Value<String?> listUnsubscribe,
  Value<int> size,
});
typedef $MessagesUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> rowId,
  Value<String> accountId,
  Value<String> id,
  Value<String> threadId,
  Value<String> subject,
  Value<String?> fromAddr,
  Value<String?> toAddrs,
  Value<String?> ccAddrs,
  Value<String?> bccAddrs,
  Value<String?> replyToAddrs,
  Value<int> date,
  Value<String> snippet,
  Value<bool> isRead,
  Value<bool> isFlagged,
  Value<bool> isDraft,
  Value<bool> hasAttachments,
  Value<String?> attachments,
  Value<String?> messageIdHeader,
  Value<String?> inReplyTo,
  Value<String?> refs,
  Value<String?> listUnsubscribe,
  Value<int> size,
});

final class $MessagesReferences
    extends BaseReferences<_$PlumeDatabase, Messages, MessageRow> {
  $MessagesReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$PlumeDatabase db) =>
      db.accounts.createAlias('messages__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $MessagesFilterComposer extends Composer<_$PlumeDatabase, Messages> {
  $MessagesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromAddr => $composableBuilder(
    column: $table.fromAddr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toAddrs => $composableBuilder(
    column: $table.toAddrs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ccAddrs => $composableBuilder(
    column: $table.ccAddrs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bccAddrs => $composableBuilder(
    column: $table.bccAddrs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToAddrs => $composableBuilder(
    column: $table.replyToAddrs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFlagged => $composableBuilder(
    column: $table.isFlagged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDraft => $composableBuilder(
    column: $table.isDraft,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachments => $composableBuilder(
    column: $table.attachments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageIdHeader => $composableBuilder(
    column: $table.messageIdHeader,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inReplyTo => $composableBuilder(
    column: $table.inReplyTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refs => $composableBuilder(
    column: $table.refs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listUnsubscribe => $composableBuilder(
    column: $table.listUnsubscribe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MessagesOrderingComposer extends Composer<_$PlumeDatabase, Messages> {
  $MessagesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromAddr => $composableBuilder(
    column: $table.fromAddr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toAddrs => $composableBuilder(
    column: $table.toAddrs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ccAddrs => $composableBuilder(
    column: $table.ccAddrs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bccAddrs => $composableBuilder(
    column: $table.bccAddrs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToAddrs => $composableBuilder(
    column: $table.replyToAddrs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFlagged => $composableBuilder(
    column: $table.isFlagged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDraft => $composableBuilder(
    column: $table.isDraft,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachments => $composableBuilder(
    column: $table.attachments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageIdHeader => $composableBuilder(
    column: $table.messageIdHeader,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inReplyTo => $composableBuilder(
    column: $table.inReplyTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refs => $composableBuilder(
    column: $table.refs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listUnsubscribe => $composableBuilder(
    column: $table.listUnsubscribe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MessagesAnnotationComposer extends Composer<_$PlumeDatabase, Messages> {
  $MessagesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get fromAddr =>
      $composableBuilder(column: $table.fromAddr, builder: (column) => column);

  GeneratedColumn<String> get toAddrs =>
      $composableBuilder(column: $table.toAddrs, builder: (column) => column);

  GeneratedColumn<String> get ccAddrs =>
      $composableBuilder(column: $table.ccAddrs, builder: (column) => column);

  GeneratedColumn<String> get bccAddrs =>
      $composableBuilder(column: $table.bccAddrs, builder: (column) => column);

  GeneratedColumn<String> get replyToAddrs => $composableBuilder(
    column: $table.replyToAddrs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get snippet =>
      $composableBuilder(column: $table.snippet, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<bool> get isFlagged =>
      $composableBuilder(column: $table.isFlagged, builder: (column) => column);

  GeneratedColumn<bool> get isDraft =>
      $composableBuilder(column: $table.isDraft, builder: (column) => column);

  GeneratedColumn<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachments => $composableBuilder(
    column: $table.attachments,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageIdHeader => $composableBuilder(
    column: $table.messageIdHeader,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inReplyTo =>
      $composableBuilder(column: $table.inReplyTo, builder: (column) => column);

  GeneratedColumn<String> get refs =>
      $composableBuilder(column: $table.refs, builder: (column) => column);

  GeneratedColumn<String> get listUnsubscribe => $composableBuilder(
    column: $table.listUnsubscribe,
    builder: (column) => column,
  );

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $MessagesTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Messages,
          MessageRow,
          $MessagesFilterComposer,
          $MessagesOrderingComposer,
          $MessagesAnnotationComposer,
          $MessagesCreateCompanionBuilder,
          $MessagesUpdateCompanionBuilder,
          (MessageRow, $MessagesReferences),
          MessageRow,
          PrefetchHooks Function({bool accountId})
        > {
  $MessagesTableManager(_$PlumeDatabase db, Messages table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessagesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessagesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessagesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String?> fromAddr = const Value.absent(),
                Value<String?> toAddrs = const Value.absent(),
                Value<String?> ccAddrs = const Value.absent(),
                Value<String?> bccAddrs = const Value.absent(),
                Value<String?> replyToAddrs = const Value.absent(),
                Value<int> date = const Value.absent(),
                Value<String> snippet = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<bool> isFlagged = const Value.absent(),
                Value<bool> isDraft = const Value.absent(),
                Value<bool> hasAttachments = const Value.absent(),
                Value<String?> attachments = const Value.absent(),
                Value<String?> messageIdHeader = const Value.absent(),
                Value<String?> inReplyTo = const Value.absent(),
                Value<String?> refs = const Value.absent(),
                Value<String?> listUnsubscribe = const Value.absent(),
                Value<int> size = const Value.absent(),
              }) => MessagesCompanion(
                rowId: rowId,
                accountId: accountId,
                id: id,
                threadId: threadId,
                subject: subject,
                fromAddr: fromAddr,
                toAddrs: toAddrs,
                ccAddrs: ccAddrs,
                bccAddrs: bccAddrs,
                replyToAddrs: replyToAddrs,
                date: date,
                snippet: snippet,
                isRead: isRead,
                isFlagged: isFlagged,
                isDraft: isDraft,
                hasAttachments: hasAttachments,
                attachments: attachments,
                messageIdHeader: messageIdHeader,
                inReplyTo: inReplyTo,
                refs: refs,
                listUnsubscribe: listUnsubscribe,
                size: size,
              ),
          createCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                required String accountId,
                required String id,
                required String threadId,
                Value<String> subject = const Value.absent(),
                Value<String?> fromAddr = const Value.absent(),
                Value<String?> toAddrs = const Value.absent(),
                Value<String?> ccAddrs = const Value.absent(),
                Value<String?> bccAddrs = const Value.absent(),
                Value<String?> replyToAddrs = const Value.absent(),
                required int date,
                Value<String> snippet = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<bool> isFlagged = const Value.absent(),
                Value<bool> isDraft = const Value.absent(),
                Value<bool> hasAttachments = const Value.absent(),
                Value<String?> attachments = const Value.absent(),
                Value<String?> messageIdHeader = const Value.absent(),
                Value<String?> inReplyTo = const Value.absent(),
                Value<String?> refs = const Value.absent(),
                Value<String?> listUnsubscribe = const Value.absent(),
                Value<int> size = const Value.absent(),
              }) => MessagesCompanion.insert(
                rowId: rowId,
                accountId: accountId,
                id: id,
                threadId: threadId,
                subject: subject,
                fromAddr: fromAddr,
                toAddrs: toAddrs,
                ccAddrs: ccAddrs,
                bccAddrs: bccAddrs,
                replyToAddrs: replyToAddrs,
                date: date,
                snippet: snippet,
                isRead: isRead,
                isFlagged: isFlagged,
                isDraft: isDraft,
                hasAttachments: hasAttachments,
                attachments: attachments,
                messageIdHeader: messageIdHeader,
                inReplyTo: inReplyTo,
                refs: refs,
                listUnsubscribe: listUnsubscribe,
                size: size,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Messages, MessageRow>(table),
                  $MessagesReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $MessagesReferences._accountIdTable(
                          db,
                        ),
                        referencedColumn: $MessagesReferences
                            ._accountIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $MessagesProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Messages,
      MessageRow,
      $MessagesFilterComposer,
      $MessagesOrderingComposer,
      $MessagesAnnotationComposer,
      $MessagesCreateCompanionBuilder,
      $MessagesUpdateCompanionBuilder,
      (MessageRow, $MessagesReferences),
      MessageRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $MessageMailboxesCreateCompanionBuilder =
    MessageMailboxesCompanion Function({
      required String accountId,
      required String messageId,
      required String mailboxId,
    });
typedef $MessageMailboxesUpdateCompanionBuilder =
    MessageMailboxesCompanion Function({
      Value<String> accountId,
      Value<String> messageId,
      Value<String> mailboxId,
    });

class $MessageMailboxesFilterComposer
    extends Composer<_$PlumeDatabase, MessageMailboxes> {
  $MessageMailboxesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mailboxId => $composableBuilder(
    column: $table.mailboxId,
    builder: (column) => ColumnFilters(column),
  );
}

class $MessageMailboxesOrderingComposer
    extends Composer<_$PlumeDatabase, MessageMailboxes> {
  $MessageMailboxesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mailboxId => $composableBuilder(
    column: $table.mailboxId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MessageMailboxesAnnotationComposer
    extends Composer<_$PlumeDatabase, MessageMailboxes> {
  $MessageMailboxesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get mailboxId =>
      $composableBuilder(column: $table.mailboxId, builder: (column) => column);
}

class $MessageMailboxesTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          MessageMailboxes,
          MessageMailboxRow,
          $MessageMailboxesFilterComposer,
          $MessageMailboxesOrderingComposer,
          $MessageMailboxesAnnotationComposer,
          $MessageMailboxesCreateCompanionBuilder,
          $MessageMailboxesUpdateCompanionBuilder,
          (
            MessageMailboxRow,
            BaseReferences<
              _$PlumeDatabase,
              MessageMailboxes,
              MessageMailboxRow
            >,
          ),
          MessageMailboxRow,
          PrefetchHooks Function()
        > {
  $MessageMailboxesTableManager(_$PlumeDatabase db, MessageMailboxes table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessageMailboxesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessageMailboxesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessageMailboxesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> mailboxId = const Value.absent(),
              }) => MessageMailboxesCompanion(
                accountId: accountId,
                messageId: messageId,
                mailboxId: mailboxId,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String messageId,
                required String mailboxId,
              }) => MessageMailboxesCompanion.insert(
                accountId: accountId,
                messageId: messageId,
                mailboxId: mailboxId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MessageMailboxes, MessageMailboxRow>(table),
                  BaseReferences<
                    _$PlumeDatabase,
                    MessageMailboxes,
                    MessageMailboxRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MessageMailboxesProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      MessageMailboxes,
      MessageMailboxRow,
      $MessageMailboxesFilterComposer,
      $MessageMailboxesOrderingComposer,
      $MessageMailboxesAnnotationComposer,
      $MessageMailboxesCreateCompanionBuilder,
      $MessageMailboxesUpdateCompanionBuilder,
      (
        MessageMailboxRow,
        BaseReferences<_$PlumeDatabase, MessageMailboxes, MessageMailboxRow>,
      ),
      MessageMailboxRow,
      PrefetchHooks Function()
    >;
typedef $ThreadsCreateCompanionBuilder = ThreadsCompanion Function({
  required String accountId,
  required String id,
  required String subject,
  required String snippet,
  required int lastDate,
  required int messageCount,
  required int unreadCount,
  required bool flagged,
  required bool hasAttachments,
  required int draftCount,
  required int activeCount,
  required String participants,
  required String mailboxIds,
});
typedef $ThreadsUpdateCompanionBuilder = ThreadsCompanion Function({
  Value<String> accountId,
  Value<String> id,
  Value<String> subject,
  Value<String> snippet,
  Value<int> lastDate,
  Value<int> messageCount,
  Value<int> unreadCount,
  Value<bool> flagged,
  Value<bool> hasAttachments,
  Value<int> draftCount,
  Value<int> activeCount,
  Value<String> participants,
  Value<String> mailboxIds,
});

final class $ThreadsReferences
    extends BaseReferences<_$PlumeDatabase, Threads, ThreadRow> {
  $ThreadsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$PlumeDatabase db) =>
      db.accounts.createAlias('threads__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $ThreadsFilterComposer extends Composer<_$PlumeDatabase, Threads> {
  $ThreadsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastDate => $composableBuilder(
    column: $table.lastDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get flagged => $composableBuilder(
    column: $table.flagged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get draftCount => $composableBuilder(
    column: $table.draftCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeCount => $composableBuilder(
    column: $table.activeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participants => $composableBuilder(
    column: $table.participants,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mailboxIds => $composableBuilder(
    column: $table.mailboxIds,
    builder: (column) => ColumnFilters(column),
  );

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ThreadsOrderingComposer extends Composer<_$PlumeDatabase, Threads> {
  $ThreadsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastDate => $composableBuilder(
    column: $table.lastDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get flagged => $composableBuilder(
    column: $table.flagged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get draftCount => $composableBuilder(
    column: $table.draftCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeCount => $composableBuilder(
    column: $table.activeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participants => $composableBuilder(
    column: $table.participants,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mailboxIds => $composableBuilder(
    column: $table.mailboxIds,
    builder: (column) => ColumnOrderings(column),
  );

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ThreadsAnnotationComposer extends Composer<_$PlumeDatabase, Threads> {
  $ThreadsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get snippet =>
      $composableBuilder(column: $table.snippet, builder: (column) => column);

  GeneratedColumn<int> get lastDate =>
      $composableBuilder(column: $table.lastDate, builder: (column) => column);

  GeneratedColumn<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get flagged =>
      $composableBuilder(column: $table.flagged, builder: (column) => column);

  GeneratedColumn<bool> get hasAttachments => $composableBuilder(
    column: $table.hasAttachments,
    builder: (column) => column,
  );

  GeneratedColumn<int> get draftCount => $composableBuilder(
    column: $table.draftCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get activeCount => $composableBuilder(
    column: $table.activeCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get participants => $composableBuilder(
    column: $table.participants,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mailboxIds => $composableBuilder(
    column: $table.mailboxIds,
    builder: (column) => column,
  );

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $ThreadsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Threads,
          ThreadRow,
          $ThreadsFilterComposer,
          $ThreadsOrderingComposer,
          $ThreadsAnnotationComposer,
          $ThreadsCreateCompanionBuilder,
          $ThreadsUpdateCompanionBuilder,
          (ThreadRow, $ThreadsReferences),
          ThreadRow,
          PrefetchHooks Function({bool accountId})
        > {
  $ThreadsTableManager(_$PlumeDatabase db, Threads table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ThreadsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ThreadsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ThreadsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> snippet = const Value.absent(),
                Value<int> lastDate = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<bool> flagged = const Value.absent(),
                Value<bool> hasAttachments = const Value.absent(),
                Value<int> draftCount = const Value.absent(),
                Value<int> activeCount = const Value.absent(),
                Value<String> participants = const Value.absent(),
                Value<String> mailboxIds = const Value.absent(),
              }) => ThreadsCompanion(
                accountId: accountId,
                id: id,
                subject: subject,
                snippet: snippet,
                lastDate: lastDate,
                messageCount: messageCount,
                unreadCount: unreadCount,
                flagged: flagged,
                hasAttachments: hasAttachments,
                draftCount: draftCount,
                activeCount: activeCount,
                participants: participants,
                mailboxIds: mailboxIds,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String id,
                required String subject,
                required String snippet,
                required int lastDate,
                required int messageCount,
                required int unreadCount,
                required bool flagged,
                required bool hasAttachments,
                required int draftCount,
                required int activeCount,
                required String participants,
                required String mailboxIds,
              }) => ThreadsCompanion.insert(
                accountId: accountId,
                id: id,
                subject: subject,
                snippet: snippet,
                lastDate: lastDate,
                messageCount: messageCount,
                unreadCount: unreadCount,
                flagged: flagged,
                hasAttachments: hasAttachments,
                draftCount: draftCount,
                activeCount: activeCount,
                participants: participants,
                mailboxIds: mailboxIds,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Threads, ThreadRow>(table),
                  $ThreadsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $ThreadsReferences._accountIdTable(db),
                        referencedColumn: $ThreadsReferences
                            ._accountIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $ThreadsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Threads,
      ThreadRow,
      $ThreadsFilterComposer,
      $ThreadsOrderingComposer,
      $ThreadsAnnotationComposer,
      $ThreadsCreateCompanionBuilder,
      $ThreadsUpdateCompanionBuilder,
      (ThreadRow, $ThreadsReferences),
      ThreadRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $ThreadMailboxesCreateCompanionBuilder =
    ThreadMailboxesCompanion Function({
      required String accountId,
      required String threadId,
      required String mailboxId,
      required int lastDate,
      required bool unread,
    });
typedef $ThreadMailboxesUpdateCompanionBuilder =
    ThreadMailboxesCompanion Function({
      Value<String> accountId,
      Value<String> threadId,
      Value<String> mailboxId,
      Value<int> lastDate,
      Value<bool> unread,
    });

class $ThreadMailboxesFilterComposer
    extends Composer<_$PlumeDatabase, ThreadMailboxes> {
  $ThreadMailboxesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mailboxId => $composableBuilder(
    column: $table.mailboxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastDate => $composableBuilder(
    column: $table.lastDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unread => $composableBuilder(
    column: $table.unread,
    builder: (column) => ColumnFilters(column),
  );
}

class $ThreadMailboxesOrderingComposer
    extends Composer<_$PlumeDatabase, ThreadMailboxes> {
  $ThreadMailboxesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mailboxId => $composableBuilder(
    column: $table.mailboxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastDate => $composableBuilder(
    column: $table.lastDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unread => $composableBuilder(
    column: $table.unread,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ThreadMailboxesAnnotationComposer
    extends Composer<_$PlumeDatabase, ThreadMailboxes> {
  $ThreadMailboxesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get mailboxId =>
      $composableBuilder(column: $table.mailboxId, builder: (column) => column);

  GeneratedColumn<int> get lastDate =>
      $composableBuilder(column: $table.lastDate, builder: (column) => column);

  GeneratedColumn<bool> get unread =>
      $composableBuilder(column: $table.unread, builder: (column) => column);
}

class $ThreadMailboxesTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          ThreadMailboxes,
          ThreadMailboxRow,
          $ThreadMailboxesFilterComposer,
          $ThreadMailboxesOrderingComposer,
          $ThreadMailboxesAnnotationComposer,
          $ThreadMailboxesCreateCompanionBuilder,
          $ThreadMailboxesUpdateCompanionBuilder,
          (
            ThreadMailboxRow,
            BaseReferences<_$PlumeDatabase, ThreadMailboxes, ThreadMailboxRow>,
          ),
          ThreadMailboxRow,
          PrefetchHooks Function()
        > {
  $ThreadMailboxesTableManager(_$PlumeDatabase db, ThreadMailboxes table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ThreadMailboxesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ThreadMailboxesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ThreadMailboxesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> mailboxId = const Value.absent(),
                Value<int> lastDate = const Value.absent(),
                Value<bool> unread = const Value.absent(),
              }) => ThreadMailboxesCompanion(
                accountId: accountId,
                threadId: threadId,
                mailboxId: mailboxId,
                lastDate: lastDate,
                unread: unread,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String threadId,
                required String mailboxId,
                required int lastDate,
                required bool unread,
              }) => ThreadMailboxesCompanion.insert(
                accountId: accountId,
                threadId: threadId,
                mailboxId: mailboxId,
                lastDate: lastDate,
                unread: unread,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<ThreadMailboxes, ThreadMailboxRow>(table),
                  BaseReferences<
                    _$PlumeDatabase,
                    ThreadMailboxes,
                    ThreadMailboxRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ThreadMailboxesProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      ThreadMailboxes,
      ThreadMailboxRow,
      $ThreadMailboxesFilterComposer,
      $ThreadMailboxesOrderingComposer,
      $ThreadMailboxesAnnotationComposer,
      $ThreadMailboxesCreateCompanionBuilder,
      $ThreadMailboxesUpdateCompanionBuilder,
      (
        ThreadMailboxRow,
        BaseReferences<_$PlumeDatabase, ThreadMailboxes, ThreadMailboxRow>,
      ),
      ThreadMailboxRow,
      PrefetchHooks Function()
    >;
typedef $BodiesCreateCompanionBuilder = BodiesCompanion Function({
  required String accountId,
  required String messageId,
  Value<String?> html,
  Value<String?> plain,
  Value<int> rowid,
});
typedef $BodiesUpdateCompanionBuilder = BodiesCompanion Function({
  Value<String> accountId,
  Value<String> messageId,
  Value<String?> html,
  Value<String?> plain,
  Value<int> rowid,
});

class $BodiesFilterComposer extends Composer<_$PlumeDatabase, Bodies> {
  $BodiesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get html => $composableBuilder(
    column: $table.html,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plain => $composableBuilder(
    column: $table.plain,
    builder: (column) => ColumnFilters(column),
  );
}

class $BodiesOrderingComposer extends Composer<_$PlumeDatabase, Bodies> {
  $BodiesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get html => $composableBuilder(
    column: $table.html,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plain => $composableBuilder(
    column: $table.plain,
    builder: (column) => ColumnOrderings(column),
  );
}

class $BodiesAnnotationComposer extends Composer<_$PlumeDatabase, Bodies> {
  $BodiesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get html =>
      $composableBuilder(column: $table.html, builder: (column) => column);

  GeneratedColumn<String> get plain =>
      $composableBuilder(column: $table.plain, builder: (column) => column);
}

class $BodiesTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Bodies,
          BodyRow,
          $BodiesFilterComposer,
          $BodiesOrderingComposer,
          $BodiesAnnotationComposer,
          $BodiesCreateCompanionBuilder,
          $BodiesUpdateCompanionBuilder,
          (BodyRow, BaseReferences<_$PlumeDatabase, Bodies, BodyRow>),
          BodyRow,
          PrefetchHooks Function()
        > {
  $BodiesTableManager(_$PlumeDatabase db, Bodies table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $BodiesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $BodiesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $BodiesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String?> html = const Value.absent(),
                Value<String?> plain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BodiesCompanion(
                accountId: accountId,
                messageId: messageId,
                html: html,
                plain: plain,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String messageId,
                Value<String?> html = const Value.absent(),
                Value<String?> plain = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BodiesCompanion.insert(
                accountId: accountId,
                messageId: messageId,
                html: html,
                plain: plain,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Bodies, BodyRow>(table),
                  BaseReferences<_$PlumeDatabase, Bodies, BodyRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $BodiesProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Bodies,
      BodyRow,
      $BodiesFilterComposer,
      $BodiesOrderingComposer,
      $BodiesAnnotationComposer,
      $BodiesCreateCompanionBuilder,
      $BodiesUpdateCompanionBuilder,
      (BodyRow, BaseReferences<_$PlumeDatabase, Bodies, BodyRow>),
      BodyRow,
      PrefetchHooks Function()
    >;
typedef $BodyPartsCreateCompanionBuilder = BodyPartsCompanion Function({
  required String accountId,
  required String messageId,
  required String contentId,
  required Uint8List data,
  Value<int> rowid,
});
typedef $BodyPartsUpdateCompanionBuilder = BodyPartsCompanion Function({
  Value<String> accountId,
  Value<String> messageId,
  Value<String> contentId,
  Value<Uint8List> data,
  Value<int> rowid,
});

class $BodyPartsFilterComposer extends Composer<_$PlumeDatabase, BodyParts> {
  $BodyPartsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );
}

class $BodyPartsOrderingComposer extends Composer<_$PlumeDatabase, BodyParts> {
  $BodyPartsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );
}

class $BodyPartsAnnotationComposer
    extends Composer<_$PlumeDatabase, BodyParts> {
  $BodyPartsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get contentId =>
      $composableBuilder(column: $table.contentId, builder: (column) => column);

  GeneratedColumn<Uint8List> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);
}

class $BodyPartsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          BodyParts,
          BodyPartRow,
          $BodyPartsFilterComposer,
          $BodyPartsOrderingComposer,
          $BodyPartsAnnotationComposer,
          $BodyPartsCreateCompanionBuilder,
          $BodyPartsUpdateCompanionBuilder,
          (
            BodyPartRow,
            BaseReferences<_$PlumeDatabase, BodyParts, BodyPartRow>,
          ),
          BodyPartRow,
          PrefetchHooks Function()
        > {
  $BodyPartsTableManager(_$PlumeDatabase db, BodyParts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $BodyPartsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $BodyPartsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $BodyPartsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> contentId = const Value.absent(),
                Value<Uint8List> data = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BodyPartsCompanion(
                accountId: accountId,
                messageId: messageId,
                contentId: contentId,
                data: data,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String messageId,
                required String contentId,
                required Uint8List data,
                Value<int> rowid = const Value.absent(),
              }) => BodyPartsCompanion.insert(
                accountId: accountId,
                messageId: messageId,
                contentId: contentId,
                data: data,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<BodyParts, BodyPartRow>(table),
                  BaseReferences<_$PlumeDatabase, BodyParts, BodyPartRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $BodyPartsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      BodyParts,
      BodyPartRow,
      $BodyPartsFilterComposer,
      $BodyPartsOrderingComposer,
      $BodyPartsAnnotationComposer,
      $BodyPartsCreateCompanionBuilder,
      $BodyPartsUpdateCompanionBuilder,
      (BodyPartRow, BaseReferences<_$PlumeDatabase, BodyParts, BodyPartRow>),
      BodyPartRow,
      PrefetchHooks Function()
    >;
typedef $ContactsCreateCompanionBuilder = ContactsCompanion Function({
  required String email,
  Value<String?> name,
  Value<int> useCount,
  Value<int> lastUsed,
});
typedef $ContactsUpdateCompanionBuilder = ContactsCompanion Function({
  Value<String> email,
  Value<String?> name,
  Value<int> useCount,
  Value<int> lastUsed,
});

class $ContactsFilterComposer extends Composer<_$PlumeDatabase, Contacts> {
  $ContactsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUsed => $composableBuilder(
    column: $table.lastUsed,
    builder: (column) => ColumnFilters(column),
  );
}

class $ContactsOrderingComposer extends Composer<_$PlumeDatabase, Contacts> {
  $ContactsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUsed => $composableBuilder(
    column: $table.lastUsed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ContactsAnnotationComposer extends Composer<_$PlumeDatabase, Contacts> {
  $ContactsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => column);

  GeneratedColumn<int> get lastUsed =>
      $composableBuilder(column: $table.lastUsed, builder: (column) => column);
}

class $ContactsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Contacts,
          ContactRow,
          $ContactsFilterComposer,
          $ContactsOrderingComposer,
          $ContactsAnnotationComposer,
          $ContactsCreateCompanionBuilder,
          $ContactsUpdateCompanionBuilder,
          (ContactRow, BaseReferences<_$PlumeDatabase, Contacts, ContactRow>),
          ContactRow,
          PrefetchHooks Function()
        > {
  $ContactsTableManager(_$PlumeDatabase db, Contacts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ContactsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ContactsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ContactsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> email = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> lastUsed = const Value.absent(),
              }) => ContactsCompanion(
                email: email,
                name: name,
                useCount: useCount,
                lastUsed: lastUsed,
              ),
          createCompanionCallback:
              ({
                required String email,
                Value<String?> name = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> lastUsed = const Value.absent(),
              }) => ContactsCompanion.insert(
                email: email,
                name: name,
                useCount: useCount,
                lastUsed: lastUsed,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Contacts, ContactRow>(table),
                  BaseReferences<_$PlumeDatabase, Contacts, ContactRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ContactsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Contacts,
      ContactRow,
      $ContactsFilterComposer,
      $ContactsOrderingComposer,
      $ContactsAnnotationComposer,
      $ContactsCreateCompanionBuilder,
      $ContactsUpdateCompanionBuilder,
      (ContactRow, BaseReferences<_$PlumeDatabase, Contacts, ContactRow>),
      ContactRow,
      PrefetchHooks Function()
    >;
typedef $SyncStateCreateCompanionBuilder = SyncStateCompanion Function({
  required String accountId,
  required String key,
  required String value,
});
typedef $SyncStateUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> accountId,
  Value<String> key,
  Value<String> value,
});

final class $SyncStateReferences
    extends BaseReferences<_$PlumeDatabase, SyncState, SyncStateRow> {
  $SyncStateReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$PlumeDatabase db) =>
      db.accounts.createAlias('sync_state__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $SyncStateFilterComposer extends Composer<_$PlumeDatabase, SyncState> {
  $SyncStateFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SyncStateOrderingComposer extends Composer<_$PlumeDatabase, SyncState> {
  $SyncStateOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SyncStateAnnotationComposer
    extends Composer<_$PlumeDatabase, SyncState> {
  $SyncStateAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $SyncStateTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          SyncState,
          SyncStateRow,
          $SyncStateFilterComposer,
          $SyncStateOrderingComposer,
          $SyncStateAnnotationComposer,
          $SyncStateCreateCompanionBuilder,
          $SyncStateUpdateCompanionBuilder,
          (SyncStateRow, $SyncStateReferences),
          SyncStateRow,
          PrefetchHooks Function({bool accountId})
        > {
  $SyncStateTableManager(_$PlumeDatabase db, SyncState table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SyncStateFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SyncStateOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SyncStateAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
              }) => SyncStateCompanion(
                accountId: accountId,
                key: key,
                value: value,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String key,
                required String value,
              }) => SyncStateCompanion.insert(
                accountId: accountId,
                key: key,
                value: value,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<SyncState, SyncStateRow>(table),
                  $SyncStateReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $SyncStateReferences._accountIdTable(
                          db,
                        ),
                        referencedColumn: $SyncStateReferences
                            ._accountIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $SyncStateProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      SyncState,
      SyncStateRow,
      $SyncStateFilterComposer,
      $SyncStateOrderingComposer,
      $SyncStateAnnotationComposer,
      $SyncStateCreateCompanionBuilder,
      $SyncStateUpdateCompanionBuilder,
      (SyncStateRow, $SyncStateReferences),
      SyncStateRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $PendingOpsCreateCompanionBuilder = PendingOpsCompanion Function({
  Value<int> id,
  required String accountId,
  required String payload,
  Value<int> attempts,
  Value<String?> lastError,
  Value<int?> notBefore,
});
typedef $PendingOpsUpdateCompanionBuilder = PendingOpsCompanion Function({
  Value<int> id,
  Value<String> accountId,
  Value<String> payload,
  Value<int> attempts,
  Value<String?> lastError,
  Value<int?> notBefore,
});

final class $PendingOpsReferences
    extends BaseReferences<_$PlumeDatabase, PendingOps, PendingOpRow> {
  $PendingOpsReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$PlumeDatabase db) =>
      db.accounts.createAlias('pending_ops__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $PendingOpsFilterComposer extends Composer<_$PlumeDatabase, PendingOps> {
  $PendingOpsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notBefore => $composableBuilder(
    column: $table.notBefore,
    builder: (column) => ColumnFilters(column),
  );

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PendingOpsOrderingComposer
    extends Composer<_$PlumeDatabase, PendingOps> {
  $PendingOpsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notBefore => $composableBuilder(
    column: $table.notBefore,
    builder: (column) => ColumnOrderings(column),
  );

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PendingOpsAnnotationComposer
    extends Composer<_$PlumeDatabase, PendingOps> {
  $PendingOpsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get notBefore =>
      $composableBuilder(column: $table.notBefore, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $PendingOpsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          PendingOps,
          PendingOpRow,
          $PendingOpsFilterComposer,
          $PendingOpsOrderingComposer,
          $PendingOpsAnnotationComposer,
          $PendingOpsCreateCompanionBuilder,
          $PendingOpsUpdateCompanionBuilder,
          (PendingOpRow, $PendingOpsReferences),
          PendingOpRow,
          PrefetchHooks Function({bool accountId})
        > {
  $PendingOpsTableManager(_$PlumeDatabase db, PendingOps table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PendingOpsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PendingOpsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PendingOpsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> notBefore = const Value.absent(),
              }) => PendingOpsCompanion(
                id: id,
                accountId: accountId,
                payload: payload,
                attempts: attempts,
                lastError: lastError,
                notBefore: notBefore,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountId,
                required String payload,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> notBefore = const Value.absent(),
              }) => PendingOpsCompanion.insert(
                id: id,
                accountId: accountId,
                payload: payload,
                attempts: attempts,
                lastError: lastError,
                notBefore: notBefore,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<PendingOps, PendingOpRow>(table),
                  $PendingOpsReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $PendingOpsReferences._accountIdTable(
                          db,
                        ),
                        referencedColumn: $PendingOpsReferences
                            ._accountIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $PendingOpsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      PendingOps,
      PendingOpRow,
      $PendingOpsFilterComposer,
      $PendingOpsOrderingComposer,
      $PendingOpsAnnotationComposer,
      $PendingOpsCreateCompanionBuilder,
      $PendingOpsUpdateCompanionBuilder,
      (PendingOpRow, $PendingOpsReferences),
      PendingOpRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $OutboxCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  required String accountId,
  required String payload,
  required int sendAt,
  required String state,
  Value<int> attempts,
  Value<String?> lastError,
});
typedef $OutboxUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  Value<String> accountId,
  Value<String> payload,
  Value<int> sendAt,
  Value<String> state,
  Value<int> attempts,
  Value<String?> lastError,
});

final class $OutboxReferences
    extends BaseReferences<_$PlumeDatabase, Outbox, OutboxRow> {
  $OutboxReferences(super.$_db, super.$_table, super.$_typedResult);

  static Accounts _accountIdTable(_$PlumeDatabase db) =>
      db.accounts.createAlias('outbox__account_id__accounts__id');

  $AccountsProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $AccountsTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $OutboxFilterComposer extends Composer<_$PlumeDatabase, Outbox> {
  $OutboxFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sendAt => $composableBuilder(
    column: $table.sendAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  $AccountsFilterComposer get accountId {
    final $AccountsFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $OutboxOrderingComposer extends Composer<_$PlumeDatabase, Outbox> {
  $OutboxOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sendAt => $composableBuilder(
    column: $table.sendAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  $AccountsOrderingComposer get accountId {
    final $AccountsOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $OutboxAnnotationComposer extends Composer<_$PlumeDatabase, Outbox> {
  $OutboxAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get sendAt =>
      $composableBuilder(column: $table.sendAt, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  $AccountsAnnotationComposer get accountId {
    final $AccountsAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $AccountsAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $OutboxTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Outbox,
          OutboxRow,
          $OutboxFilterComposer,
          $OutboxOrderingComposer,
          $OutboxAnnotationComposer,
          $OutboxCreateCompanionBuilder,
          $OutboxUpdateCompanionBuilder,
          (OutboxRow, $OutboxReferences),
          OutboxRow,
          PrefetchHooks Function({bool accountId})
        > {
  $OutboxTableManager(_$PlumeDatabase db, Outbox table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $OutboxFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $OutboxOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $OutboxAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> sendAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion(
                id: id,
                accountId: accountId,
                payload: payload,
                sendAt: sendAt,
                state: state,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String accountId,
                required String payload,
                required int sendAt,
                required String state,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion.insert(
                id: id,
                accountId: accountId,
                payload: payload,
                sendAt: sendAt,
                state: state,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Outbox, OutboxRow>(table),
                  $OutboxReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (accountId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.accountId,
                        referencedTable: $OutboxReferences._accountIdTable(db),
                        referencedColumn: $OutboxReferences
                            ._accountIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $OutboxProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Outbox,
      OutboxRow,
      $OutboxFilterComposer,
      $OutboxOrderingComposer,
      $OutboxAnnotationComposer,
      $OutboxCreateCompanionBuilder,
      $OutboxUpdateCompanionBuilder,
      (OutboxRow, $OutboxReferences),
      OutboxRow,
      PrefetchHooks Function({bool accountId})
    >;
typedef $SettingsCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
});
typedef $SettingsUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
});

class $SettingsFilterComposer extends Composer<_$PlumeDatabase, Settings> {
  $SettingsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $SettingsOrderingComposer extends Composer<_$PlumeDatabase, Settings> {
  $SettingsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $SettingsAnnotationComposer extends Composer<_$PlumeDatabase, Settings> {
  $SettingsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $SettingsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          Settings,
          SettingRow,
          $SettingsFilterComposer,
          $SettingsOrderingComposer,
          $SettingsAnnotationComposer,
          $SettingsCreateCompanionBuilder,
          $SettingsUpdateCompanionBuilder,
          (SettingRow, BaseReferences<_$PlumeDatabase, Settings, SettingRow>),
          SettingRow,
          PrefetchHooks Function()
        > {
  $SettingsTableManager(_$PlumeDatabase db, Settings table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $SettingsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $SettingsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $SettingsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value),
          createCompanionCallback: ({
            required String key,
            required String value,
          }) => SettingsCompanion.insert(key: key, value: value),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<Settings, SettingRow>(table),
                  BaseReferences<_$PlumeDatabase, Settings, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $SettingsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      Settings,
      SettingRow,
      $SettingsFilterComposer,
      $SettingsOrderingComposer,
      $SettingsAnnotationComposer,
      $SettingsCreateCompanionBuilder,
      $SettingsUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$PlumeDatabase, Settings, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $MessageFtsCreateCompanionBuilder = MessageFtsCompanion Function({
  required String subject,
  required String sender,
  required String recipients,
  required String snippet,
  required String body,
  Value<int> rowid,
});
typedef $MessageFtsUpdateCompanionBuilder = MessageFtsCompanion Function({
  Value<String> subject,
  Value<String> sender,
  Value<String> recipients,
  Value<String> snippet,
  Value<String> body,
  Value<int> rowid,
});

class $MessageFtsFilterComposer extends Composer<_$PlumeDatabase, MessageFts> {
  $MessageFtsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipients => $composableBuilder(
    column: $table.recipients,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );
}

class $MessageFtsOrderingComposer
    extends Composer<_$PlumeDatabase, MessageFts> {
  $MessageFtsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipients => $composableBuilder(
    column: $table.recipients,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MessageFtsAnnotationComposer
    extends Composer<_$PlumeDatabase, MessageFts> {
  $MessageFtsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<String> get recipients => $composableBuilder(
    column: $table.recipients,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snippet =>
      $composableBuilder(column: $table.snippet, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $MessageFtsTableManager
    extends
        RootTableManager<
          _$PlumeDatabase,
          MessageFts,
          MessageFt,
          $MessageFtsFilterComposer,
          $MessageFtsOrderingComposer,
          $MessageFtsAnnotationComposer,
          $MessageFtsCreateCompanionBuilder,
          $MessageFtsUpdateCompanionBuilder,
          (MessageFt, BaseReferences<_$PlumeDatabase, MessageFts, MessageFt>),
          MessageFt,
          PrefetchHooks Function()
        > {
  $MessageFtsTableManager(_$PlumeDatabase db, MessageFts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessageFtsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessageFtsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessageFtsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> subject = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<String> recipients = const Value.absent(),
                Value<String> snippet = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageFtsCompanion(
                subject: subject,
                sender: sender,
                recipients: recipients,
                snippet: snippet,
                body: body,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subject,
                required String sender,
                required String recipients,
                required String snippet,
                required String body,
                Value<int> rowid = const Value.absent(),
              }) => MessageFtsCompanion.insert(
                subject: subject,
                sender: sender,
                recipients: recipients,
                snippet: snippet,
                body: body,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<MessageFts, MessageFt>(table),
                  BaseReferences<_$PlumeDatabase, MessageFts, MessageFt>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MessageFtsProcessedTableManager =
    ProcessedTableManager<
      _$PlumeDatabase,
      MessageFts,
      MessageFt,
      $MessageFtsFilterComposer,
      $MessageFtsOrderingComposer,
      $MessageFtsAnnotationComposer,
      $MessageFtsCreateCompanionBuilder,
      $MessageFtsUpdateCompanionBuilder,
      (MessageFt, BaseReferences<_$PlumeDatabase, MessageFts, MessageFt>),
      MessageFt,
      PrefetchHooks Function()
    >;

class $PlumeDatabaseManager {
  final _$PlumeDatabase _db;
  $PlumeDatabaseManager(this._db);
  $AccountsTableManager get accounts =>
      $AccountsTableManager(_db, _db.accounts);
  $MailboxesTableManager get mailboxes =>
      $MailboxesTableManager(_db, _db.mailboxes);
  $MessagesTableManager get messages =>
      $MessagesTableManager(_db, _db.messages);
  $MessageMailboxesTableManager get messageMailboxes =>
      $MessageMailboxesTableManager(_db, _db.messageMailboxes);
  $ThreadsTableManager get threads => $ThreadsTableManager(_db, _db.threads);
  $ThreadMailboxesTableManager get threadMailboxes =>
      $ThreadMailboxesTableManager(_db, _db.threadMailboxes);
  $BodiesTableManager get bodies => $BodiesTableManager(_db, _db.bodies);
  $BodyPartsTableManager get bodyParts =>
      $BodyPartsTableManager(_db, _db.bodyParts);
  $ContactsTableManager get contacts =>
      $ContactsTableManager(_db, _db.contacts);
  $SyncStateTableManager get syncState =>
      $SyncStateTableManager(_db, _db.syncState);
  $PendingOpsTableManager get pendingOps =>
      $PendingOpsTableManager(_db, _db.pendingOps);
  $OutboxTableManager get outbox => $OutboxTableManager(_db, _db.outbox);
  $SettingsTableManager get settings =>
      $SettingsTableManager(_db, _db.settings);
  $MessageFtsTableManager get messageFts =>
      $MessageFtsTableManager(_db, _db.messageFts);
}
