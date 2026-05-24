import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');

    // Stub: in production these would come from a sessions provider
    final sessions = <_Session>[
      _Session(
        device: 'iPhone 15 Pro',
        location: 'İstanbul, TR',
        lastActive: DateTime.now().subtract(const Duration(minutes: 5)),
        isCurrent: true,
      ),
      _Session(
        device: 'MacBook Pro',
        location: 'İstanbul, TR',
        lastActive: DateTime.now().subtract(const Duration(hours: 2)),
        isCurrent: false,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('account.security'.tr())),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'security.active_sessions'.tr(),
              style: theme.textTheme.titleSmall,
            ),
          ),
          ...sessions.map(
            (s) => ListTile(
              leading: Icon(
                s.isCurrent ? Icons.phone_iphone : Icons.computer,
                color: s.isCurrent ? cs.primary : cs.onSurfaceVariant,
              ),
              title: Row(
                children: [
                  Text(s.device),
                  if (s.isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'security.current'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                '${s.location} · ${dateFmt.format(s.lastActive)}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: s.isCurrent
                  ? null
                  : TextButton(
                      onPressed: () {},
                      child: Text(
                        'security.revoke'.tr(),
                        style: TextStyle(color: cs.error),
                      ),
                    ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'security.login_history'.tr(),
              style: theme.textTheme.titleSmall,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

class _Session {
  _Session({
    required this.device,
    required this.location,
    required this.lastActive,
    required this.isCurrent,
  });

  final String device;
  final String location;
  final DateTime lastActive;
  final bool isCurrent;
}
