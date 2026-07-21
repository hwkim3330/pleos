// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'fault_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

FaultData _$FaultDataFromJson(Map<String, dynamic> json) {
  return _FaultData.fromJson(json);
}

/// @nodoc
mixin _$FaultData {
  int get id => throw _privateConstructorUsedError;
  String get target => throw _privateConstructorUsedError;
  int get severity => throw _privateConstructorUsedError;
  String get faultType => throw _privateConstructorUsedError;
  String get cause => throw _privateConstructorUsedError;
  List<String> get countermeasures => throw _privateConstructorUsedError;

  /// Serializes this FaultData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of FaultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FaultDataCopyWith<FaultData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FaultDataCopyWith<$Res> {
  factory $FaultDataCopyWith(FaultData value, $Res Function(FaultData) then) =
      _$FaultDataCopyWithImpl<$Res, FaultData>;
  @useResult
  $Res call({
    int id,
    String target,
    int severity,
    String faultType,
    String cause,
    List<String> countermeasures,
  });
}

/// @nodoc
class _$FaultDataCopyWithImpl<$Res, $Val extends FaultData>
    implements $FaultDataCopyWith<$Res> {
  _$FaultDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FaultData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? target = null,
    Object? severity = null,
    Object? faultType = null,
    Object? cause = null,
    Object? countermeasures = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as int,
            target: null == target
                ? _value.target
                : target // ignore: cast_nullable_to_non_nullable
                      as String,
            severity: null == severity
                ? _value.severity
                : severity // ignore: cast_nullable_to_non_nullable
                      as int,
            faultType: null == faultType
                ? _value.faultType
                : faultType // ignore: cast_nullable_to_non_nullable
                      as String,
            cause: null == cause
                ? _value.cause
                : cause // ignore: cast_nullable_to_non_nullable
                      as String,
            countermeasures: null == countermeasures
                ? _value.countermeasures
                : countermeasures // ignore: cast_nullable_to_non_nullable
                      as List<String>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FaultDataImplCopyWith<$Res>
    implements $FaultDataCopyWith<$Res> {
  factory _$$FaultDataImplCopyWith(
    _$FaultDataImpl value,
    $Res Function(_$FaultDataImpl) then,
  ) = __$$FaultDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int id,
    String target,
    int severity,
    String faultType,
    String cause,
    List<String> countermeasures,
  });
}

/// @nodoc
class __$$FaultDataImplCopyWithImpl<$Res>
    extends _$FaultDataCopyWithImpl<$Res, _$FaultDataImpl>
    implements _$$FaultDataImplCopyWith<$Res> {
  __$$FaultDataImplCopyWithImpl(
    _$FaultDataImpl _value,
    $Res Function(_$FaultDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FaultData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? target = null,
    Object? severity = null,
    Object? faultType = null,
    Object? cause = null,
    Object? countermeasures = null,
  }) {
    return _then(
      _$FaultDataImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as int,
        target: null == target
            ? _value.target
            : target // ignore: cast_nullable_to_non_nullable
                  as String,
        severity: null == severity
            ? _value.severity
            : severity // ignore: cast_nullable_to_non_nullable
                  as int,
        faultType: null == faultType
            ? _value.faultType
            : faultType // ignore: cast_nullable_to_non_nullable
                  as String,
        cause: null == cause
            ? _value.cause
            : cause // ignore: cast_nullable_to_non_nullable
                  as String,
        countermeasures: null == countermeasures
            ? _value._countermeasures
            : countermeasures // ignore: cast_nullable_to_non_nullable
                  as List<String>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$FaultDataImpl implements _FaultData {
  const _$FaultDataImpl({
    required this.id,
    required this.target,
    required this.severity,
    required this.faultType,
    required this.cause,
    required final List<String> countermeasures,
  }) : _countermeasures = countermeasures;

  factory _$FaultDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$FaultDataImplFromJson(json);

  @override
  final int id;
  @override
  final String target;
  @override
  final int severity;
  @override
  final String faultType;
  @override
  final String cause;
  final List<String> _countermeasures;
  @override
  List<String> get countermeasures {
    if (_countermeasures is EqualUnmodifiableListView) return _countermeasures;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_countermeasures);
  }

  @override
  String toString() {
    return 'FaultData(id: $id, target: $target, severity: $severity, faultType: $faultType, cause: $cause, countermeasures: $countermeasures)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FaultDataImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.target, target) || other.target == target) &&
            (identical(other.severity, severity) ||
                other.severity == severity) &&
            (identical(other.faultType, faultType) ||
                other.faultType == faultType) &&
            (identical(other.cause, cause) || other.cause == cause) &&
            const DeepCollectionEquality().equals(
              other._countermeasures,
              _countermeasures,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    target,
    severity,
    faultType,
    cause,
    const DeepCollectionEquality().hash(_countermeasures),
  );

  /// Create a copy of FaultData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FaultDataImplCopyWith<_$FaultDataImpl> get copyWith =>
      __$$FaultDataImplCopyWithImpl<_$FaultDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FaultDataImplToJson(this);
  }
}

abstract class _FaultData implements FaultData {
  const factory _FaultData({
    required final int id,
    required final String target,
    required final int severity,
    required final String faultType,
    required final String cause,
    required final List<String> countermeasures,
  }) = _$FaultDataImpl;

  factory _FaultData.fromJson(Map<String, dynamic> json) =
      _$FaultDataImpl.fromJson;

  @override
  int get id;
  @override
  String get target;
  @override
  int get severity;
  @override
  String get faultType;
  @override
  String get cause;
  @override
  List<String> get countermeasures;

  /// Create a copy of FaultData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FaultDataImplCopyWith<_$FaultDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
