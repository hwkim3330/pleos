// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'native_fault_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

NativeFaultData _$NativeFaultDataFromJson(Map<String, dynamic> json) {
  return _NativeFaultData.fromJson(json);
}

/// @nodoc
mixin _$NativeFaultData {
  int get action => throw _privateConstructorUsedError;
  int get id => throw _privateConstructorUsedError;
  String? get target => throw _privateConstructorUsedError;
  int? get code => throw _privateConstructorUsedError;
  int? get severity => throw _privateConstructorUsedError;

  /// Serializes this NativeFaultData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NativeFaultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NativeFaultDataCopyWith<NativeFaultData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NativeFaultDataCopyWith<$Res> {
  factory $NativeFaultDataCopyWith(
    NativeFaultData value,
    $Res Function(NativeFaultData) then,
  ) = _$NativeFaultDataCopyWithImpl<$Res, NativeFaultData>;
  @useResult
  $Res call({int action, int id, String? target, int? code, int? severity});
}

/// @nodoc
class _$NativeFaultDataCopyWithImpl<$Res, $Val extends NativeFaultData>
    implements $NativeFaultDataCopyWith<$Res> {
  _$NativeFaultDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NativeFaultData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? action = null,
    Object? id = null,
    Object? target = freezed,
    Object? code = freezed,
    Object? severity = freezed,
  }) {
    return _then(
      _value.copyWith(
            action: null == action
                ? _value.action
                : action // ignore: cast_nullable_to_non_nullable
                      as int,
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            target: freezed == target
                ? _value.target
                : target // ignore: cast_nullable_to_non_nullable
                      as String?,
            code: freezed == code
                ? _value.code
                : code // ignore: cast_nullable_to_non_nullable
                      as int?,
            severity: freezed == severity
                ? _value.severity
                : severity // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$NativeFaultDataImplCopyWith<$Res>
    implements $NativeFaultDataCopyWith<$Res> {
  factory _$$NativeFaultDataImplCopyWith(
    _$NativeFaultDataImpl value,
    $Res Function(_$NativeFaultDataImpl) then,
  ) = __$$NativeFaultDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int action, int id, String? target, int? code, int? severity});
}

/// @nodoc
class __$$NativeFaultDataImplCopyWithImpl<$Res>
    extends _$NativeFaultDataCopyWithImpl<$Res, _$NativeFaultDataImpl>
    implements _$$NativeFaultDataImplCopyWith<$Res> {
  __$$NativeFaultDataImplCopyWithImpl(
    _$NativeFaultDataImpl _value,
    $Res Function(_$NativeFaultDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of NativeFaultData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? action = null,
    Object? id = null,
    Object? target = freezed,
    Object? code = freezed,
    Object? severity = freezed,
  }) {
    return _then(
      _$NativeFaultDataImpl(
        action: null == action
            ? _value.action
            : action // ignore: cast_nullable_to_non_nullable
                  as int,
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        target: freezed == target
            ? _value.target
            : target // ignore: cast_nullable_to_non_nullable
                  as String?,
        code: freezed == code
            ? _value.code
            : code // ignore: cast_nullable_to_non_nullable
                  as int?,
        severity: freezed == severity
            ? _value.severity
            : severity // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$NativeFaultDataImpl implements _NativeFaultData {
  const _$NativeFaultDataImpl({
    this.action = 1,
    required this.id,
    this.target,
    this.code,
    this.severity,
  });

  factory _$NativeFaultDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$NativeFaultDataImplFromJson(json);

  @override
  @JsonKey()
  final int action;
  @override
  final int id;
  @override
  final String? target;
  @override
  final int? code;
  @override
  final int? severity;

  @override
  String toString() {
    return 'NativeFaultData(action: $action, id: $id, target: $target, code: $code, severity: $severity)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NativeFaultDataImpl &&
            (identical(other.action, action) || other.action == action) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.target, target) || other.target == target) &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.severity, severity) ||
                other.severity == severity));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, action, id, target, code, severity);

  /// Create a copy of NativeFaultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NativeFaultDataImplCopyWith<_$NativeFaultDataImpl> get copyWith =>
      __$$NativeFaultDataImplCopyWithImpl<_$NativeFaultDataImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$NativeFaultDataImplToJson(this);
  }
}

abstract class _NativeFaultData implements NativeFaultData {
  const factory _NativeFaultData({
    final int action,
    required final int id,
    final String? target,
    final int? code,
    final int? severity,
  }) = _$NativeFaultDataImpl;

  factory _NativeFaultData.fromJson(Map<String, dynamic> json) =
      _$NativeFaultDataImpl.fromJson;

  @override
  int get action;
  @override
  int get id;
  @override
  String? get target;
  @override
  int? get code;
  @override
  int? get severity;

  /// Create a copy of NativeFaultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NativeFaultDataImplCopyWith<_$NativeFaultDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
