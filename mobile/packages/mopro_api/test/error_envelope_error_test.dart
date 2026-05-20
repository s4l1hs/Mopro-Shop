import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';

// tests for ErrorEnvelopeError
void main() {
  final ErrorEnvelopeError? instance = /* ErrorEnvelopeError(...) */ null;
  // TODO add properties to the entity

  group(ErrorEnvelopeError, () {
    // Machine-readable error slug
    // String code
    test('to test the property `code`', () async {
      // TODO
    });

    // Human-readable error message (locale from Accept-Language)
    // String message
    test('to test the property `message`', () async {
      // TODO
    });

    // Request trace ID. Echoes X-Trace-Id or server-generated UUID.
    // String traceId
    test('to test the property `traceId`', () async {
      // TODO
    });

    // Per-field validation errors. Present only for 422 responses.
    // List<FieldError> fields
    test('to test the property `fields`', () async {
      // TODO
    });

  });
}
