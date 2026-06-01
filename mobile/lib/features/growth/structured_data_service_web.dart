import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mopro/features/growth/structured_data_service.dart';
import 'package:web/web.dart' as web;

/// Web impl: writes a single <script type="application/ld+json" id="mopro-jsonld">
/// into the head, replacing any prior payload. Failures never propagate.
class _WebStructuredDataService implements StructuredDataService {
  static const _id = 'mopro-jsonld';

  @override
  void setJsonLd(Map<String, dynamic> data) {
    try {
      final head = web.document.head;
      if (head == null) return;
      final json = jsonEncode(data);
      final existing = head.querySelector('script#$_id');
      if (existing != null) {
        existing.textContent = json;
        return;
      }
      final el = web.document.createElement('script')
        ..setAttribute('type', 'application/ld+json')
        ..id = _id
        ..textContent = json;
      head.appendChild(el);
    } catch (e) {
      if (kDebugMode) debugPrint('StructuredDataService(web): $e');
    }
  }
}

StructuredDataService createStructuredDataService() =>
    _WebStructuredDataService();
