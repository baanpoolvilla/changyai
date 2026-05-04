import 'package:intl/intl.dart';

const Duration _thaiOffset = Duration(hours: 7);

DateTime thaiNow() => DateTime.now().toUtc().add(_thaiOffset);

DateTime parseServerTimestampToThai(String value) {
  final parsed = DateTime.parse(value);
  return parsed.toUtc().add(_thaiOffset);
}

String formatThaiDate(DateTime value) {
  return DateFormat('d/M/yyyy').format(value);
}

String formatThaiDateTime(DateTime value) {
  return DateFormat('d/M/yyyy HH:mm').format(value);
}

String thaiDateForDb([DateTime? value]) {
  return DateFormat('yyyy-MM-dd').format(value ?? thaiNow());
}