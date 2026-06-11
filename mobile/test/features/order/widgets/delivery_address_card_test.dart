import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/delivery_address_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(home: Scaffold(body: child)),
    );

const _addr = DeliveryAddressDto(
  label: 'Ev',
  recipientName: 'Ali Veli',
  phone: '+905551112233',
  fullAddress: 'Atatürk Cad. No:1',
  neighborhood: 'Merkez Mah.',
  district: 'Kadıköy',
  city: 'İstanbul',
  postalCode: '34000',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders recipient, street, locality, phone + label', (tester) async {
    await tester.pumpWidget(_wrap(const DeliveryAddressCard(address: _addr)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ali Veli'), findsOneWidget);
    expect(find.text('Atatürk Cad. No:1'), findsOneWidget);
    expect(find.text('Merkez Mah. Kadıköy/İstanbul 34000'), findsOneWidget);
    expect(find.text('+905551112233'), findsOneWidget);
    expect(find.text('Ev'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('omits the label chip when label is empty', (tester) async {
    await tester.pumpWidget(
      _wrap(const DeliveryAddressCard(
        address: DeliveryAddressDto(
          recipientName: 'Ayşe Kaya',
          fullAddress: 'Bağdat Cad. No:2',
          district: 'Maltepe',
          city: 'İstanbul',
        ),
      )),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Ayşe Kaya'), findsOneWidget);
    expect(find.text('Maltepe/İstanbul'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
