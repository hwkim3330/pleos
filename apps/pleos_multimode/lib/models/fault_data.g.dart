// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fault_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$FaultDataImpl _$$FaultDataImplFromJson(Map<String, dynamic> json) =>
    _$FaultDataImpl(
      id: (json['id'] as num).toInt(),
      target: json['target'] as String,
      severity: (json['severity'] as num).toInt(),
      faultType: json['faultType'] as String,
      cause: json['cause'] as String,
      countermeasures: (json['countermeasures'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$$FaultDataImplToJson(_$FaultDataImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'target': instance.target,
      'severity': instance.severity,
      'faultType': instance.faultType,
      'cause': instance.cause,
      'countermeasures': instance.countermeasures,
    };
