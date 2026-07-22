// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $VisitOutboxTable extends VisitOutbox
    with TableInfo<$VisitOutboxTable, VisitOutboxItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisitOutboxTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dwellSecondsMeta = const VerificationMeta(
    'dwellSeconds',
  );
  @override
  late final GeneratedColumn<int> dwellSeconds = GeneratedColumn<int>(
    'dwell_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<int> synced = GeneratedColumn<int>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    seq,
    kind,
    lat,
    lon,
    startedAt,
    dwellSeconds,
    synced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visit_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisitOutboxItem> instance, {
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
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('dwell_seconds')) {
      context.handle(
        _dwellSecondsMeta,
        dwellSeconds.isAcceptableOrUnknown(
          data['dwell_seconds']!,
          _dwellSecondsMeta,
        ),
      );
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  VisitOutboxItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisitOutboxItem(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      dwellSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dwell_seconds'],
      ),
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced'],
      )!,
    );
  }

  @override
  $VisitOutboxTable createAlias(String alias) {
    return $VisitOutboxTable(attachedDatabase, alias);
  }
}

class VisitOutboxItem extends DataClass implements Insertable<VisitOutboxItem> {
  final int seq;
  final String kind;
  final double lat;
  final double lon;
  final int startedAt;
  final int? dwellSeconds;
  final int synced;
  const VisitOutboxItem({
    required this.seq,
    required this.kind,
    required this.lat,
    required this.lon,
    required this.startedAt,
    this.dwellSeconds,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['kind'] = Variable<String>(kind);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || dwellSeconds != null) {
      map['dwell_seconds'] = Variable<int>(dwellSeconds);
    }
    map['synced'] = Variable<int>(synced);
    return map;
  }

  VisitOutboxCompanion toCompanion(bool nullToAbsent) {
    return VisitOutboxCompanion(
      seq: Value(seq),
      kind: Value(kind),
      lat: Value(lat),
      lon: Value(lon),
      startedAt: Value(startedAt),
      dwellSeconds: dwellSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(dwellSeconds),
      synced: Value(synced),
    );
  }

  factory VisitOutboxItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisitOutboxItem(
      seq: serializer.fromJson<int>(json['seq']),
      kind: serializer.fromJson<String>(json['kind']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      dwellSeconds: serializer.fromJson<int?>(json['dwellSeconds']),
      synced: serializer.fromJson<int>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'kind': serializer.toJson<String>(kind),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'startedAt': serializer.toJson<int>(startedAt),
      'dwellSeconds': serializer.toJson<int?>(dwellSeconds),
      'synced': serializer.toJson<int>(synced),
    };
  }

