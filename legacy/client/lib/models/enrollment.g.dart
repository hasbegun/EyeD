// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enrollment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TemplateInfo _$TemplateInfoFromJson(Map<String, dynamic> json) => TemplateInfo(
  templateId: json['template_id'] as String,
  eyeSide: json['eye_side'] as String,
);

Map<String, dynamic> _$TemplateInfoToJson(TemplateInfo instance) =>
    <String, dynamic>{
      'template_id': instance.templateId,
      'eye_side': instance.eyeSide,
    };

EnrollResponse _$EnrollResponseFromJson(Map<String, dynamic> json) =>
    EnrollResponse(
      identityId: json['identity_id'] as String,
      templateId: json['template_id'] as String,
      isDuplicate: json['is_duplicate'] as bool,
      duplicateIdentityId: json['duplicate_identity_id'] as String?,
      duplicateIdentityName: json['duplicate_identity_name'] as String?,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$EnrollResponseToJson(EnrollResponse instance) =>
    <String, dynamic>{
      'identity_id': instance.identityId,
      'template_id': instance.templateId,
      'is_duplicate': instance.isDuplicate,
      'duplicate_identity_id': instance.duplicateIdentityId,
      'duplicate_identity_name': instance.duplicateIdentityName,
      'error': instance.error,
    };

GalleryIdentity _$GalleryIdentityFromJson(Map<String, dynamic> json) =>
    GalleryIdentity(
      identityId: json['identity_id'] as String,
      name: json['name'] as String,
      templates: (json['templates'] as List<dynamic>)
          .map((e) => TemplateInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$GalleryIdentityToJson(GalleryIdentity instance) =>
    <String, dynamic>{
      'identity_id': instance.identityId,
      'name': instance.name,
      'templates': instance.templates,
    };

BulkEnrollResult _$BulkEnrollResultFromJson(Map<String, dynamic> json) =>
    BulkEnrollResult(
      subjectId: json['subject_id'] as String,
      eyeSide: json['eye_side'] as String,
      filename: json['filename'] as String,
      identityId: json['identity_id'] as String,
      templateId: json['template_id'] as String? ?? '',
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      duplicateIdentityId: json['duplicate_identity_id'] as String?,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$BulkEnrollResultToJson(BulkEnrollResult instance) =>
    <String, dynamic>{
      'subject_id': instance.subjectId,
      'eye_side': instance.eyeSide,
      'filename': instance.filename,
      'identity_id': instance.identityId,
      'template_id': instance.templateId,
      'is_duplicate': instance.isDuplicate,
      'duplicate_identity_id': instance.duplicateIdentityId,
      'error': instance.error,
    };

BulkEnrollSummary _$BulkEnrollSummaryFromJson(Map<String, dynamic> json) =>
    BulkEnrollSummary(
      total: (json['total'] as num).toInt(),
      enrolled: (json['enrolled'] as num).toInt(),
      duplicates: (json['duplicates'] as num).toInt(),
      errors: (json['errors'] as num).toInt(),
    );

Map<String, dynamic> _$BulkEnrollSummaryToJson(BulkEnrollSummary instance) =>
    <String, dynamic>{
      'total': instance.total,
      'enrolled': instance.enrolled,
      'duplicates': instance.duplicates,
      'errors': instance.errors,
    };

TemplateDetail _$TemplateDetailFromJson(Map<String, dynamic> json) =>
    TemplateDetail(
      templateId: json['template_id'] as String,
      identityId: json['identity_id'] as String,
      identityName: json['identity_name'] as String,
      eyeSide: json['eye_side'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      nScales: (json['n_scales'] as num).toInt(),
      qualityScore: (json['quality_score'] as num).toDouble(),
      deviceId: json['device_id'] as String,
      irisCodeB64: json['iris_code_b64'] as String?,
      maskCodeB64: json['mask_code_b64'] as String?,
    );

Map<String, dynamic> _$TemplateDetailToJson(TemplateDetail instance) =>
    <String, dynamic>{
      'template_id': instance.templateId,
      'identity_id': instance.identityId,
      'identity_name': instance.identityName,
      'eye_side': instance.eyeSide,
      'width': instance.width,
      'height': instance.height,
      'n_scales': instance.nScales,
      'quality_score': instance.qualityScore,
      'device_id': instance.deviceId,
      'iris_code_b64': instance.irisCodeB64,
      'mask_code_b64': instance.maskCodeB64,
    };
