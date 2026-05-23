import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/address/widgets/address_card.dart';
import 'package:mopro_api/mopro_api.dart';

Address _addr({bool isDefault = false}) => Address(
      id: 1,
      label: 'Ev',
      name: 'Ali Veli',
      phone: '+905321234567',
      city: 'İstanbul',
      district: 'Kadıköy',
      fullAddress: 'Test Cad. No:1 Daire:5',
      isDefault: isDefault,
    );

Widget _wrap(Address a, {VoidCallback? onEdit, VoidCallback? onDelete}) =>
    MaterialApp(
      home: Scaffold(
        body: AddressCard(
          address: a,
          onEdit: onEdit ?? () {},
          onDelete: onDelete ?? () {},
        ),
      ),
    );

void main() {
  testWidgets('AddressCard shows label, name, and city/district',
      (tester) async {
    await tester.pumpWidget(_wrap(_addr()));
    expect(find.text('Ev'), findsOneWidget);
    expect(find.text('Ali Veli'), findsOneWidget);
    expect(find.textContaining('Kadıköy'), findsOneWidget);
  });

  testWidgets('AddressCard calls onEdit callback', (tester) async {
    bool edited = false;
    await tester.pumpWidget(_wrap(_addr(), onEdit: () => edited = true));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    expect(edited, isTrue);
  });

  testWidgets('AddressCard calls onDelete callback', (tester) async {
    bool deleted = false;
    await tester.pumpWidget(_wrap(_addr(), onDelete: () => deleted = true));
    await tester.tap(find.byIcon(Icons.delete_outline));
    expect(deleted, isTrue);
  });
}
