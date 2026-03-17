import 'package:json_annotation/json_annotation.dart';

part 'enrollment.g.dart';

@JsonSerializable()
class TemplateInfo {
  @JsonKey(name: 'template_id')
  final String templateId;
  @JsonKey(name: 'eye_side')
  final String eyeSide;

  const TemplateInfo({required this.templateId, required this.eyeSide});

  factory TemplateInfo.fromJson(Map<String, dynamic> json) =>
      _$TemplateInfoFromJson(json);
  Map<String, dynamic> toJson() => _$TemplateInfoToJson(this);
}

@JsonSerializable()
class EnrollResponse {
  @JsonKey(name: 'identity_id')
  final String identityId;
  @JsonKey(name: 'template_id')
  final String templateId;
  @JsonKey(name: 'is_duplicate')
  final bool isDuplicate;
  @JsonKey(name: 'duplicate_identity_id')
  final String? duplicateIdentityId;
  @JsonKey(name: 'duplicate_identity_name')
  final String? duplicateIdentityName;
  final String? error;

  const EnrollResponse({
    required this.identityId,
    required this.templateId,
    required this.isDuplicate,
    this.duplicateIdentityId,
    this.duplicateIdentityName,
    this.error,
  });

  factory EnrollResponse.fromJson(Map<String, dynamic> json) =>
      _$EnrollResponseFromJson(json);
  Map<String, dynamic> toJson() => _$EnrollResponseToJson(this);
}

@JsonSerializable()
class GalleryIdentity {
  @JsonKey(name: 'identity_id')
  final String identityId;
  final String name;
  final List<TemplateInfo> templates;

  const GalleryIdentity({
    required this.identityId,
    required this.name,
    required this.templates,
  });

  factory GalleryIdentity.fromJson(Map<String, dynamic> json) =>
      _$GalleryIdentityFromJson(json);
  Map<String, dynamic> toJson() => _$GalleryIdentityToJson(this);
}

@JsonSerializable()
class BulkEnrollResult {
  @JsonKey(name: 'subject_id')
  final String subjectId;
  @JsonKey(name: 'eye_side')
  final String eyeSide;
  final String filename;
  @JsonKey(name: 'identity_id')
  final String identityId;
  @JsonKey(name: 'template_id')
  final String templateId;
  @JsonKey(name: 'is_duplicate')
  final bool isDuplicate;
  @JsonKey(name: 'duplicate_identity_id')
  final String? duplicateIdentityId;
  final String? error;

  const BulkEnrollResult({
    required this.subjectId,
    required this.eyeSide,
    required this.filename,
    required this.identityId,
    this.templateId = '',
    this.isDuplicate = false,
    this.duplicateIdentityId,
    this.error,
  });

  factory BulkEnrollResult.fromJson(Map<String, dynamic> json) =>
      _$BulkEnrollResultFromJson(json);
  Map<String, dynamic> toJson() => _$BulkEnrollResultToJson(this);
}

@JsonSerializable()
class BulkEnrollSummary {
  final int total;
  final int enrolled;
  final int duplicates;
  final int errors;

  const BulkEnrollSummary({
    required this.total,
    required this.enrolled,
    required this.duplicates,
    required this.errors,
  });

  factory BulkEnrollSummary.fromJson(Map<String, dynamic> json) =>
      _$BulkEnrollSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$BulkEnrollSummaryToJson(this);
}

@JsonSerializable()
class TemplateDetail {
  @JsonKey(name: 'template_id')
  final String templateId;
  @JsonKey(name: 'identity_id')
  final String identityId;
  @JsonKey(name: 'identity_name')
  final String identityName;
  @JsonKey(name: 'eye_side')
  final String eyeSide;
  final int width;
  final int height;
  @JsonKey(name: 'n_scales')
  final int nScales;
  @JsonKey(name: 'quality_score')
  final double qualityScore;
  @JsonKey(name: 'device_id')
  final String deviceId;
  @JsonKey(name: 'iris_code_b64')
  final String? irisCodeB64;
  @JsonKey(name: 'mask_code_b64')
  final String? maskCodeB64;

  const TemplateDetail({
    required this.templateId,
    required this.identityId,
    required this.identityName,
    required this.eyeSide,
    required this.width,
    required this.height,
    required this.nScales,
    required this.qualityScore,
    required this.deviceId,
    this.irisCodeB64,
    this.maskCodeB64,
  });

  factory TemplateDetail.fromJson(Map<String, dynamic> json) =>
      _$TemplateDetailFromJson(json);
  Map<String, dynamic> toJson() => _$TemplateDetailToJson(this);
}

sealed class BulkEnrollEvent {}

class BulkEnrollProgress extends BulkEnrollEvent {
  final BulkEnrollResult result;
  BulkEnrollProgress(this.result);
}

class BulkEnrollDone extends BulkEnrollEvent {
  final BulkEnrollSummary summary;
  BulkEnrollDone(this.summary);
}
