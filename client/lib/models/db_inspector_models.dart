import 'package:json_annotation/json_annotation.dart';

part 'db_inspector_models.g.dart';

@JsonSerializable()
class ByteaInfo {
  @JsonKey(name: 'size_bytes')
  final int sizeBytes;
  @JsonKey(name: 'prefix_hex')
  final String prefixHex;
  final String format; // "npz", "hev1", "unknown"
  @JsonKey(name: 'he_ciphertext_count')
  final int? heCiphertextCount;
  @JsonKey(name: 'he_per_ct_sizes')
  final List<int>? hePerCtSizes;

  const ByteaInfo({
    required this.sizeBytes,
    required this.prefixHex,
    required this.format,
    this.heCiphertextCount,
    this.hePerCtSizes,
  });

  factory ByteaInfo.fromJson(Map<String, dynamic> json) =>
      _$ByteaInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ByteaInfoToJson(this);

  String get humanSize {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }
}

@JsonSerializable()
class ColumnInfo {
  final String name;
  @JsonKey(name: 'data_type')
  final String dataType;
  final bool nullable;
  @JsonKey(name: 'default_value')
  final String? defaultValue;
  @JsonKey(name: 'is_primary_key')
  final bool isPrimaryKey;

  const ColumnInfo({
    required this.name,
    required this.dataType,
    required this.nullable,
    this.defaultValue,
    required this.isPrimaryKey,
  });

  factory ColumnInfo.fromJson(Map<String, dynamic> json) =>
      _$ColumnInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ColumnInfoToJson(this);
}

@JsonSerializable()
class ForeignKeyInfo {
  final String column;
  @JsonKey(name: 'referenced_table')
  final String referencedTable;
  @JsonKey(name: 'referenced_column')
  final String referencedColumn;

  const ForeignKeyInfo({
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
  });

  factory ForeignKeyInfo.fromJson(Map<String, dynamic> json) =>
      _$ForeignKeyInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ForeignKeyInfoToJson(this);
}

@JsonSerializable()
class TableSchema {
  @JsonKey(name: 'table_name')
  final String tableName;
  final List<ColumnInfo> columns;
  @JsonKey(name: 'foreign_keys')
  final List<ForeignKeyInfo> foreignKeys;
  @JsonKey(name: 'row_count')
  final int rowCount;

  const TableSchema({
    required this.tableName,
    required this.columns,
    required this.foreignKeys,
    required this.rowCount,
  });

  factory TableSchema.fromJson(Map<String, dynamic> json) =>
      _$TableSchemaFromJson(json);
  Map<String, dynamic> toJson() => _$TableSchemaToJson(this);
}

@JsonSerializable()
class DbSchemaResponse {
  final List<TableSchema> tables;

  const DbSchemaResponse({required this.tables});

  factory DbSchemaResponse.fromJson(Map<String, dynamic> json) =>
      _$DbSchemaResponseFromJson(json);
  Map<String, dynamic> toJson() => _$DbSchemaResponseToJson(this);
}

@JsonSerializable()
class TableRowsResponse {
  @JsonKey(name: 'table_name')
  final String tableName;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  @JsonKey(name: 'total_count')
  final int totalCount;
  @JsonKey(name: 'has_more')
  final bool hasMore;

  const TableRowsResponse({
    required this.tableName,
    required this.columns,
    required this.rows,
    required this.totalCount,
    required this.hasMore,
  });

  factory TableRowsResponse.fromJson(Map<String, dynamic> json) =>
      _$TableRowsResponseFromJson(json);
  Map<String, dynamic> toJson() => _$TableRowsResponseToJson(this);
}

@JsonSerializable()
class RowDetailResponse {
  @JsonKey(name: 'table_name')
  final String tableName;
  @JsonKey(name: 'primary_key')
  final String primaryKey;
  final Map<String, dynamic> row;
  final Map<String, dynamic>? related;

  const RowDetailResponse({
    required this.tableName,
    required this.primaryKey,
    required this.row,
    this.related,
  });

  factory RowDetailResponse.fromJson(Map<String, dynamic> json) =>
      _$RowDetailResponseFromJson(json);
  Map<String, dynamic> toJson() => _$RowDetailResponseToJson(this);
}

@JsonSerializable()
class DbStatsResponse {
  @JsonKey(name: 'identities_count')
  final int identitiesCount;
  @JsonKey(name: 'templates_count')
  final int templatesCount;
  @JsonKey(name: 'match_log_count')
  final int matchLogCount;
  @JsonKey(name: 'he_templates_count')
  final int heTemplatesCount;
  @JsonKey(name: 'npz_templates_count')
  final int npzTemplatesCount;
  @JsonKey(name: 'db_size_bytes')
  final int dbSizeBytes;

  const DbStatsResponse({
    required this.identitiesCount,
    required this.templatesCount,
    required this.matchLogCount,
    required this.heTemplatesCount,
    required this.npzTemplatesCount,
    required this.dbSizeBytes,
  });

  factory DbStatsResponse.fromJson(Map<String, dynamic> json) =>
      _$DbStatsResponseFromJson(json);
  Map<String, dynamic> toJson() => _$DbStatsResponseToJson(this);

  String get humanDbSize {
    if (dbSizeBytes >= 1024 * 1024 * 1024) {
      return '${(dbSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (dbSizeBytes >= 1024 * 1024) {
      return '${(dbSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (dbSizeBytes >= 1024) {
      return '${(dbSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$dbSizeBytes B';
  }
}
