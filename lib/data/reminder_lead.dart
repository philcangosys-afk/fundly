/// «وقت التذكير» في المتابعة والتخطيط: كم قبل الموعد يصل التذكير.
///
/// كانت ساعة على الوقت (18:06) لا تعني شيئًا أمام «الوقت» نفسه. الآن مدة
/// قبل الموعد: قبل يوم، قبل 12 ساعة، قبل ساعة، أو مخصص بالساعات أو الأيام.
/// القيمة تُحفظ نصًّا مقروءًا: «قبل يوم»، «قبل 3 ساعة»، «قبل 2 يوم».
const List<String> kReminderLeadOptions = [
  'قبل يوم',
  'قبل 12 ساعة',
  'قبل ساعة',
  'مخصص بالساعات',
  'مخصص بالأيام',
];

const String kLeadCustomHours = 'مخصص بالساعات';
const String kLeadCustomDays = 'مخصص بالأيام';

String _latinDigits(String raw) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var out = raw;
  for (var i = 0; i < arabic.length; i++) {
    out = out.replaceAll(arabic[i], '$i');
  }
  return out;
}

/// القيمة المحفوظة من الخيار والعدد (للمخصص).
String reminderLeadValue(String option, String number) {
  final n = int.tryParse(_latinDigits(number.trim())) ?? 0;
  if (option == kLeadCustomHours) return n > 0 ? 'قبل $n ساعة' : '';
  if (option == kLeadCustomDays) return n > 0 ? 'قبل $n يوم' : '';
  return option;
}

/// تفكيك قيمة محفوظة إلى (الخيار، العدد) لملء النموذج عند التعديل.
/// قيمة قديمة على شكل ساعة (18:06) لا تُقابل خيارًا: ('', '').
(String, String) reminderLeadSplit(String stored) {
  final s = _latinDigits(stored.trim());
  if (s.isEmpty) return ('', '');
  if (kReminderLeadOptions.contains(s)) return (s, '');
  final m = RegExp(r'قبل\s*(\d+)\s*(ساعة|ساعات|يوم|أيام)').firstMatch(s);
  if (m == null) return ('', '');
  final hours = m.group(2)!.startsWith('ساع');
  return (hours ? kLeadCustomHours : kLeadCustomDays, m.group(1)!);
}

/// دقائق التذكير قبل الموعد، و-1 إن لم تكن قيمة مدة.
int reminderLeadMinutes(String raw) {
  final s = _latinDigits(raw.trim());
  if (s.isEmpty) return -1;
  if (s == 'قبل يوم') return 1440;
  if (s == 'قبل ساعة') return 60;
  final m = RegExp(r'قبل\s*(\d+)\s*(ساعة|ساعات|يوم|أيام)').firstMatch(s);
  if (m == null) return -1;
  final n = int.parse(m.group(1)!);
  return m.group(2)!.startsWith('ساع') ? n * 60 : n * 1440;
}
