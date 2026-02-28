// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db_inspector_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ByteaInfo _$ByteaInfoFromJson(Map<String, dynamic> json) => ByteaInfo(
  sizeBytes: (json['size_bytes'] as num).toInt(),
  prefixHex: json['prefix_hex'] as String,
  format: json['format'] as String,
  heCiphertextCount: (json['he_ciphertext_count'] as num?)?.toInt(),
  hePerCtSizes: (json['he_per_ct_sizes'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
);

Map<String, dynamic> _$ByteaInfoToJson(ByteaInfo instance) => <String, dynamic>{
  'size_bytes': instance.sizeBytes,
  'prefix_hex': instance.prefixHex,
  'format': instance.format,
  'he_ciphertext_count': instance.heCiphertextCount,
  'he_per_ct_sizes': instance.hePerCtSizes,
};

ColumnInfo _$ColumnInfoFromJson(Map<String, dynamic> json) => ColumnInfo(
  name: json['name'] as String,
  dataType: json['data_type'] as String,
  nullable: json['nullable'] as bool,
  defaultValue: json['default_value'] as String?,
  isPrimaryKey: json['is_primary_key'] as bool,
);

Map<String, dynamic> _$ColumnInfoToJson(ColumnInfo instance) =>
    <String, dynamic>{
      'name': instance.name,
      'data_type': instance.dataType,
      'nullable': instance.nullable,
      'default_value': instance.defaultValue,
      'is_primary_key': instance.isPrimaryKey,
    };

ForeignKeyInfo _$ForeignKeyInfoFromJson(Map<String, dynamic> json) =>
    ForeignKeyInfo(
      column: json['column'] as String,
      referencedTable: json['referenced_table'] as String,
      referencedColumn: json['referenced_column'] as String,
    );

Map<String, dynamic> _$ForeignKeyInfoToJson(ForeignKeyInfo instance) =>
    <String, dynamic>{
      'column': instance.column,
      'referenced_table': instance.referencedTable,
      'referenced_column': instance.referencedColumn,
    };

TableSchema _$TableSchemaFromJson(Map<String, dynamic> json) => TableSchema(
  tableName: json['table_name'] as String,
  columns: (json['columns'] as List<dynamic>)
      .map((e) => ColumnInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
  foreignKeys: (json['foreign_keys'] as List<dynamic>)
      .map((e) => ForeignKeyInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
  rowCount: (json['row_count'] as num).toInt(),
);

Map<String, dynamic> _$TableSchemaToJson(TableSchema instance) =>
    <String, dynamic>{
      'table_name': instance.tableName,
      'columns': instance.columns,
      'foreign_keys': instance.foreignKeys,
      'row_count': instance.rowCount,
    };

DbSchemaResponse _$DbSchemaResponseFromJson(Map<String, dynamic> json) =>
    DbSchemaResponse(
      tables: (json['tables'] as List<dynamic>)
          .map((e) => TableSchema.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DbSchemaResponseToJson(DbSchemaResponse instance) =>
    <String, dynamic>{'tables': instance.tables};

TableRowsResponse _$TableRowsResponseFromJson(Map<String, dynamic> json) =>
    TableRowsResponse(
      tableName: json['table_name'] as String,
      columns: (json['columns'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      rows: (json['rows'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      totalCount: (json['total_count'] as num).toInt(),
      hasMore: json['has_more'] as bool,
    );

Map<String, dynamic> _$TableRowsResponseToJson(TableRowsResponse instance) =>
    <String, dynamic>{
      'table_name': instance.tableName,
      'columns': instance.columns,
      'rows': instance.rows,
      'total_count': instance.totalCount,
      'has_more': instance.hasMore,
    };

RowDetailResponse _$RowDetailResponseFromJson(Map<String, dynamic> json) =>
    RowDetailResponse(
      tableName: json['table_name'] as String,
      primaryKey: json['primary_key'] as String,
      row: json['row'] as Map<String, dynamic>,
      related: json['related'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$RowDetailResponseToJson(RowDetailResponse instance) =>
    <String, dynamic>{
      'table_name': instance.tableName,
      'primary_key': instance.primaryKey,
      'row': instance.row,
      'related': instance.related,
    };

DbStatsResponse _$DbStatsResponseFromJson(Map<String, dynamic> json) =>
    DbStatsResponse(
      identitiesCount: (json['identities_count'] as num).toInt(),
      templatesCount: (json['templates_count'] as num).toInt(),
      matchLogCount: (json['match_log_count'] as num).toInt(),
      heTemplatesCount: (json['he_templates_count'] as num).toInt(),
      npzTemplatesCount: (json['npz_templates_count'] as num).toInt(),
      dbSizeBytes: (json['db_size_bytes'] as num).toInt(),
    );

Map<String, dynamic> _$DbStatsResponseToJson(DbStatsResponse instance) =>
    <String, dynamic>{
      'identities_count': instance.identitiesCount,
      'templates_count': instance.templatesCount,
      'match_log_count': instance.matchLogCount,
      'he_templates_count': instance.heTemplatesCount,
      'npz_templates_count': instance.npzTemplatesCount,
      'db_size_bytes': instance.dbSizeBytes,
    };
