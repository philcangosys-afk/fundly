// أدوات مطابقة البحث العربية المشتركة بين كل شاشات التطبيق.
//
// وُضعت في ملف مستقل (بدل بقائها داخل module_shared_widgets.dart) حتى
// يستطيع management_dashboard_chrome.dart استخدامها دون استيراد دائري،
// لأن module_shared_widgets.dart يستورد management_dashboard_chrome.dart.

/// يوحّد النص للمقارنة: يزيل التشكيل وفروق الهمزات والتاء المربوطة
/// والألف المقصورة، حتى يطابق "احمد" الاسمَ "أحمد" و"فاطمه" الاسمَ "فاطمة".
String normalizeForSearch(String input) {
  var value = input.toLowerCase().trim();
  if (value.isEmpty) return '';
  value = value
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');

  // إزالة التشكيل (بما فيه الألف الخنجرية وعلامات الضبط) والتطويل.
  value = value.replaceAll(RegExp(r'[\u064B-\u0655\u0670\u0640]'), '');

  // توحيد الأرقام العربية‑الهندية (١٢٣) مع الأرقام اللاتينية (123) حتى
  // يتطابق البحث برقم مكتوب بأي من الصيغتين.
  const arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < arabicIndicDigits.length; i++) {
    value = value.replaceAll(arabicIndicDigits[i], '$i');
  }

  value = value.replaceAll(RegExp(r'[^0-9a-zA-Z؀-ۿ\s]+'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value;
}

List<String> tokenizeSearchQuery(String query) {
  final normalized = normalizeForSearch(query);
  if (normalized.isEmpty) return const [];
  return normalized
      .split(' ')
      .where((token) => token.length >= 2 || int.tryParse(token) != null)
      .toList(growable: false);
}

bool matchesSearchQuery({
  required String query,
  required Iterable<String> fields,
}) {
  final haystack = normalizeForSearch(fields.join(' '));
  final tokens = tokenizeSearchQuery(query);
  if (tokens.isEmpty) {
    // استعلام أقصر من حدّ التقطيع (حرف واحد مثلًا): يُطابَق كاحتواء بسيط
    // بدل إرجاع false الذي كان يُخفي كل النتائج بمجرد كتابة أول حرف.
    final needle = normalizeForSearch(query);
    if (needle.isEmpty) return true;
    return haystack.contains(needle);
  }

  final words = haystack.split(' ');

  return tokens.every((token) {
    return words.any(
      (word) =>
          word == token ||
          word.startsWith(token) ||
          (token.length >= 3 && word.contains(token)),
    );
  });
}

/// أقل عدد حروف يبدأ عنده ظهور الاقتراحات في كل خانات البحث بالتطبيق.
const int kSearchSuggestionMinChars = 2;

/// يبني قائمة اقتراحات الإكمال لخانة بحث.
///
/// يعمل بمجرد كتابة حرفين ([kSearchSuggestionMinChars])، ويطابق بالنص
/// المُوحَّد عربيًا لا بالنص الخام — فكتابة "اح" تقترح "أحمد". الترتيب
/// بالأولوية: ما يبدأ بالكلمة المكتوبة أولًا، ثم ما يبدأ به أحد مقاطعه،
/// ثم ما يحتويها في أي موضع. تُحذف التكرارات والقيمة المطابقة تمامًا لما
/// كُتب (لأن اقتراحها لا يضيف شيئًا).
List<String> searchSuggestionsFor({
  required String query,
  required Iterable<String> candidates,
  int limit = 5,
}) {
  final rawQuery = query.trim();
  if (rawQuery.length < kSearchSuggestionMinChars) return const [];
  final needle = normalizeForSearch(rawQuery);
  if (needle.isEmpty) return const [];

  final startsWith = <String>[];
  final wordStartsWith = <String>[];
  final contains = <String>[];
  final seen = <String>{};

  for (final candidate in candidates) {
    final value = candidate.trim();
    if (value.isEmpty) continue;
    final normalized = normalizeForSearch(value);
    if (normalized.isEmpty || normalized == needle) continue;
    if (!seen.add(normalized)) continue;

    if (normalized.startsWith(needle)) {
      startsWith.add(value);
    } else if (normalized.split(' ').any((word) => word.startsWith(needle))) {
      wordStartsWith.add(value);
    } else if (normalized.contains(needle)) {
      contains.add(value);
    }
  }

  return [
    ...startsWith,
    ...wordStartsWith,
    ...contains,
  ].take(limit).toList(growable: false);
}
