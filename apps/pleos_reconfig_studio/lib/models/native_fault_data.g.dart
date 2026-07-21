// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'native_fault_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NativeFaultDataImpl _$$NativeFaultDataImplFromJson(
  Map<String, dynamic> json,
) => _$NativeFaultDataImpl(
  action: (json['action'] as num?)?.toInt() ?? 1,
  id: (json['id'] as num).toInt(),
  target: json['target'] as String?,
  code: (json['code'] as num?)?.toInt(),
  severity: (json['severity'] as num?)?.toInt(),
);

Map<String, dynamic> _$$NativeFaultDataImplToJson(
  _$NativeFaultDataImpl instance,
) => <String, dynamic>{
  'action': instance.action,
  'id': instance.id,
  'target': instance.target,
  'code': instance.code,
  'severity': instance.severity,
};
