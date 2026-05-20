//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/model_return.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_returns200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListReturns200Response {
  /// Returns a new [ListReturns200Response] instance.
  ListReturns200Response({

    required  this.data,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<ModelReturn> data;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListReturns200Response &&
      other.data == data;

    @override
    int get hashCode =>
        data.hashCode;

  factory ListReturns200Response.fromJson(Map<String, dynamic> json) => _$ListReturns200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListReturns200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

