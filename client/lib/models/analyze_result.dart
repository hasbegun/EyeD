import 'package:json_annotation/json_annotation.dart';

part 'analyze_result.g.dart';

@JsonSerializable()
class MatchInfo {
  @JsonKey(name: 'hamming_distance')
  final double hammingDistance;
  @JsonKey(name: 'is_match')
  final bool isMatch;
  @JsonKey(name: 'matched_identity_id')
  final String? matchedIdentityId;
  @JsonKey(name: 'matched_identity_name')
  final String? matchedIdentityName;
  @JsonKey(name: 'best_rotation')
  final int bestRotation;

  const MatchInfo({
    required this.hammingDistance,
    required this.isMatch,
    this.matchedIdentityId,
    this.matchedIdentityName,
    required this.bestRotation,
  });

  factory MatchInfo.fromJson(Map<String, dynamic> json) =>
      _$MatchInfoFromJson(json);
  Map<String, dynamic> toJson() => _$MatchInfoToJson(this);
}

@JsonSerializable()
class AnalyzeResult {
  @JsonKey(name: 'frame_id')
  final String frameId;
  @JsonKey(name: 'device_id')
  final String deviceId;
  final MatchInfo? match;
  @JsonKey(name: 'iris_template_b64')
  final String? irisTemplateB64;
  @JsonKey(name: 'latency_ms')
  final double latencyMs;
  final String? error;

  const AnalyzeResult({
    required this.frameId,
    required this.deviceId,
    this.match,
    this.irisTemplateB64,
    required this.latencyMs,
    this.error,
  });

  factory AnalyzeResult.fromJson(Map<String, dynamic> json) =>
      _$AnalyzeResultFromJson(json);
  Map<String, dynamic> toJson() => _$AnalyzeResultToJson(this);
}
