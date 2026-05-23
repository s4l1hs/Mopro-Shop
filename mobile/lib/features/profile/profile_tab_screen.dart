import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileTabScreen extends StatelessWidget {
  const ProfileTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('nav.profile'.tr())),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text('address.list_title'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/addresses'),
          ),
        ],
      ),
    );
  }
}
