// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signal_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SignalMessage _$SignalMessageFromJson(Map<String, dynamic> json) =>
    SignalMessage(
      type: json['type'] as String,
      deviceId: json['device_id'] as String,
      from: json['from'] as String,
      payload: json['payload'],
    );

Map<String, dynamic> _$SignalMessageToJson(SignalMessage instance) =>
    <String, dynamic>{
      'type': instance.type,
      'device_id': instance.deviceId,
      'from': instance.from,
      'payload': instance.payload,
    };
