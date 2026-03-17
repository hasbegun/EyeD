// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HealthAlive _$HealthAliveFromJson(Map<String, dynamic> json) =>
    HealthAlive(alive: json['alive'] as bool);

Map<String, dynamic> _$HealthAliveToJson(HealthAlive instance) =>
    <String, dynamic>{'alive': instance.alive};

HealthReady _$HealthReadyFromJson(Map<String, dynamic> json) => HealthReady(
  alive: json['alive'] as bool,
  ready: json['ready'] as bool,
  natsConnected: json['nats_connected'] as bool,
  circuitBreaker: json['circuit_breaker'] as String,
  version: json['version'] as String,
);

Map<String, dynamic> _$HealthReadyToJson(HealthReady instance) =>
    <String, dynamic>{
      'alive': instance.alive,
      'ready': instance.ready,
      'nats_connected': instance.natsConnected,
      'circuit_breaker': instance.circuitBreaker,
      'version': instance.version,
    };

EngineHealth _$EngineHealthFromJson(Map<String, dynamic> json) => EngineHealth(
  alive: json['alive'] as bool,
  ready: json['ready'] as bool,
  pipelineLoaded: json['pipeline_loaded'] as bool,
  natsConnected: json['nats_connected'] as bool,
  gallerySize: (json['gallery_size'] as num).toInt(),
  dbConnected: json['db_connected'] as bool,
  version: json['version'] as String,
);

Map<String, dynamic> _$EngineHealthToJson(EngineHealth instance) =>
    <String, dynamic>{
      'alive': instance.alive,
      'ready': instance.ready,
      'pipeline_loaded': instance.pipelineLoaded,
      'nats_connected': instance.natsConnected,
      'gallery_size': instance.gallerySize,
      'db_connected': instance.dbConnected,
      'version': instance.version,
    };
