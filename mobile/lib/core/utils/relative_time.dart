import 'package:easy_localization/easy_localization.dart';

/// Localized relative time: "az önce", "3 dakika önce", "2 saat önce", "dün",
/// "3 gün önce", or `dd.MM.yyyy` for anything older than 7 days. [now] is
/// injectable for deterministic tests.
String relativeTime(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final d = ref.difference(when.toLocal());

  if (d.inSeconds < 60) return 'time.just_now'.tr();
  if (d.inMinutes < 60) return 'time.minutes_ago'.tr(args: ['${d.inMinutes}']);
  if (d.inHours < 24) return 'time.hours_ago'.tr(args: ['${d.inHours}']);
  if (d.inDays == 1) return 'time.yesterday'.tr();
  if (d.inDays <= 7) return 'time.days_ago'.tr(args: ['${d.inDays}']);
  return DateFormat('dd.MM.yyyy').format(when.toLocal());
}
