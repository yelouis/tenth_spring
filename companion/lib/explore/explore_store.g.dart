// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'explore_store.dart';

// ignore_for_file: type=lint
class $ExploredAreaTable extends ExploredArea
    with TableInfo<$ExploredAreaTable, ExploredAreaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExploredAreaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _areaKeyMeta = const VerificationMeta(
    'areaKey',
  );
  @override
  late final GeneratedColumn<String> areaKey = GeneratedColumn<String>(
    'area_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _placeIdMeta = const VerificationMeta(
    'placeId',
  );
  @override
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
    'place_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstAtMsMeta = const VerificationMeta(
    'firstAtMs',
  );
  @override
  late final GeneratedColumn<int> firstAtMs = GeneratedColumn<int>(
    'first_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _starterMeta = const VerificationMeta(
    'starter',
  );
  @override
  late final GeneratedColumn<bool> starter = GeneratedColumn<bool>(
    'starter',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starter" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [areaKey, placeId, firstAtMs, starter];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'explored_area';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExploredAreaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('area_key')) {
      context.handle(
        _areaKeyMeta,
        areaKey.isAcceptableOrUnknown(data['area_key']!, _areaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_areaKeyMeta);
    }
    if (data.containsKey('place_id')) {
      context.handle(
        _placeIdMeta,
        placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_placeIdMeta);
    }
    if (data.containsKey('first_at_ms')) {
      context.handle(
        _firstAtMsMeta,
        firstAtMs.isAcceptableOrUnknown(data['first_at_ms']!, _firstAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_firstAtMsMeta);
    }
    if (data.containsKey('starter')) {
      context.handle(
        _starterMeta,
        starter.isAcceptableOrUnknown(data['starter']!, _starterMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {areaKey};
  @override
  ExploredAreaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExploredAreaRow(
      areaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_key'],
      )!,
      placeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_id'],
      )!,
      firstAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_at_ms'],
      )!,
      starter: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starter'],
      )!,
    );
  }

  @override
  $ExploredAreaTable createAlias(String alias) {
    return $ExploredAreaTable(attachedDatabase, alias);
  }
}

