import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

String formatRelativeTime(DateTime? date, {DateTime? clock}) {
  if (date == null) {
    return 'No activity';
  }

  return timeago.format(
    date,
    locale: 'en_short',
    clock: clock ?? DateTime.now(),
  );
}

String formatFullDateTime(DateTime? date) {
  if (date == null) {
    return '—';
  }

  return DateFormat.yMMMd().add_jm().format(date);
}

String formatIntervalLabel(int seconds) {
  if (seconds < 60) {
    return '$seconds sec';
  }
  if (seconds < 3600) {
    final minutes = seconds ~/ 60;
    return '$minutes min';
  }
  final hours = seconds ~/ 3600;
  return '$hours hr';
}

String formatRecentWindowLabel(int minutes) {
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  return '$hours hr';
}

String yesNoLabel(bool? value) {
  return switch (value) {
    true => 'Yes',
    false => 'No',
    null => '—',
  };
}
