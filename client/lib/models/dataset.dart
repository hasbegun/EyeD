import 'package:json_annotation/json_annotation.dart';

part 'dataset.g.dart';

@JsonSerializable()
class DatasetInfo {
  final String name;
  final String format;
  final int count;

  const DatasetInfo({
    required this.name,
    required this.format,
    required this.count,
  });

  factory DatasetInfo.fromJson(Map<String, dynamic> json) =>
      _$DatasetInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DatasetInfoToJson(this);
}

@JsonSerializable()
class DatasetImage {
  final String path;
  @JsonKey(name: 'subject_id')
  final String subjectId;
  @JsonKey(name: 'eye_side')
  final String eyeSide;
  final String filename;

  const DatasetImage({
    required this.path,
    required this.subjectId,
    required this.eyeSide,
    required this.filename,
  });

  factory DatasetImage.fromJson(Map<String, dynamic> json) =>
      _$DatasetImageFromJson(json);
  Map<String, dynamic> toJson() => _$DatasetImageToJson(this);
}

@JsonSerializable()
class SubjectInfo {
  @JsonKey(name: 'subject_id')
  final String subjectId;
  @JsonKey(name: 'image_count')
  final int imageCount;

  const SubjectInfo({
    required this.subjectId,
    required this.imageCount,
  });

  factory SubjectInfo.fromJson(Map<String, dynamic> json) =>
      _$SubjectInfoFromJson(json);
  Map<String, dynamic> toJson() => _$SubjectInfoToJson(this);
}

@JsonSerializable()
class DatasetPathInfo {
  final String path;
  final bool exists;
  @JsonKey(name: 'dataset_count')
  final int datasetCount;

  const DatasetPathInfo({
    required this.path,
    required this.exists,
    required this.datasetCount,
  });

  factory DatasetPathInfo.fromJson(Map<String, dynamic> json) =>
      _$DatasetPathInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DatasetPathInfoToJson(this);
}
