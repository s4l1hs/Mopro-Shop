//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/address.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_addresses200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListAddresses200Response {
  /// Returns a new [ListAddresses200Response] instance.
  ListAddresses200Response({

    required  this.data,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<Address> data;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListAddresses200Response &&
      other.data == data;

    @override
    int get hashCode =>
        data.hashCode;

  factory ListAddresses200Response.fromJson(Map<String, dynamic> json) => _$ListAddresses200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListAddresses200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