  VisitOutboxItem copyWith({
    int? seq,
    String? kind,
    double? lat,
    double? lon,
    int? startedAt,
    Value<int?> dwellSeconds = const Value.absent(),
    int? synced,
  }) => VisitOutboxItem(
    seq: seq ?? this.seq,
    kind: kind ?? this.kind,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    startedAt: startedAt ?? this.startedAt,
    dwellSeconds: dwellSeconds.present ? dwellSeconds.value : this.dwellSeconds,
    synced: synced ?? this.synced,
  );
  VisitOutboxItem copyWithCompanion(VisitOutboxCompanion data) {
    return VisitOutboxItem(
      seq: data.seq.present ? data.seq.value : this.seq,
      kind: data.kind.present ? data.kind.value : this.kind,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      dwellSeconds: data.dwellSeconds.present
          ? data.dwellSeconds.value
          : this.dwellSeconds,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisitOutboxItem(')
          ..write('seq: $seq, ')
          ..write('kind: $kind, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('startedAt: $startedAt, ')
          ..write('dwellSeconds: $dwellSeconds, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(seq, kind, lat, lon, startedAt, dwellSeconds, synced);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisitOutboxItem &&
          other.seq == this.seq &&
          other.kind == this.kind &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.startedAt == this.startedAt &&
          other.dwellSeconds == this.dwellSeconds &&
          other.synced == this.synced);
}

class VisitOutboxCompanion extends UpdateCompanion<VisitOutboxItem> {
  final Value<int> seq;
  final Value<String> kind;
  final Value<double> lat;
  final Value<double> lon;
  final Value<int> startedAt;
  final Value<int?> dwellSeconds;
  final Value<int> synced;
  const VisitOutboxCompanion({
    this.seq = const Value.absent(),
    this.kind = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.dwellSeconds = const Value.absent(),
    this.synced = const Value.absent(),
  });
  VisitOutboxCompanion.insert({
    this.seq = const Value.absent(),
    required String kind,
    required double lat,
    required double lon,
    required int startedAt,
    this.dwellSeconds = const Value.absent(),
    this.synced = const Value.absent(),
  }) : kind = Value(kind),
       lat = Value(lat),
       lon = Value(lon),
       startedAt = Value(startedAt);
  static Insertable<VisitOutboxItem> custom({
    Expression<int>? seq,
    Expression<String>? kind,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<int>? startedAt,
    Expression<int>? dwellSeconds,
    Expression<int>? synced,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (kind != null) 'kind': kind,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (startedAt != null) 'started_at': startedAt,
      if (dwellSeconds != null) 'dwell_seconds': dwellSeconds,
      if (synced != null) 'synced': synced,
    });
  }

  VisitOutboxCompanion copyWith({
    Value<int>? seq,
    Value<String>? kind,
    Value<double>? lat,
    Value<double>? lon,
    Value<int>? startedAt,
    Value<int?>? dwellSeconds,
    Value<int>? synced,
  }) {
    return VisitOutboxCompanion(
      seq: seq ?? this.seq,
      kind: kind ?? this.kind,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      startedAt: startedAt ?? this.startedAt,
      dwellSeconds: dwellSeconds ?? this.dwellSeconds,
      synced: synced ?? this.synced,
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
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (dwellSeconds.present) {
      map['dwell_seconds'] = Variable<int>(dwellSeconds.value);
    }
    if (synced.present) {
      map['synced'] = Variable<int>(synced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisitOutboxCompanion(')
          ..write('seq: $seq, ')
          ..write('kind: $kind, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('startedAt: $startedAt, ')
          ..write('dwellSeconds: $dwellSeconds, ')
          ..write('synced: $synced')
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
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $VisitOutboxTable visitOutbox = $VisitOutboxTable(this);
  late final $MetaTableTable metaTable = $MetaTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [visitOutbox, metaTable];
}

typedef $$VisitOutboxTableCreateCompanionBuilder =
    VisitOutboxCompanion Function({
      Value<int> seq,
      required String kind,
      required double lat,
      required double lon,
      required int startedAt,
      Value<int?> dwellSeconds,
      Value<int> synced,
    });
typedef $$VisitOutboxTableUpdateCompanionBuilder =
    VisitOutboxCompanion Function({
      Value<int> seq,
      Value<String> kind,
      Value<double> lat,
      Value<double> lon,
      Value<int> startedAt,
      Value<int?> dwellSeconds,
      Value<int> synced,
    });

class $$VisitOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $VisitOutboxTable> {
  $$VisitOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dwellSeconds => $composableBuilder(
    column: $table.dwellSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisitOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $VisitOutboxTable> {
  $$VisitOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dwellSeconds => $composableBuilder(
    column: $table.dwellSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisitOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisitOutboxTable> {
  $$VisitOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get dwellSeconds => $composableBuilder(
    column: $table.dwellSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$VisitOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisitOutboxTable,
          VisitOutboxItem,
          $$VisitOutboxTableFilterComposer,
          $$VisitOutboxTableOrderingComposer,
          $$VisitOutboxTableAnnotationComposer,
          $$VisitOutboxTableCreateCompanionBuilder,
          $$VisitOutboxTableUpdateCompanionBuilder,
          (
            VisitOutboxItem,
            BaseReferences<_$AppDatabase, $VisitOutboxTable, VisitOutboxItem>,
          ),
          VisitOutboxItem,
          PrefetchHooks Function()
        > {
  $$VisitOutboxTableTableManager(_$AppDatabase db, $VisitOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisitOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisitOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisitOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int?> dwellSeconds = const Value.absent(),
                Value<int> synced = const Value.absent(),
              }) => VisitOutboxCompanion(
                seq: seq,
                kind: kind,
                lat: lat,
                lon: lon,
                startedAt: startedAt,
                dwellSeconds: dwellSeconds,
                synced: synced,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required String kind,
                required double lat,
                required double lon,
                required int startedAt,
                Value<int?> dwellSeconds = const Value.absent(),
                Value<int> synced = const Value.absent(),
              }) => VisitOutboxCompanion.insert(
                seq: seq,
                kind: kind,
                lat: lat,
                lon: lon,
                startedAt: startedAt,
                dwellSeconds: dwellSeconds,
                synced: synced,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisitOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisitOutboxTable,
      VisitOutboxItem,
      $$VisitOutboxTableFilterComposer,
      $$VisitOutboxTableOrderingComposer,
      $$VisitOutboxTableAnnotationComposer,
      $$VisitOutboxTableCreateCompanionBuilder,
      $$VisitOutboxTableUpdateCompanionBuilder,
      (
        VisitOutboxItem,
        BaseReferences<_$AppDatabase, $VisitOutboxTable, VisitOutboxItem>,
      ),
      VisitOutboxItem,
      PrefetchHooks Function()
    >;
typedef $$MetaTableTableCreateCompanionBuilder =
    MetaTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$MetaTableTableUpdateCompanionBuilder =
    MetaTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$MetaTableTableFilterComposer
    extends Composer<_$AppDatabase, $MetaTableTable> {
  $$MetaTableTableFilterComposer({
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

class $$MetaTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MetaTableTable> {
  $$MetaTableTableOrderingComposer({
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

class $$MetaTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MetaTableTable> {
  $$MetaTableTableAnnotationComposer({
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

class $$MetaTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MetaTableTable,
          Meta,
          $$MetaTableTableFilterComposer,
          $$MetaTableTableOrderingComposer,
          $$MetaTableTableAnnotationComposer,
          $$MetaTableTableCreateCompanionBuilder,
          $$MetaTableTableUpdateCompanionBuilder,
          (Meta, BaseReferences<_$AppDatabase, $MetaTableTable, Meta>),
          Meta,
          PrefetchHooks Function()
        > {
  $$MetaTableTableTableManager(_$AppDatabase db, $MetaTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaTableCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => MetaTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MetaTableTable,
      Meta,
      $$MetaTableTableFilterComposer,
      $$MetaTableTableOrderingComposer,
      $$MetaTableTableAnnotationComposer,
      $$MetaTableTableCreateCompanionBuilder,
      $$MetaTableTableUpdateCompanionBuilder,
      (Meta, BaseReferences<_$AppDatabase, $MetaTableTable, Meta>),
      Meta,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$VisitOutboxTableTableManager get visitOutbox =>
      $$VisitOutboxTableTableManager(_db, _db.visitOutbox);
  $$MetaTableTableTableManager get metaTable =>
      $$MetaTableTableTableManager(_db, _db.metaTable);
}
