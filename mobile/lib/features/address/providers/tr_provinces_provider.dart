import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Province {
  const Province({required this.name, required this.districts});

  final String name;
  final List<String> districts;
}

final trProvincesProvider = FutureProvider<List<Province>>((ref) async {
  final raw = await rootBundle.loadString('assets/data/tr_provinces.json');
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => e as Map<String, dynamic>)
      .map((e) => Province(
            name: e['il'] as String,
            districts: List<String>.from(e['ilceler'] as List),
          ),)
      .toList();
});