class ExploredAreaRow extends DataClass implements Insertable<ExploredAreaRow> {
  final String areaKey;
  final String placeId;
  final int firstAtMs;
  final bool starter;
  const ExploredAreaRow({
    required this.areaKey,
    required this.placeId,
    required this.firstAtMs,
    required this.starter,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['area_key'] = Variable<String>(areaKey);
    map['place_id'] = Variable<String>(placeId);
    map['first_at_ms'] = Variable<int>(firstAtMs);
    map['starter'] = Variable<bool>(starter);
    return map;
  }

  ExploredAreaCompanion toCompanion(bool nullToAbsent) {
    return ExploredAreaCompanion(
      areaKey: Value(areaKey),
      placeId: Value(placeId),
      firstAtMs: Value(firstAtMs),
      starter: Value(starter),
    );
  }

  factory ExploredAreaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExploredAreaRow(
      areaKey: serializer.fromJson<String>(json['areaKey']),
      placeId: serializer.fromJson<String>(json['placeId']),
      firstAtMs: serializer.fromJson<int>(json['firstAtMs']),
      starter: serializer.fromJson<bool>(json['starter']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'areaKey': serializer.toJson<String>(areaKey),
      'placeId': serializer.toJson<String>(placeId),
      'firstAtMs': serializer.toJson<int>(firstAtMs),
      'starter': serializer.toJson<bool>(starter),
    };
  }

  ExploredAreaRow copyWith({
    String? areaKey,
    String? placeId,
    int? firstAtMs,
    bool? starter,
  }) => ExploredAreaRow(
    areaKey: areaKey ?? this.areaKey,
    placeId: placeId ?? this.placeId,
    firstAtMs: firstAtMs ?? this.firstAtMs,
    starter: starter ?? this.starter,
  );
  ExploredAreaRow copyWithCompanion(ExploredAreaCompanion data) {
    return ExploredAreaRow(
      areaKey: data.areaKey.present ? data.areaKey.value : this.areaKey,
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      firstAtMs: data.firstAtMs.present ? data.firstAtMs.value : this.firstAtMs,
      starter: data.starter.present ? data.starter.value : this.starter,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExploredAreaRow(')
          ..write('areaKey: $areaKey, ')
          ..write('placeId: $placeId, ')
          ..write('firstAtMs: $firstAtMs, ')
          ..write('starter: $starter')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(areaKey, placeId, firstAtMs, starter);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExploredAreaRow &&
          other.areaKey == this.areaKey &&
          other.placeId == this.placeId &&
          other.firstAtMs == this.firstAtMs &&
          other.starter == this.starter);
}

class ExploredAreaCompanion extends UpdateCompanion<ExploredAreaRow> {
  final Value<String> areaKey;
  final Value<String> placeId;
  final Value<int> firstAtMs;
  final Value<bool> starter;
  final Value<int> rowid;
  const ExploredAreaCompanion({
    this.areaKey = const Value.absent(),
    this.placeId = const Value.absent(),
    this.firstAtMs = const Value.absent(),
    this.starter = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExploredAreaCompanion.insert({
    required String areaKey,
    required String placeId,
    required int firstAtMs,
    this.starter = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : areaKey = Value(areaKey),
       placeId = Value(placeId),
       firstAtMs = Value(firstAtMs);
  static Insertable<ExploredAreaRow> custom({
    Expression<String>? areaKey,
    Expression<String>? placeId,
    Expression<int>? firstAtMs,
    Expression<bool>? starter,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (areaKey != null) 'area_key': areaKey,
      if (placeId != null) 'place_id': placeId,
      if (firstAtMs != null) 'first_at_ms': firstAtMs,
      if (starter != null) 'starter': starter,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExploredAreaCompanion copyWith({
    Value<String>? areaKey,
    Value<String>? placeId,
    Value<int>? firstAtMs,
    Value<bool>? starter,
    Value<int>? rowid,
  }) {
    return ExploredAreaCompanion(
      areaKey: areaKey ?? this.areaKey,
      placeId: placeId ?? this.placeId,
      firstAtMs: firstAtMs ?? this.firstAtMs,
      starter: starter ?? this.starter,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (areaKey.present) {
      map['area_key'] = Variable<String>(areaKey.value);
    }
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (firstAtMs.present) {
      map['first_at_ms'] = Variable<int>(firstAtMs.value);
    }
    if (starter.present) {
      map['starter'] = Variable<bool>(starter.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExploredAreaCompanion(')
          ..write('areaKey: $areaKey, ')
          ..write('placeId: $placeId, ')
          ..write('firstAtMs: $firstAtMs, ')
          ..write('starter: $starter, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExploreOutboxTable extends ExploreOutbox
    with TableInfo<$ExploreOutboxTable, ExploreOutboxItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExploreOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _placeIdMeta = const VerificationMeta(
    'placeId',
  );
  @override
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
    'place_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaKeyMeta = const VerificationMeta(
    'areaKey',
  );
  @override
  late final GeneratedColumn<String> areaKey = GeneratedColumn<String>(
    'area_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tsUtcMsMeta = const VerificationMeta(
    'tsUtcMs',
  );
  @override
  late final GeneratedColumn<int> tsUtcMs = GeneratedColumn<int>(
    'ts_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [seq, kind, placeId, areaKey, tsUtcMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'explore_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExploreOutboxItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('place_id')) {
      context.handle(
        _placeIdMeta,
        placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_placeIdMeta);
    }
    if (data.containsKey('area_key')) {
      context.handle(
        _areaKeyMeta,
        areaKey.isAcceptableOrUnknown(data['area_key']!, _areaKeyMeta),
      );
    }
    if (data.containsKey('ts_utc_ms')) {
      context.handle(
        _tsUtcMsMeta,
        tsUtcMs.isAcceptableOrUnknown(data['ts_utc_ms']!, _tsUtcMsMeta),
      );
    } else if (isInserting) {
      context.missing(_tsUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  ExploreOutboxItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExploreOutboxItem(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      placeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_id'],
      )!,
      areaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_key'],
      ),
      tsUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts_utc_ms'],
      )!,
    );
  }

  @override
  $ExploreOutboxTable createAlias(String alias) {
    return $ExploreOutboxTable(attachedDatabase, alias);
  }
}

class ExploreOutboxItem extends DataClass
    implements Insertable<ExploreOutboxItem> {
  final int seq;
  final String kind;
  final String placeId;
  final String? areaKey;
  final int tsUtcMs;
  const ExploreOutboxItem({
    required this.seq,
    required this.kind,
    required this.placeId,
    this.areaKey,
    required this.tsUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['kind'] = Variable<String>(kind);
    map['place_id'] = Variable<String>(placeId);
    if (!nullToAbsent || areaKey != null) {
      map['area_key'] = Variable<String>(areaKey);
    }
    map['ts_utc_ms'] = Variable<int>(tsUtcMs);
    return map;
  }

  ExploreOutboxCompanion toCompanion(bool nullToAbsent) {
    return ExploreOutboxCompanion(
      seq: Value(seq),
      kind: Value(kind),
      placeId: Value(placeId),
      areaKey: areaKey == null && nullToAbsent
          ? const Value.absent()
          : Value(areaKey),
      tsUtcMs: Value(tsUtcMs),
    );
  }

  factory ExploreOutboxItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExploreOutboxItem(
      seq: serializer.fromJson<int>(json['seq']),
      kind: serializer.fromJson<String>(json['kind']),
      placeId: serializer.fromJson<String>(json['placeId']),
      areaKey: serializer.fromJson<String?>(json['areaKey']),
      tsUtcMs: serializer.fromJson<int>(json['tsUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'kind': serializer.toJson<String>(kind),
      'placeId': serializer.toJson<String>(placeId),
      'areaKey': serializer.toJson<String?>(areaKey),
      'tsUtcMs': serializer.toJson<int>(tsUtcMs),
    };
  }

  ExploreOutboxItem copyWith({
    int? seq,
    String? kind,
    String? placeId,
    Value<String?> areaKey = const Value.absent(),
    int? tsUtcMs,
  }) => ExploreOutboxItem(
    seq: seq ?? this.seq,
    kind: kind ?? this.kind,
    placeId: placeId ?? this.placeId,
    areaKey: areaKey.present ? areaKey.value : this.areaKey,
    tsUtcMs: tsUtcMs ?? this.tsUtcMs,
  );
  ExploreOutboxItem copyWithCompanion(ExploreOutboxCompanion data) {
    return ExploreOutboxItem(
      seq: data.seq.present ? data.seq.value : this.seq,
      kind: data.kind.present ? data.kind.value : this.kind,
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      areaKey: data.areaKey.present ? data.areaKey.value : this.areaKey,
      tsUtcMs: data.tsUtcMs.present ? data.tsUtcMs.value : this.tsUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExploreOutboxItem(')
          ..write('seq: $seq, ')
          ..write('kind: $kind, ')
          ..write('placeId: $placeId, ')
          ..write('areaKey: $areaKey, ')
          ..write('tsUtcMs: $tsUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seq, kind, placeId, areaKey, tsUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExploreOutboxItem &&
          other.seq == this.seq &&
          other.kind == this.kind &&
          other.placeId == this.placeId &&
          other.areaKey == this.areaKey &&
          other.tsUtcMs == this.tsUtcMs);
}

class ExploreOutboxCompanion extends UpdateCompanion<ExploreOutboxItem> {
  final Value<int> seq;
  final Value<String> kind;
  final Value<String> placeId;
  final Value<String?> areaKey;
  final Value<int> tsUtcMs;
  const ExploreOutboxCompanion({
    this.seq = const Value.absent(),
    this.kind = const Value.absent(),
    this.placeId = const Value.absent(),
    this.areaKey = const Value.absent(),
    this.tsUtcMs = const Value.absent(),
  });
  ExploreOutboxCompanion.insert({
    this.seq = const Value.absent(),
    required String kind,
    required String placeId,
    this.areaKey = const Value.absent(),
    required int tsUtcMs,
  }) : kind = Value(kind),
       placeId = Value(placeId),
       tsUtcMs = Value(tsUtcMs);
  static Insertable<ExploreOutboxItem> custom({
    Expression<int>? seq,
    Expression<String>? kind,
    Expression<String>? placeId,
    Expression<String>? areaKey,
    Expression<int>? tsUtcMs,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (kind != null) 'kind': kind,
      if (placeId != null) 'place_id': placeId,
      if (areaKey != null) 'area_key': areaKey,
      if (tsUtcMs != null) 'ts_utc_ms': tsUtcMs,
    });
  }

  ExploreOutboxCompanion copyWith({
    Value<int>? seq,
    Value<String>? kind,
    Value<String>? placeId,
    Value<String?>? areaKey,
    Value<int>? tsUtcMs,
  }) {
    return ExploreOutboxCompanion(
      seq: seq ?? this.seq,
      kind: kind ?? this.kind,
      placeId: placeId ?? this.placeId,
      areaKey: areaKey ?? this.areaKey,
      tsUtcMs: tsUtcMs ?? this.tsUtcMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (areaKey.present) {
      map['area_key'] = Variable<String>(areaKey.value);
    }
    if (tsUtcMs.present) {
      map['ts_utc_ms'] = Variable<int>(tsUtcMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExploreOutboxCompanion(')
          ..write('seq: $seq, ')
          ..write('kind: $kind, ')
          ..write('placeId: $placeId, ')
          ..write('areaKey: $areaKey, ')
          ..write('tsUtcMs: $tsUtcMs')
          ..write(')'))
        .toString();
  }
}

class $MetaTableTable extends MetaTable with TableInfo<$MetaTableTable, Meta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<Meta> instance, {
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
  Meta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Meta(
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
  $MetaTableTable createAlias(String alias) {
    return $MetaTableTable(attachedDatabase, alias);
  }
}

class Meta extends DataClass implements Insertable<Meta> {
  final String key;
  final String value;
  const Meta({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaTableCompanion toCompanion(bool nullToAbsent) {
    return MetaTableCompanion(key: Value(key), value: Value(value));
  }

  factory Meta.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Meta(
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

  Meta copyWith({String? key, String? value}) =>
      Meta(key: key ?? this.key, value: value ?? this.value);
  Meta copyWithCompanion(MetaTableCompanion data) {
    return Meta(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Meta(')
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
      (other is Meta && other.key == this.key && other.value == this.value);
}

class MetaTableCompanion extends UpdateCompanion<Meta> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const MetaTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Meta> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return MetaTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $ExploredAreaTable exploredArea = $ExploredAreaTable(this);
  late final $ExploreOutboxTable exploreOutbox = $ExploreOutboxTable(this);
  late final $MetaTableTable metaTable = $MetaTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    exploredArea,
    exploreOutbox,
    metaTable,
  ];
}
