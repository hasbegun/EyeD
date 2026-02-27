// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analyze_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MatchInfo _$MatchInfoFromJson(Map<String, dynamic> json) => MatchInfo(
  hammingDistance: (json['hamming_distance'] as num).toDouble(),
  isMatch: json['is_match'] as bool,
  matchedIdentityId: json['matched_identity_id'] as String?,
  bestRotation: (json['best_rotation'] as num).toInt(),
);

Map<String, dynamic> _$MatchInfoToJson(MatchInfo instance) => <String, dynamic>{
  'hamming_distance': instance.hammingDistance,
  'is_match': instance.isMatch,
  'matched_identity_id': instance.matchedIdentityId,
  'best_rotation': instance.bestRotation,
};

AnalyzeResult _$AnalyzeResultFromJson(Map<String, dynamic> json) =>
    AnalyzeResult(
      frameId: json['frame_id'] as String,
      deviceId: json['device_id'] as String,
      match: json['match'] == null
          ? null
          : MatchInfo.fromJson(json['match'] as Map<String, dynamic>),
      irisTemplateB64: json['iris_template_b64'] as String?,
      latencyMs: (json['latency_ms'] as num).toDouble(),
      error: json['error'] as String?,
    );

Map<String, dynamic> _$AnalyzeResultToJson(AnalyzeResult instance) =>
    <String, dynamic>{
      'frame_id': instance.frameId,
      'device_id': instance.deviceId,
      'match': instance.match,
      'iris_template_b64': instance.irisTemplateB64,
      'latency_ms': instance.latencyMs,
      'error': instance.error,
    };
