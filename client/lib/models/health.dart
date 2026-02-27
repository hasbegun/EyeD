import 'package:json_annotation/json_annotation.dart';

part 'health.g.dart';

@JsonSerializable()
class HealthAlive {
  final bool alive;

  const HealthAlive({required this.alive});

  factory HealthAlive.fromJson(Map<String, dynamic> json) =>
      _$HealthAliveFromJson(json);
  Map<String, dynamic> toJson() => _$HealthAliveToJson(this);
}

@JsonSerializable()
class HealthReady {
  final bool alive;
  final bool ready;
  @JsonKey(name: 'nats_connected')
  final bool natsConnected;
  @JsonKey(name: 'circuit_breaker')
  final String circuitBreaker;
  final String version;

  const HealthReady({
    required this.alive,
    required this.ready,
    required this.natsConnected,
    required this.circuitBreaker,
    required this.version,
  });

  factory HealthReady.fromJson(Map<String, dynamic> json) =>
      _$HealthReadyFromJson(json);
  Map<String, dynamic> toJson() => _$HealthReadyToJson(this);
}

@JsonSerializable()
class EngineHealth {
  final bool alive;
  final bool ready;
  @JsonKey(name: 'pipeline_loaded')
  final bool pipelineLoaded;
  @JsonKey(name: 'nats_connected')
  final bool natsConnected;
  @JsonKey(name: 'gallery_size')
  final int gallerySize;
  @JsonKey(name: 'db_connected')
  final bool dbConnected;
  final String version;

  const EngineHealth({
    required this.alive,
    required this.ready,
    required this.pipelineLoaded,
    required this.natsConnected,
    required this.gallerySize,
    required this.dbConnected,
    required this.version,
  });

  factory EngineHealth.fromJson(Map<String, dynamic> json) =>
      _$EngineHealthFromJson(json);
  Map<String, dynamic> toJson() => _$EngineHealthToJson(this);
}
