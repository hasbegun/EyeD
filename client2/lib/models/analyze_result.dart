class MatchInfo {
  final double hammingDistance;
  final bool isMatch;
  final String? matchedIdentityId;
  final String? matchedIdentityName;

  const MatchInfo({
    required this.hammingDistance,
    required this.isMatch,
    this.matchedIdentityId,
    this.matchedIdentityName,
  });

  factory MatchInfo.fromJson(Map<String, dynamic> json) => MatchInfo(
        hammingDistance: (json['hamming_distance'] as num).toDouble(),
        isMatch: json['is_match'] as bool,
        matchedIdentityId: json['matched_identity_id'] as String?,
        matchedIdentityName: json['matched_identity_name'] as String?,
      );
}

class AnalyzeResponse {
  final MatchInfo? match;
  final String? error;
  final double latencyMs;

  const AnalyzeResponse({
    this.match,
    this.error,
    required this.latencyMs,
  });

  factory AnalyzeResponse.fromJson(Map<String, dynamic> json) =>
      AnalyzeResponse(
        match: json['match'] != null
            ? MatchInfo.fromJson(json['match'] as Map<String, dynamic>)
            : null,
        error: json['error'] as String?,
        latencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0,
      );
}
