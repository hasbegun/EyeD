// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detailed_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EyeGeometry _$EyeGeometryFromJson(Map<String, dynamic> json) => EyeGeometry(
  pupilCenter: (json['pupil_center'] as List<dynamic>)
      .map((e) => (e as num).toDouble())
      .toList(),
  irisCenter: (json['iris_center'] as List<dynamic>)
      .map((e) => (e as num).toDouble())
      .toList(),
  pupilRadius: (json['pupil_radius'] as num).toDouble(),
  irisRadius: (json['iris_radius'] as num).toDouble(),
  eyeOrientation: (json['eye_orientation'] as num).toDouble(),
);

Map<String, dynamic> _$EyeGeometryToJson(EyeGeometry instance) =>
    <String, dynamic>{
      'pupil_center': instance.pupilCenter,
      'iris_center': instance.irisCenter,
      'pupil_radius': instance.pupilRadius,
      'iris_radius': instance.irisRadius,
      'eye_orientation': instance.eyeOrientation,
    };

QualityMetrics _$QualityMetricsFromJson(Map<String, dynamic> json) =>
    QualityMetrics(
      offgazeScore: (json['offgaze_score'] as num).toDouble(),
      occlusion90: (json['occlusion_90'] as num).toDouble(),
      occlusion30: (json['occlusion_30'] as num).toDouble(),
      sharpness: (json['sharpness'] as num).toDouble(),
      pupilIrisRatio: (json['pupil_iris_ratio'] as num).toDouble(),
    );

Map<String, dynamic> _$QualityMetricsToJson(QualityMetrics instance) =>
    <String, dynamic>{
      'offgaze_score': instance.offgazeScore,
      'occlusion_90': instance.occlusion90,
      'occlusion_30': instance.occlusion30,
      'sharpness': instance.sharpness,
      'pupil_iris_ratio': instance.pupilIrisRatio,
    };

DetailedResult _$DetailedResultFromJson(Map<String, dynamic> json) =>
    DetailedResult(
      frameId: json['frame_id'] as String,
      deviceId: json['device_id'] as String,
      irisTemplateB64: json['iris_template_b64'] as String?,
      match: json['match'] == null
          ? null
          : MatchInfo.fromJson(json['match'] as Map<String, dynamic>),
      latencyMs: (json['latency_ms'] as num).toDouble(),
      error: json['error'] as String?,
      geometry: json['geometry'] == null
          ? null
          : EyeGeometry.fromJson(json['geometry'] as Map<String, dynamic>),
      quality: json['quality'] == null
          ? null
          : QualityMetrics.fromJson(json['quality'] as Map<String, dynamic>),
      originalImageB64: json['original_image_b64'] as String?,
      segmentationOverlayB64: json['segmentation_overlay_b64'] as String?,
      normalizedIrisB64: json['normalized_iris_b64'] as String?,
      irisCodeB64: json['iris_code_b64'] as String?,
      noiseMaskB64: json['noise_mask_b64'] as String?,
    );

Map<String, dynamic> _$DetailedResultToJson(DetailedResult instance) =>
    <String, dynamic>{
      'frame_id': instance.frameId,
      'device_id': instance.deviceId,
      'iris_template_b64': instance.irisTemplateB64,
      'match': instance.match,
      'latency_ms': instance.latencyMs,
      'error': instance.error,
      'geometry': instance.geometry,
      'quality': instance.quality,
      'original_image_b64': instance.originalImageB64,
      'segmentation_overlay_b64': instance.segmentationOverlayB64,
      'normalized_iris_b64': instance.normalizedIrisB64,
      'iris_code_b64': instance.irisCodeB64,
      'noise_mask_b64': instance.noiseMaskB64,
    };
