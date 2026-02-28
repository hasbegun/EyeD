// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dataset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DatasetInfo _$DatasetInfoFromJson(Map<String, dynamic> json) => DatasetInfo(
  name: json['name'] as String,
  format: json['format'] as String,
  count: (json['count'] as num).toInt(),
);

Map<String, dynamic> _$DatasetInfoToJson(DatasetInfo instance) =>
    <String, dynamic>{
      'name': instance.name,
      'format': instance.format,
      'count': instance.count,
    };

DatasetImage _$DatasetImageFromJson(Map<String, dynamic> json) => DatasetImage(
  path: json['path'] as String,
  subjectId: json['subject_id'] as String,
  eyeSide: json['eye_side'] as String,
  filename: json['filename'] as String,
);

Map<String, dynamic> _$DatasetImageToJson(DatasetImage instance) =>
    <String, dynamic>{
      'path': instance.path,
      'subject_id': instance.subjectId,
      'eye_side': instance.eyeSide,
      'filename': instance.filename,
    };

SubjectInfo _$SubjectInfoFromJson(Map<String, dynamic> json) => SubjectInfo(
  subjectId: json['subject_id'] as String,
  imageCount: (json['image_count'] as num).toInt(),
);

Map<String, dynamic> _$SubjectInfoToJson(SubjectInfo instance) =>
    <String, dynamic>{
      'subject_id': instance.subjectId,
      'image_count': instance.imageCount,
    };

DatasetPathInfo _$DatasetPathInfoFromJson(Map<String, dynamic> json) =>
    DatasetPathInfo(
      path: json['path'] as String,
      exists: json['exists'] as bool,
      datasetCount: (json['dataset_count'] as num).toInt(),
    );

Map<String, dynamic> _$DatasetPathInfoToJson(DatasetPathInfo instance) =>
    <String, dynamic>{
      'path': instance.path,
      'exists': instance.exists,
      'dataset_count': instance.datasetCount,
    };
