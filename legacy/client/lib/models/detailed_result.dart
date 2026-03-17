import 'package:json_annotation/json_annotation.dart';
import 'analyze_result.dart';

part 'detailed_result.g.dart';

@JsonSerializable()
class EyeGeometry {
  @JsonKey(name: 'pupil_center')
  final List<double> pupilCenter;
  @JsonKey(name: 'iris_center')
  final List<double> irisCenter;
  @JsonKey(name: 'pupil_radius')
  final double pupilRadius;
  @JsonKey(name: 'iris_radius')
  final double irisRadius;
  @JsonKey(name: 'eye_orientation')
  final double eyeOrientation;

  const EyeGeometry({
    required this.pupilCenter,
    required this.irisCenter,
    required this.pupilRadius,
    required this.irisRadius,
    required this.eyeOrientation,
  });

  factory EyeGeometry.fromJson(Map<String, dynamic> json) =>
      _$EyeGeometryFromJson(json);
  Map<String, dynamic> toJson() => _$EyeGeometryToJson(this);
}

@JsonSerializable()
class QualityMetrics {
  @JsonKey(name: 'offgaze_score')
  final double offgazeScore;
  @JsonKey(name: 'occlusion_90')
  final double occlusion90;
  @JsonKey(name: 'occlusion_30')
  final double occlusion30;
  final double sharpness;
  @JsonKey(name: 'pupil_iris_ratio')
  final double pupilIrisRatio;

  const QualityMetrics({
    required this.offgazeScore,
    required this.occlusion90,
    required this.occlusion30,
    required this.sharpness,
    required this.pupilIrisRatio,
  });

  factory QualityMetrics.fromJson(Map<String, dynamic> json) =>
      _$QualityMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$QualityMetricsToJson(this);
}

@JsonSerializable()
class DetailedResult {
  @JsonKey(name: 'frame_id')
  final String frameId;
  @JsonKey(name: 'device_id')
  final String deviceId;
  @JsonKey(name: 'iris_template_b64')
  final String? irisTemplateB64;
  final MatchInfo? match;
  @JsonKey(name: 'latency_ms')
  final double latencyMs;
  final String? error;
  final EyeGeometry? geometry;
  final QualityMetrics? quality;
  @JsonKey(name: 'original_image_b64')
  final String? originalImageB64;
  @JsonKey(name: 'segmentation_overlay_b64')
  final String? segmentationOverlayB64;
  @JsonKey(name: 'normalized_iris_b64')
  final String? normalizedIrisB64;
  @JsonKey(name: 'iris_code_b64')
  final String? irisCodeB64;
  @JsonKey(name: 'noise_mask_b64')
  final String? noiseMaskB64;

  const DetailedResult({
    required this.frameId,
    required this.deviceId,
    this.irisTemplateB64,
    this.match,
    required this.latencyMs,
    this.error,
    this.geometry,
    this.quality,
    this.originalImageB64,
    this.segmentationOverlayB64,
    this.normalizedIrisB64,
    this.irisCodeB64,
    this.noiseMaskB64,
  });

  factory DetailedResult.fromJson(Map<String, dynamic> json) =>
      _$DetailedResultFromJson(json);
  Map<String, dynamic> toJson() => _$DetailedResultToJson(this);

  /// Convert to [AnalyzeResult] for history/dashboard integration.
  AnalyzeResult toAnalyzeResult() => AnalyzeResult(
        frameId: frameId,
        deviceId: deviceId,
        match: match,
        irisTemplateB64: irisTemplateB64,
        latencyMs: latencyMs,
        error: error,
      );
}
