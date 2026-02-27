import 'package:json_annotation/json_annotation.dart';

part 'signal_message.g.dart';

@JsonSerializable()
class SignalMessage {
  final String type;
  @JsonKey(name: 'device_id')
  final String deviceId;
  final String from;
  final dynamic payload;

  const SignalMessage({
    required this.type,
    required this.deviceId,
    required this.from,
    this.payload,
  });

  factory SignalMessage.fromJson(Map<String, dynamic> json) =>
      _$SignalMessageFromJson(json);
  Map<String, dynamic> toJson() => _$SignalMessageToJson(this);
}
