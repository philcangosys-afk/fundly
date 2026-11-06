import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_language.dart';
import 'app_settings.dart';
import 'lease_contract_data.dart';
import 'user_logo_store.dart';
import 'user_signature_store.dart';
import 'user_stamp_store.dart';

/// طباعة قوالب المستندات والعقود: ورقة A4 احترافية (الشعار، رقم المستند،
/// التاريخ ميلادي وهجري، أقسام مرقّمة بجداول وأعمدة، التوقيع والختم).
/// تُرسم مباشرة بمكتبة PDF داخل التطبيق (بلا متصفح)، والخانة الفارغة لا
/// تُطبع.

// ============================================================
// أدوات عامة
// ============================================================

const _arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

String _tr(String text) => AppTr.tr(text);

String _arNum(int value) => AppTr.isEnglish
    ? '$value'
    : value.toString().split('').map((d) => _arDigits[int.parse(d)]).join();

/// رقم من نص (يقبل الأرقام العربية والفواصل).
double printNum(String raw) {
  var text = raw.trim();
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(_arDigits[i], '$i');
  }
  text = text.replaceAll('٫', '.').replaceAll(RegExp(r'[^0-9.\-]'), '');
  return double.tryParse(text) ?? 0;
}

/// 12,345.50
String printMoney(double value) {
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  return '${value < 0 ? '-' : ''}$out.${parts[1]}';
}

String _dmy(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

DateTime? _parseDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  final parts = text.split(RegExp(r'[/\-.]'));
  if (parts.length != 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2]);
  if (a == null || b == null || c == null) return null;
  return parts[0].length == 4 ? DateTime(a, b, c) : DateTime(c, b, a);
}

/// تاريخ للعرض: «2026-10-13» يصير «13/10/2026».
String _showDate(String raw) {
  final date = DateTime.tryParse(raw.trim());
  return date == null ? raw.trim() : _dmy(date);
}

/// التاريخ الهجري (حساب تقريبي قد يختلف يومًا عن تقويم أم القرى).
String printHijri(DateTime date) {
  final d = date.subtract(const Duration(days: 1));
  var m = d.month;
  var y = d.year;
  if (m < 3) {
    y -= 1;
    m += 12;
  }
  final a = (y / 100).floor();
  final b = 2 - a + (a / 4).floor();
  final jd =
      (365.25 * (y + 4716)).floor() +
      (30.6001 * (m + 1)).floor() +
      d.day +
      b -
      1524;
  const iyear = 10631.0 / 30.0;
  const epochAstro = 1948084;
  const shift1 = 8.01 / 60.0;
  var z = jd - epochAstro;
  final cyc = (z / 10631).floor();
  z = z - 10631 * cyc;
  final j = ((z - shift1) / iyear).floor();
  final iy = 30 * cyc + j;
  z = z - (j * iyear + shift1).floor();
  var im = ((z + 28.5001) / 29.5).floor();
  if (im == 13) im = 12;
  final id = z - (29.5001 * im - 29).floor();
  return '${id.toString().padLeft(2, '0')}/${im.toString().padLeft(2, '0')}/$iy';
}

/// رمز الفاتورة بصيغة هيئة الزكاة (TLV: البائع، الرقم الضريبي، الوقت،
/// الإجمالي، الضريبة) بترميز Base64.
String zatcaQrPayload({
  required String seller,
  required String vatNo,
  required DateTime time,
  required double total,
  required double vat,
}) {
  final bytes = <int>[];
  void tag(int id, String value) {
    final encoded = utf8.encode(value);
    bytes
      ..add(id)
      ..add(encoded.length > 255 ? 255 : encoded.length)
      ..addAll(encoded.length > 255 ? encoded.sublist(0, 255) : encoded);
  }

  tag(1, seller);
  tag(2, vatNo);
  tag(3, time.toUtc().toIso8601String());
  tag(4, total.toStringAsFixed(2));
  tag(5, vat.toStringAsFixed(2));
  return base64Encode(bytes);
}

/// صفوف حقل جدول (JSON) — كل صف: العمود ← القيمة.
List<Map<String, String>> printRows(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final row in decoded.whereType<Map>())
        {for (final e in row.entries) '${e.key}': '${e.value ?? ''}'.trim()},
    ]
        .where(
          (row) => row.entries.any(
            (e) => !e.key.startsWith('__') && e.value.isNotEmpty,
          ),
        )
        .toList();
  } catch (_) {
    return const [];
  }
}

/// التوقيع المرسوم ← صورة SVG بنفس خطوطه.
String _signatureSvg(List<List<Offset>> strokes) {
  if (strokes.isEmpty) return '';
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final stroke in strokes) {
    for (final p in stroke) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
  }
  final w = (maxX - minX) < 1 ? 1.0 : (maxX - minX);
  final h = (maxY - minY) < 1 ? 1.0 : (maxY - minY);
  final path = StringBuffer();
  for (final stroke in strokes) {
    for (var i = 0; i < stroke.length; i++) {
      final p = stroke[i];
      path.write(
        '${i == 0 ? 'M' : 'L'}${(p.dx - minX).toStringAsFixed(1)} '
        '${(p.dy - minY).toStringAsFixed(1)} ',
      );
    }
  }
  final width = (w > h ? w : h) / 70;
  return '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="-6 -6 ${(w + 12).toStringAsFixed(1)} ${(h + 12).toStringAsFixed(1)}">'
      '<path d="$path" fill="none" stroke="#0F2420" '
      'stroke-width="${width.toStringAsFixed(2)}" stroke-linecap="round" '
      'stroke-linejoin="round"/></svg>';
}

// ============================================================
// الألوان والخطوط
// ============================================================

const _deep = PdfColor.fromInt(0xFF0A5A50);
const _gold = PdfColor.fromInt(0xFFC9A24A);
const _goldText = PdfColor.fromInt(0xFF9A8040);
const _ink = PdfColor.fromInt(0xFF16302B);
const _title = PdfColor.fromInt(0xFF0F2420);
const _muted = PdfColor.fromInt(0xFF5C6B68);
const _faint = PdfColor.fromInt(0xFF7B918C);
const _line = PdfColor.fromInt(0xFFD6E2E0);
const _rowLine = PdfColor.fromInt(0xFFE6EEEC);
const _soft = PdfColor.fromInt(0xFFF6FAF9);
const _softer = PdfColor.fromInt(0xFFF4F8F7);
const _cream = PdfColor.fromInt(0xFFFBF6EA);
const _creamBg = PdfColor.fromInt(0xFFFFFBF1);
const _red = PdfColor.fromInt(0xFFC4392E);
const _redDark = PdfColor.fromInt(0xFF8E2A22);
const _redSoft = PdfColor.fromInt(0xFFFFF8F7);
const _redLine = PdfColor.fromInt(0xFFE9B7B1);
const _redBg = PdfColor.fromInt(0xFFFBF1EF);
const _white = PdfColors.white;

pw.Font? _fontRegular;
pw.Font? _fontBold;

Future<void> _loadFonts() async {
  _fontRegular ??= pw.Font.ttf(
    await rootBundle.load('assets/fonts/CairoRegular.ttf'),
  );
  _fontBold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/CairoBold.ttf'));
}

pw.TextStyle _st({
  double size = 9,
  bool bold = false,
  PdfColor color = _ink,
}) => pw.TextStyle(
  fontSize: size,
  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  color: color,
  lineSpacing: 1.5,
);

/// التشكيل (فوق الهمزة خاصة) يُسقط تشكيل سطور PDF العربية ويرمي
/// «RangeError (length)» فلا يُطبع المستند كله (عقد ملغى من السجل
/// التاريخي مثلًا). يُحذف من كل نص يُطبع — المعنى لا يتغير.
String _noHarakat(String value) =>
    value.replaceAll(RegExp('[\u064B-\u0652\u0670]'), '');

pw.Widget _text(
  String text, {
  double size = 9,
  bool bold = false,
  PdfColor color = _ink,
  pw.TextAlign? align,
  int? maxLines,
}) => pw.Text(
  _noHarakat(text),
  style: _st(size: size, bold: bold, color: color),
  textAlign: align,
  maxLines: maxLines,
);

// ============================================================
// عناصر الصفحة (كل دالة تعيد عناصر مستقلة لتنقسم الصفحات بينها)
// ============================================================

class _Doc {
  int _section = 0;

  /// عنوان قسم مرقّم ثم محتواه — لا يظهر إن كان المحتوى فارغًا.
  List<pw.Widget> section(
    String title,
    List<pw.Widget> content, {
    bool numbered = true,
  }) {
    if (content.isEmpty) return const [];
    final num = numbered ? _arNum(++_section) : '';
    return [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
        child: pw.Row(
          children: [
            if (num.isNotEmpty) ...[
              pw.Container(
                width: 15,
                height: 15,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(
                  color: _deep,
                  shape: pw.BoxShape.circle,
                ),
                child: _text(num, size: 7.5, bold: true, color: _white),
              ),
              pw.SizedBox(width: 6),
            ],
            _text(_tr(title), size: 10.5, bold: true, color: _deep),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Container(height: 0.7, color: _line)),
          ],
        ),
      ),
      ...content,
    ];
  }

  /// أزواج «العنوان: القيمة» في أعمدة — الفارغ لا يظهر، والطويل سطر كامل.
  List<pw.Widget> kv(List<(String, String)> pairs, {int cols = 3}) {
    final filled = [
      for (final pair in pairs)
        if (pair.$2.trim().isNotEmpty) pair,
    ];
    if (filled.isEmpty) return const [];
    final short = filled.where((p) => p.$2.trim().length <= 48).toList();
    final long = filled.where((p) => p.$2.trim().length > 48).toList();
    final out = <pw.Widget>[];
    if (short.isNotEmpty) {
      final c = short.length < cols ? (short.length == 1 ? 2 : short.length) : cols;
      final rows = <pw.Widget>[];
      for (var i = 0; i < short.length; i += c) {
        final cells = <pw.Widget>[];
        for (var k = 0; k < c; k++) {
          final index = i + k;
          cells.add(
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: index >= short.length
                    ? pw.SizedBox()
                    : pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _text(_tr(short[index].$1), size: 7.8, color: _muted),
                          pw.SizedBox(width: 5),
                          pw.Expanded(
                            child: _text(
                              short[index].$2.trim(),
                              size: 8.3,
                              bold: true,
                              align: AppTr.isEnglish
                                  ? pw.TextAlign.right
                                  : pw.TextAlign.left,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        }
        rows.add(
          pw.Container(
            decoration: i == 0
                ? null
                : const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: _rowLine, width: 0.6),
                    ),
                  ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: cells,
            ),
          ),
        );
      }
      out.add(
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(children: rows),
        ),
      );
    }
    for (final p in long) {
      out.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _text(_tr(p.$1), size: 7.8, color: _muted),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _text(p.$2.trim(), size: 8.5, bold: true)),
            ],
          ),
        ),
      );
    }
    return out;
  }

  /// جدول: رأس أخضر، أسطر متناوبة، وسطر إجمالي. كل سطر عنصر مستقل.
  List<pw.Widget> table(
    List<String> heads,
    List<List<String>> rows, {
    List<String>? foot,
    Set<int> numeric = const {},
  }) {
    if (rows.isEmpty) return const [];
    int flexOf(int i) => heads[i] == '#'
        ? 1
        : numeric.contains(i)
        ? 3
        : 4;
    pw.Widget line(
      List<String> cells, {
      PdfColor? bg,
      bool head = false,
      bool bold = false,
      bool top = false,
    }) => pw.Container(
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border(
          left: const pw.BorderSide(color: _line, width: 0.6),
          right: const pw.BorderSide(color: _line, width: 0.6),
          bottom: const pw.BorderSide(color: _rowLine, width: 0.6),
          top: top
              ? const pw.BorderSide(color: _gold, width: 1)
              : pw.BorderSide.none,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            pw.Expanded(
              flex: flexOf(i),
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                child: _text(
                  head || bold ? _tr(cells[i]) : cells[i],
                  size: head ? 7.8 : 8,
                  bold: head || bold,
                  color: head ? _white : _ink,
                ),
              ),
            ),
        ],
      ),
    );
    return [
      pw.SizedBox(height: 3),
      line(heads, bg: _deep, head: true),
      for (var r = 0; r < rows.length; r++)
        line(rows[r], bg: r.isOdd ? _soft : null),
      if (foot != null) line(foot, bg: _cream, bold: true, top: true),
    ];
  }

  List<pw.Widget> para(String text, {bool lead = false}) => text.trim().isEmpty
      ? const []
      : [
          pw.SizedBox(height: 4),
          pw.Text(
            _noHarakat(text.trim()),
            textAlign: pw.TextAlign.justify,
            style: _st(size: lead ? 9.5 : 9, color: _ink),
          ),
          pw.SizedBox(height: 6),
        ];

  List<pw.Widget> clauses(List<String> items) {
    if (items.isEmpty) return const [];
    const ordinals = [
      'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع',
      'الثامن', 'التاسع', 'العاشر', 'الحادي عشر', 'الثاني عشر',
      'الثالث عشر', 'الرابع عشر', 'الخامس عشر',
    ];
    return [
      for (var i = 0; i < items.length; i++)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _rowLine, width: 0.6),
            ),
          ),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: _noHarakat(i < ordinals.length
                      ? '${_tr('البند')} ${_tr(ordinals[i])}: '
                      : '${_tr('البند')} ${i + 1}: '),
                  style: _st(size: 9, bold: true, color: _deep),
                ),
                pw.TextSpan(text: _noHarakat(items[i]), style: _st(size: 9)),
              ],
            ),
          ),
        ),
    ];
  }

  List<pw.Widget> kpis(List<(String, String, String, bool)> items) => [
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
      child: pw.Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(
                  color: items[i].$4 ? _deep : null,
                  border: pw.Border.all(
                    color: items[i].$4 ? _deep : _line,
                    width: 0.8,
                  ),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _text(
                      _tr(items[i].$1),
                      size: 7.5,
                      color: items[i].$4 ? _white : _muted,
                    ),
                    _text(
                      items[i].$2,
                      size: 12.5,
                      bold: true,
                      color: items[i].$4 ? _white : _title,
                    ),
                    _text(
                      items[i].$3,
                      size: 7,
                      color: items[i].$4 ? _white : _faint,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  ];

  List<pw.Widget> note(String text) => text.trim().isEmpty
      ? const []
      : [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _soft,
              border: const pw.Border(
                right: pw.BorderSide(color: _gold, width: 2.5),
              ),
            ),
            child: _text(text.trim(), size: 8.3, color: _muted),
          ),
        ];
}

/// التوقيعات: صندوق لكل طرف؛ صندوق صاحب الحساب فيه توقيعه وختمه.
List<pw.Widget> _signatures(
  List<(String, String)> signers, {
  int userIndex = 0,
  String signatureSvg = '',
  Uint8List? stamp,
  List<(String, String)> witnesses = const [],
}) {
  if (signers.isEmpty) return const [];
  final boxes = <pw.Widget>[];
  for (var i = 0; i < signers.length; i++) {
    final mine = i == userIndex;
    if (i > 0) boxes.add(pw.SizedBox(width: 10));
    boxes.add(
      pw.Expanded(
        child: pw.Container(
          height: 92,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.8),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _text(_tr(signers[i].$1), size: 7.5, bold: true, color: _goldText),
                    _text(signers[i].$2, size: 9.5, bold: true, maxLines: 2),
                    pw.Spacer(),
                    if (mine && signatureSvg.isNotEmpty)
                      pw.SizedBox(
                        height: 30,
                        child: pw.SvgImage(svg: signatureSvg),
                      ),
                    pw.Container(height: 0.7, color: _faint),
                    _text(_tr('التوقيع'), size: 7, color: _faint),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                width: 62,
                alignment: pw.Alignment.center,
                child: mine && stamp != null
                    ? pw.Image(pw.MemoryImage(stamp), fit: pw.BoxFit.contain)
                    : pw.Container(
                        width: 58,
                        height: 58,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(
                            color: const PdfColor.fromInt(0xFFB9CBC7),
                            width: 0.8,
                          ),
                        ),
                        child: _text(_tr('الختم'), size: 7, color: _faint),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  final out = <pw.Widget>[
    pw.SizedBox(height: 14),
    pw.Row(children: boxes),
  ];
  final filled = witnesses.where((w) => w.$2.trim().isNotEmpty).toList();
  if (filled.isNotEmpty) {
    out.add(pw.SizedBox(height: 10));
    out.add(
      pw.Row(
        children: [
          for (var i = 0; i < filled.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: _noHarakat('${_tr(filled[i].$1)}: '),
                          style: _st(size: 8.5, color: _muted),
                        ),
                        pw.TextSpan(
                          text: _noHarakat(filled[i].$2),
                          style: _st(size: 8.5, bold: true),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Container(height: 0.7, color: _faint),
                  _text(_tr('التوقيع'), size: 7, color: _faint),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  return out;
}

pw.Widget _signedNote(String text) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 10),
  padding: const pw.EdgeInsets.all(6),
  alignment: pw.Alignment.center,
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _gold, width: 0.7),
    borderRadius: pw.BorderRadius.circular(6),
  ),
  child: _text(_tr(text), size: 8.3, color: _muted, align: pw.TextAlign.center),
);

/// بيانات الرأس: العنوان ورقم المستند والتاريخ.
class _Page {
  _Page({
    required this.title,
    required this.subtitle,
    required this.docNo,
    required this.date,
    this.metaExtra = const [],
    this.warn = false,
    this.letterhead = true,
  });

  final String title;
  final String subtitle;
  final String docNo;
  final DateTime date;
  final List<(String, String)> metaExtra;
  final bool warn;

  /// ترويسة Fundly: الشعار والاسم وجدول رقم المستند والتاريخ والشريط
  /// الملوّن والتذييل. بدونها مستند أبيض بالعنوان والمحتوى ورقم الصفحة.
  final bool letterhead;
}

/// الصفحة كاملة: الرأس في الصفحة الأولى، والتذييل برقم الصفحة في كل صفحة.
Future<Uint8List> _render(
  _Page page,
  List<pw.Widget> body,
  PdfPageFormat format,
) async {
  await _loadFonts();
  final logo = await UserLogoStore.load();
  final settings = AppSettings.instance;
  final rtl = !AppTr.isEnglish;
  final orgLines = [
    [settings.city, settings.phone].where((v) => v.trim().isNotEmpty).join(' · '),
    settings.email,
  ].where((v) => v.trim().isNotEmpty).toList();
  final meta = <(String, String)>[
    ('رقم المستند', page.docNo.isEmpty ? '—' : page.docNo),
    ('التاريخ', '${_dmy(page.date)} ${_tr('م')}'),
    ('الموافق', '${printHijri(page.date)} ${_tr('هـ')}'),
    ...page.metaExtra.where((m) => m.$2.trim().isNotEmpty),
  ];
  final accent = page.warn ? _red : _deep;
  final issuedOn = _dmy(DateTime.now());

  final header = <pw.Widget>[
    if (page.letterhead) ...[
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 52,
            height: 52,
            child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 8),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _text(settings.name, size: 13, bold: true, color: _deep),
              for (final line in orgLines) _text(line, size: 8, color: _muted),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Container(
          width: 170,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              for (var i = 0; i < meta.length; i++)
                pw.Container(
                  color: i.isEven ? _softer : null,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  child: pw.Row(
                    children: [
                      _text(_tr(meta[i].$1), size: 7.8, color: _muted),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: _text(
                          meta[i].$2,
                          size: 8.2,
                          bold: true,
                          align: rtl ? pw.TextAlign.left : pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 8),
    pw.Container(height: 1.2, color: accent),
    pw.SizedBox(height: 10),
    ],
    pw.Center(child: _text(_tr(page.title), size: 18, bold: true, color: _title)),
    if (!page.letterhead)
      pw.Center(
        child: _text(
          '${_dmy(page.date)} ${_tr('م')}',
          size: 8.5,
          color: _muted,
        ),
      ),
    pw.Center(
      child: pw.Text(
        page.subtitle,
        style: _st(size: 7.5, color: _goldText).copyWith(letterSpacing: 2),
        textDirection: pw.TextDirection.ltr,
      ),
    ),
    pw.SizedBox(height: 8),
  ];

  final doc = pw.Document(title: _tr(page.title), author: settings.name);
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 28),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        theme: pw.ThemeData.withFont(base: _fontRegular!, bold: _fontBold!),
        buildBackground: !page.letterhead
            ? null
            : (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Stack(
            children: [
              pw.Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: pw.Container(height: 5, color: accent),
              ),
              pw.Positioned(
                left: 0,
                top: 0,
                child: pw.Container(width: 140, height: 5, color: _gold),
              ),
              if (logo != null)
                pw.Center(
                  child: pw.Opacity(
                    opacity: 0.05,
                    child: pw.SizedBox(
                      width: 260,
                      height: 260,
                      child: pw.Image(
                        pw.MemoryImage(logo),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: 0.7)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: page.letterhead
                  ? _text(
                      '${_tr('صادر إلكترونيًا عبر تطبيق Fundly')} · $issuedOn — '
                      '${_tr('أي كشط أو تعديل يدوي يُبطل هذا المستند')}',
                      size: 6.8,
                      color: _faint,
                    )
                  : pw.SizedBox(),
            ),
            _text(
              '${_tr('صفحة')} ${context.pageNumber} / ${context.pagesCount}',
              size: 7.5,
              bold: true,
              color: _muted,
            ),
          ],
        ),
      ),
      build: (context) => [...header, ...body],
    ),
  );
  return doc.save();
}

// ============================================================
// قوالب المستندات (إيصالات، فواتير، تقارير، إنذارات، عقود)
// ============================================================

/// مدخلات طباعة نموذج محفوظ — تجهّزها شاشة القوالب.
class TemplatePrintInput {
  const TemplatePrintInput({
    required this.type,
    required this.fields,
    required this.sections,
    this.tables = const {},
    this.intro = '',
    this.clauses = const [],
    this.signers = const [],
    this.witnesses = const [],
    this.userSigner = 0,
    this.withSignature = false,
    this.linked = '',
    this.docNo = '',
    this.issued,
  });

  final String type;
  final Map<String, String> fields;

  /// الأقسام بترتيب النموذج: (العنوان، الحقول).
  final List<(String, List<String>)> sections;

  /// حقول الجداول: الاسم ← الأعمدة.
  final Map<String, List<String>> tables;
  final String intro;
  final List<String> clauses;
  final List<(String, String)> signers;
  final List<(String, String)> witnesses;
  final int userSigner;
  final bool withSignature;
  final String linked;
  final String docNo;
  final DateTime? issued;
}

const _titles = <String, (String, String)>{
  'إيصال أمانة': ('إيصال أمانة', 'TRUST RECEIPT'),
  'إيصال استلام وتسليم': ('محضر استلام وتسليم', 'HANDOVER RECEIPT'),
  'فاتورة': ('فاتورة', 'INVOICE'),
  'تقرير ضريبي': ('تقرير ضريبة القيمة المضافة', 'VAT REPORT'),
  'عقد إيجار عقار': ('عقد إيجار عقار', 'PROPERTY LEASE AGREEMENT'),
  'عقد إيجار نشاط تجاري': ('عقد إيجار نشاط تجاري', 'COMMERCIAL LEASE AGREEMENT'),
  'عقد تأجير مركبة': ('عقد تأجير مركبة', 'VEHICLE RENTAL AGREEMENT'),
  'عقد عام': ('عقد اتفاق', 'GENERAL AGREEMENT'),
  'إنذار': ('إنذار رسمي', 'FORMAL NOTICE'),
};

/// خانات المبالغ في النماذج: تُطبع بجانبها عملة النموذج.
const Set<String> _templateMoneyKeys = {
  'المبلغ',
  'قيمة القسط',
  'قيمة الإيجار السنوي',
  'قيمة الإيجار',
  'مبلغ التأمين',
  'رسوم الكيلومتر الإضافي',
  'رأس المال',
  'قيمة العقد',
  'المبلغ المطالب به',
};

String _rateLabel(double rate) =>
    rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1);

/// ملف PDF لنموذج محفوظ.
Future<Uint8List> buildTemplatePdf(
  TemplatePrintInput input,
  PdfPageFormat format,
) async {
  final f = input.fields;
  String v(String key) => (f[key] ?? '').trim();
  // عملة النموذج كما اختيرت فيه، وإلا العملة الافتراضية للتطبيق.
  final currency = _tr(
    v('العملة').isEmpty ? AppSettings.currencySuffix : v('العملة'),
  );
  final doc = _Doc();
  final issued =
      _parseDate(v('تاريخ تحرير العقد')) ??
      _parseDate(v('تاريخ الإصدار')) ??
      input.issued ??
      DateTime.now();
  final signature = input.withSignature
      ? _signatureSvg(await UserSignatureStore.load())
      : '';
  final stamp = input.withSignature ? await UserStampStore.load() : null;
  final type = input.type;
  final titles = _titles[type] ?? (type, '');
  var title = titles.$1;
  if (type == 'فاتورة' && v('الرقم الضريبي للمُصدر').isNotEmpty) {
    title = 'فاتورة ضريبية';
  }
  final consumed = <String>{
    'تاريخ الإصدار',
    'ملاحظات',
    'includeSignature',
    'reminder',
  };
  final body = <pw.Widget>[];
  final metaExtra = <(String, String)>[];
  final seller = AppSettings.instance.name;

  // ---------- الإنذار: بنمط خطاب ----------
  if (type == 'إنذار') {
    metaExtra.add(('رقم العقد', v('رقم العقد المرتبط')));
    body.add(
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: _noHarakat('${_tr('إلى السيد/')} '),
                    style: _st(size: 11, color: _muted),
                  ),
                  pw.TextSpan(
                    text: _noHarakat(v('المرسل إليه')),
                    style: _st(size: 11.5, bold: true),
                  ),
                ],
              ),
            ),
          ),
          _text(_tr('المحترم'), size: 10, color: _muted),
        ],
      ),
    );
    final extraTo = [
      if (v('رقم هوية المرسل إليه').isNotEmpty)
        '${_tr('رقم الهوية')}: ${v('رقم هوية المرسل إليه')}',
      if (v('رقم جواز المرسل إليه').isNotEmpty)
        '${_tr('رقم الجواز')}: ${v('رقم جواز المرسل إليه')}',
      v('عنوان المرسل إليه'),
    ].where((s) => s.isNotEmpty).join(' · ');
    if (extraTo.isNotEmpty) body.add(_text(extraTo, size: 8.5, color: _muted));
    if (v('سبب الإنذار').isNotEmpty) {
      body.add(
        pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 8),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const pw.BoxDecoration(
            color: _redBg,
            border: pw.Border(right: pw.BorderSide(color: _red, width: 3)),
          ),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '${_tr('الموضوع:')} ',
                  style: _st(size: 10, bold: true, color: _red),
                ),
                pw.TextSpan(
                  text: v('سبب الإنذار'),
                  style: _st(size: 10, bold: true),
                ),
              ],
            ),
          ),
        ),
      );
    }
    body.addAll(doc.para(_tr('السلام عليكم ورحمة الله وبركاته، وبعد:')));
    body.addAll(doc.para(v('نص الإنذار'), lead: true));
    final boxes = <pw.Widget>[];
    void box(String label, String value, String sub) {
      if (value.isEmpty) return;
      if (boxes.isNotEmpty) boxes.add(pw.SizedBox(width: 8));
      boxes.add(
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: _redSoft,
              border: pw.Border.all(color: _redLine, width: 1),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text(_tr(label), size: 7.8, color: _redDark),
                _text(value, size: 12, bold: true),
                if (sub.isNotEmpty) _text(sub, size: 8, color: _muted),
              ],
            ),
          ),
        ),
      );
    }

    box(
      'المهلة',
      v('المهلة'),
      v('تاريخ انتهاء المهلة').isEmpty
          ? ''
          : '${_tr('تنتهي في')} ${v('تاريخ انتهاء المهلة')}',
    );
    box(
      'الإجراء المطلوب',
      v('الإجراء المطلوب'),
      v('المبلغ المطالب به').isEmpty
          ? ''
          : '${_tr('المبلغ المطالب به')}: '
                '${printMoney(printNum(v('المبلغ المطالب به')))} $currency',
    );
    if (boxes.isNotEmpty) {
      body.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Row(children: boxes),
        ),
      );
    }
    body.addAll(doc.para(_tr(
      'وفي حال عدم الاستجابة خلال المهلة المحددة سنضطر آسفين لاتخاذ '
      'الإجراءات النظامية اللازمة دون الرجوع إليكم.',
    )));
    body.addAll(doc.note(v('ملاحظات')));
    body.addAll(_signatures(
      [('المُنذِر', seller)],
      signatureSvg: signature,
      stamp: stamp,
    ));
    // لا سطر «إقرار استلام» مطبوع: يُضعف قوة الإنذار. المستلم يوقّع تحته
    // ويكتب الاستلام بخط يده في هذه المساحة الفارغة.
    body.add(pw.SizedBox(height: 40));
    return _render(
      _Page(
        title: title,
        subtitle: titles.$2,
        docNo: input.docNo,
        date: issued,
        metaExtra: metaExtra,
        warn: true,
      ),
      body,
      format,
    );
  }

  // ---------- الفاتورة ----------
  if (type == 'فاتورة') {
    metaExtra.add(('تاريخ الاستحقاق', v('تاريخ الانتهاء')));
    pw.Widget card(String caption, String name, List<String> lines) =>
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line, width: 0.8),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text(_tr(caption), size: 7.5, bold: true, color: _goldText),
                _text(name, size: 10.5, bold: true, color: _title),
                for (final line in lines)
                  if (line.trim().isNotEmpty) _text(line, size: 8.3, color: _muted),
              ],
            ),
          ),
        );
    body.add(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          card('من', seller, [
            if (v('الرقم الضريبي للمُصدر').isNotEmpty)
              '${_tr('الرقم الضريبي')}: ${v('الرقم الضريبي للمُصدر')}',
            v('عنوان المُصدر'),
          ]),
          pw.SizedBox(width: 8),
          card('إلى (العميل)', v('اسم الجهة'), [
            if (v('الرقم الضريبي').isNotEmpty)
              '${_tr('الرقم الضريبي')}: ${v('الرقم الضريبي')}',
            v('عنوان العميل'),
          ]),
        ],
      ),
    );
    final rate = v('نسبة الضريبة %').isEmpty ? 15.0 : printNum(v('نسبة الضريبة %'));
    var items = printRows(v('بنود الفاتورة'));
    if (items.isEmpty && (v('البيان').isNotEmpty || v('المبلغ').isNotEmpty)) {
      items = [
        {'البيان': v('البيان'), 'الكمية': '1', 'سعر الوحدة': v('المبلغ')},
      ];
    }
    var net = 0.0, tax = 0.0;
    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final row = items[i];
      final qty = (row['الكمية'] ?? '').isNotEmpty ? printNum(row['الكمية']!) : 1.0;
      final price = printNum(row['سعر الوحدة'] ?? '');
      final lineNet = qty * price;
      final lineTax = lineNet * rate / 100;
      net += lineNet;
      tax += lineTax;
      rows.add([
        '${i + 1}',
        row['البيان'] ?? '',
        qty == qty.roundToDouble() ? '${qty.round()}' : '$qty',
        printMoney(price),
        printMoney(lineTax),
        printMoney(lineNet + lineTax),
      ]);
    }
    body.add(pw.SizedBox(height: 8));
    body.addAll(doc.table(
      ['#', 'البيان', 'الكمية', 'سعر الوحدة', '${_tr('الضريبة')} ${_rateLabel(rate)}%', 'الإجمالي'],
      rows,
      numeric: const {2, 3, 4, 5},
    ));
    if (rows.isNotEmpty) {
      pw.Widget totalRow(String label, double value, {bool grand = false}) =>
          pw.Container(
            color: grand ? _deep : null,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: grand
                ? null
                : const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _rowLine, width: 0.6),
                    ),
                  ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: _text(
                    _tr(label),
                    size: grand ? 10 : 8.8,
                    bold: grand,
                    color: grand ? _white : _ink,
                  ),
                ),
                _text(
                  '${printMoney(value)} $currency',
                  size: grand ? 11 : 9,
                  bold: true,
                  color: grand ? _white : _ink,
                ),
              ],
            ),
          );
      final vatNo = v('الرقم الضريبي للمُصدر');
      body.add(pw.SizedBox(height: 8));
      body.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    totalRow('الإجمالي قبل الضريبة', net),
                    totalRow('ضريبة القيمة المضافة', tax),
                    totalRow('الإجمالي المستحق', net + tax, grand: true),
                  ],
                ),
              ),
            ),
            if (vatNo.isNotEmpty) ...[
              pw.SizedBox(width: 10),
              pw.BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: zatcaQrPayload(
                  seller: seller,
                  vatNo: vatNo,
                  time: issued,
                  total: net + tax,
                  vat: tax,
                ),
                width: 72,
                height: 72,
              ),
            ],
          ],
        ),
      );
    }
    body.addAll(doc.section(
      'طريقة الدفع',
      doc.kv([('اسم البنك', v('اسم البنك')), ('الآيبان', v('الآيبان'))], cols: 2),
      numbered: false,
    ));
    body.addAll(doc.note(v('ملاحظات')));
    body.addAll(_signatures(
      [('المُصدِر', seller)],
      signatureSvg: signature,
      stamp: stamp,
    ));
    return _render(
      _Page(
        title: title,
        subtitle: titles.$2,
        docNo: v('رقم الفاتورة').isEmpty ? input.docNo : v('رقم الفاتورة'),
        date: issued,
        metaExtra: metaExtra,
      ),
      body,
      format,
    );
  }

  // ---------- التقرير الضريبي ----------
  if (type == 'تقرير ضريبي') {
    final rate = v('نسبة الضريبة %').isEmpty ? 15.0 : printNum(v('نسبة الضريبة %'));
    final months = printRows(v('التفصيل الشهري'));
    var sales = 0.0, purchases = 0.0;
    final rows = <List<String>>[];
    for (final row in months) {
      final s = printNum(row['المبيعات'] ?? '');
      final p = printNum(row['المشتريات'] ?? '');
      sales += s;
      purchases += p;
      rows.add([
        row['الشهر'] ?? '',
        printMoney(s),
        printMoney(s * rate / 100),
        printMoney(p),
        printMoney(p * rate / 100),
        printMoney((s - p) * rate / 100),
      ]);
    }
    if (months.isEmpty) sales = printNum(v('الإيرادات'));
    final outTax = months.isEmpty ? printNum(v('الضريبة')) : sales * rate / 100;
    final inTax = purchases * rate / 100;
    final net = outTax - inTax;
    body.addAll(doc.kpis([
      ('إجمالي المبيعات', printMoney(sales), currency, false),
      ('ضريبة المخرجات', printMoney(outTax), currency, false),
      ('ضريبة المدخلات', printMoney(inTax), currency, false),
      ('صافي الضريبة المستحقة', printMoney(net), currency, true),
    ]));
    body.addAll(doc.section(
      'التفصيل الشهري',
      doc.table(
        ['الشهر', 'المبيعات', 'ضريبة المخرجات', 'المشتريات', 'ضريبة المدخلات', 'الصافي'],
        rows,
        foot: [
          'الإجمالي',
          printMoney(sales),
          printMoney(outTax),
          printMoney(purchases),
          printMoney(inTax),
          printMoney(net),
        ],
        numeric: const {1, 2, 3, 4, 5},
      ),
    ));
    body.addAll(doc.section('بيانات المكلّف', doc.kv([
      ('الاسم', v('اسم المكلّف').isEmpty ? seller : v('اسم المكلّف')),
      ('الرقم الضريبي', v('الرقم الضريبي')),
      ('الفترة الضريبية', v('الفترة الضريبية')),
      ('نسبة الضريبة', '${_rateLabel(rate)}%'),
      ('تاريخ استحقاق السداد', v('تاريخ استحقاق السداد')),
    ])));
    body.addAll(doc.note(
      '${_tr('هذا التقرير للمتابعة الداخلية من بيانات التطبيق، ولا يغني عن الإقرار الرسمي لدى الجهة المختصة.')}'
      '${v('ملاحظات').isEmpty ? '' : '\n${v('ملاحظات')}'}',
    ));
    body.addAll(_signatures(
      [('أعدّه', seller), ('اعتمده', '')],
      signatureSvg: signature,
      stamp: stamp,
    ));
    return _render(
      _Page(
        title: title,
        subtitle: titles.$2,
        docNo: input.docNo,
        date: issued,
        metaExtra: [('الفترة', v('الفترة الضريبية'))],
      ),
      body,
      format,
    );
  }

  // ---------- العام: الإقرار، الأقسام بجداولها، البنود، التوقيعات ----------
  if (type == 'إيصال أمانة' && v('المبلغ').isNotEmpty) {
    body.add(
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _creamBg,
          border: pw.Border.all(color: _gold, width: 1.2),
          borderRadius: pw.BorderRadius.circular(9),
        ),
        child: pw.Row(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _text(_tr('المبلغ'), size: 8, color: _goldText),
                _text(
                  '${printMoney(printNum(v('المبلغ')))} $currency',
                  size: 17,
                  bold: true,
                  color: _title,
                ),
              ],
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _text(
                v('المبلغ كتابةً'),
                size: 8.5,
                color: _muted,
                align: AppTr.isEnglish ? pw.TextAlign.right : pw.TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );
    consumed.addAll({'المبلغ', 'المبلغ كتابةً'});
  }
  if (v('مكان تحرير العقد').isNotEmpty) {
    metaExtra.add(('مكان التحرير', v('مكان تحرير العقد')));
  }
  body.addAll(doc.para(input.intro, lead: true));
  for (final (heading, keys) in input.sections) {
    final pairs = <(String, String)>[];
    final tables = <pw.Widget>[];
    for (final key in keys) {
      // العملة تُكتب بجانب كل مبلغ، فلا سطر مستقل لها.
      if (consumed.contains(key) || key == 'العملة') continue;
      final columns = input.tables[key];
      if (columns != null) {
        tables.addAll(_tableFor(doc, key, columns, v(key), f));
        continue;
      }
      pairs.add((
        key,
        _templateMoneyKeys.contains(key) && v(key).isNotEmpty
            ? '${v(key)} $currency'
            : _showDate(v(key)),
      ));
    }
    // محضر الاستلام القديم: عنصر واحد بلا جدول.
    if (type == 'إيصال استلام وتسليم' &&
        keys.contains('العناصر المسلّمة') &&
        printRows(v('العناصر المسلّمة')).isEmpty &&
        v('العنصر').isNotEmpty) {
      tables.addAll(doc.table(
        ['#', 'العنصر', 'الحالة'],
        [
          ['1', v('العنصر'), v('حالته')],
        ],
      ));
    }
    body.addAll(doc.section(heading, [...doc.kv(pairs), ...tables]));
  }
  body.addAll(doc.section('البنود', doc.clauses(input.clauses)));
  if (input.linked.isNotEmpty) {
    body.addAll(doc.note('${_tr('مرتبط بـ')}: ${input.linked}'));
  }
  body.addAll(doc.note(v('ملاحظات')));
  body.addAll(_signatures(
    input.signers.isEmpty ? [('المُصدِر', seller)] : input.signers,
    userIndex: input.userSigner,
    signatureSvg: signature,
    stamp: stamp,
    witnesses: input.witnesses,
  ));
  if (type.startsWith('عقد')) {
    body.add(_signedNote('حُرّر هذا العقد من نسختين، بيد كل طرف نسخة للعمل بموجبها.'));
  }
  return _render(
    _Page(
      title: title,
      subtitle: titles.$2,
      docNo: v('رقم العقد').isEmpty ? input.docNo : v('رقم العقد'),
      date: issued,
      metaExtra: metaExtra,
    ),
    body,
    format,
  );
}

/// جدول من حقل JSON، مع الضريبة والإجمالي لجداول المبالغ.
List<pw.Widget> _tableFor(
  _Doc doc,
  String key,
  List<String> columns,
  String raw,
  Map<String, String> f,
) {
  final rows = printRows(raw);
  if (rows.isEmpty) return const [];
  final rate = printNum(f['نسبة الضريبة %'] ?? '');
  if (key == 'الدفعات' || key == 'الرسوم الإدارية') {
    const amountCol = 'القيمة';
    final withTax = key == 'الدفعات' && rate > 0;
    var total = 0.0, totalTax = 0.0;
    final out = <List<String>>[];
    for (var i = 0; i < rows.length; i++) {
      final amount = printNum(rows[i][amountCol] ?? '');
      final tax = withTax ? amount * rate / 100 : 0.0;
      total += amount;
      totalTax += tax;
      out.add([
        '${i + 1}',
        for (final c in columns)
          c == amountCol ? printMoney(amount) : _showDate(rows[i][c] ?? ''),
        if (withTax) printMoney(tax),
        if (withTax) printMoney(amount + tax),
      ]);
    }
    final heads = ['#', ...columns, if (withTax) 'الضريبة', if (withTax) 'الإجمالي'];
    final amountIndex = columns.indexOf(amountCol) + 1;
    final foot = List<String>.filled(heads.length, '');
    foot[1] = 'الإجمالي';
    if (amountIndex > 0) foot[amountIndex] = printMoney(total);
    if (withTax) {
      foot[heads.length - 2] = printMoney(totalTax);
      foot[heads.length - 1] = printMoney(total + totalTax);
    }
    return doc.table(
      heads,
      out,
      foot: foot,
      numeric: {
        amountIndex,
        if (withTax) heads.length - 2,
        if (withTax) heads.length - 1,
      },
    );
  }
  return doc.table(
    ['#', ...columns],
    [
      for (var i = 0; i < rows.length; i++)
        ['${i + 1}', for (final c in columns) _showDate(rows[i][c] ?? '')],
    ],
  );
}

// ============================================================
// عقود الإيجار المسجّلة في العقارات والأنشطة والمركبات
// ============================================================

/// مفاتيح داخلية لا تُطبع.
const _leaseInternal = {
  LeaseContractData.kSubject,
  LeaseContractData.kPaymentsNote,
  LeaseContractData.kTaxRate,
  LeaseContractData.kRentTaxable,
  LeaseContractData.kAdminFeesTaxable,
  LeaseContractData.kAdminFeesTaxRate,
  LeaseContractData.kContractScope,
  LeaseContractData.kLeaseReminderDays,
  LeaseContractData.kLicenseReminder,
  LeaseContractData.kLicenseReminderDays,
  LeaseContractData.kRowId,
  LeaseContractData.kChequeState,
  LeaseContractData.kChequeLog,
  LeaseContractData.kPaymentReminder,
  LeaseContractData.kPaymentReminderDays,
};

List<(String, String)> _pairsOf(
  Map<String, String> values,
  List<LeaseFieldSpec> specs,
) {
  final out = <(String, String)>[];
  final seen = <String>{};
  for (final spec in specs) {
    seen.add(spec.key);
    final value = (values[spec.key] ?? '').trim();
    if (value.isEmpty) continue;
    out.add((spec.label, spec.date ? _showDate(value) : value));
  }
  for (final entry in values.entries) {
    if (seen.contains(entry.key) || _leaseInternal.contains(entry.key)) {
      continue;
    }
    if (entry.key.startsWith('__') || entry.value.trim().isEmpty) continue;
    out.add((
      entry.key == LeaseContractData.kMobile
          ? LeaseContractData.kPhone
          : entry.key,
      _showDate(entry.value),
    ));
  }
  return out;
}

/// قسم في تقرير عام: أزواج «العنوان: القيمة» و/أو جدول.
class PrintSection {
  const PrintSection(
    this.title, {
    this.pairs = const [],
    this.heads = const [],
    this.rows = const [],
  });

  final String title;
  final List<(String, String)> pairs;
  final List<String> heads;
  final List<List<String>> rows;
}

/// تقرير عام بأقسام (السجل التاريخي لوحدة أو عقار مثلًا). الجدول الواسع
/// (أكثر من 6 أعمدة) يُطبع سطرًا سطرًا كأزواج كي لا تضيق أعمدته.
Future<Uint8List> buildRecordPdf({
  required String title,
  required List<PrintSection> sections,
  required PdfPageFormat format,
  String subtitle = 'RECORD',
  List<(String, String)> meta = const [],
  bool letterhead = true,
}) async {
  final doc = _Doc();
  final body = <pw.Widget>[];
  for (final s in sections) {
    final content = <pw.Widget>[...doc.kv(s.pairs)];
    if (s.rows.isNotEmpty && s.heads.isNotEmpty) {
      if (s.heads.length > 6) {
        for (final row in s.rows) {
          content.add(pw.SizedBox(height: 4));
          content.addAll(doc.kv([
            for (var i = 0; i < s.heads.length && i < row.length; i++)
              (s.heads[i], row[i]),
          ]));
        }
      } else {
        if (content.isNotEmpty) content.add(pw.SizedBox(height: 4));
        content.addAll(doc.table(s.heads, s.rows));
      }
    }
    body.addAll(doc.section(s.title, content));
  }
  return _render(
    _Page(
      title: title,
      subtitle: subtitle,
      docNo: '',
      date: DateTime.now(),
      metaExtra: meta,
      letterhead: letterhead,
    ),
    body,
    format,
  );
}

/// بيانات العقار للطباعة: كل عداد في سطر «رقم عداد الكهرباء 1: 123 — على
/// المستأجر» بدل أسطر الأرقام و«على من» مجمّعة.
Map<String, String> _leasePropertyForPrint(Map<String, String> property) {
  final out = Map<String, String>.of(property);
  LeaseContractData.migrateMeters(out);
  LeaseContractData.meterGroups.forEach((countKey, group) {
    final n = LeaseContractData.meterCountOf(out, countKey);
    final numbers = LeaseContractData.meterLines(out[group.$1], n);
    final payers = LeaseContractData.meterLines(out[group.$2], n);
    out.remove(group.$1);
    out.remove(group.$2);
    for (var i = 0; i < n; i++) {
      final value = [
        if (numbers[i].isNotEmpty) numbers[i],
        if (payers[i].isNotEmpty) 'على ${payers[i]}',
      ].join(' — ');
      if (value.isNotEmpty) out['${group.$3} ${i + 1}'] = value;
    }
  });
  return out;
}

/// ملف PDF لعقد إيجار مسجّل بكل إدخالاته.
Future<Uint8List> buildLeasePdf(
  LeaseContractData data,
  PdfPageFormat format, {
  required String title,
  bool activity = false,
  Map<String, String> assetMeta = const {},
}) async {
  final vehicle = data.isVehicle;
  final doc = _Doc();
  final c = data.contract;
  String cv(String key) => (c[key] ?? '').trim();
  // عقد من «المستندات» قد تكون له عملته؛ وإلا عملة التطبيق.
  final currency = _tr(
    cv('العملة').isEmpty ? AppSettings.currencySuffix : cv('العملة'),
  );
  final body = <pw.Widget>[];

  final contractSpecs = vehicle
      ? LeaseContractData.vehicleContractFields
      : activity
      ? LeaseContractData.activityContractFields
      : LeaseContractData.contractFields;
  body.addAll(doc.section('بيانات العقد', doc.kv(_pairsOf(c, contractSpecs))));
  body.addAll(doc.section(
    'الطرف الأول — المؤجر',
    doc.kv(_pairsOf(data.lessor, LeaseContractData.lessorFields)),
  ));
  body.addAll(doc.section(
    'الطرف الثاني — المستأجر',
    doc.kv(_pairsOf(data.tenant, LeaseContractData.tenantFields)),
  ));
  if (!vehicle) {
    body.addAll(doc.section(
      'ممثل المستأجر',
      doc.kv(_pairsOf(data.representative, LeaseContractData.representativeFields)),
    ));
  }
  if (activity) {
    body.addAll(doc.section(
      'بيانات الرخصة والنشاط',
      doc.kv(_pairsOf(data.license, const [])),
    ));
  }
  body.addAll(doc.section(
    vehicle
        ? 'بيانات المركبة'
        : (activity ? 'بيانات المحل' : 'بيانات العين المؤجرة'),
    doc.kv(_pairsOf(
      vehicle ? data.property : _leasePropertyForPrint(data.property),
      vehicle ? const [] : LeaseContractData.leasePropertyFields,
    )),
  ));

  if (vehicle) {
    String m(String key) => (assetMeta[key] ?? '').trim();
    String when(String date, String time) =>
        [m(date), m(time)].where((s) => s.isNotEmpty).join(' · ');
    body.addAll(doc.section('شروط التأجير', doc.kv([
      ('الموقع', m('موقع المشروع')),
      ('وقت البدء', when('بدء المشروع', 'ساعة بدء المشروع')),
      ('وقت الإغلاق', when('وقت الإغلاق', 'ساعة الإغلاق')),
      ('على من الصيانة', m('الصيانة على')),
      ('على من الوقود', m('الوقود على')),
      ('رقم التواصل', m('رقم التواصل')),
      ('ملاحظات', m('ملاحظات شروط التأجير')),
    ])));
    final marine = m('تصنيف المركبة') == 'مركبات بحرية';
    body.addAll(doc.section(
      marine ? 'القبطان والرخصة البحرية' : 'السائق / المشغّل',
      doc.kv([
        ('الاسم', m('اسم المشغل')),
        ('الجنسية', m('جنسية المشغل')),
        ('انتهاء الرخصة', m('انتهاء شهادة المشغل')),
        ('انتهاء شهادة السلامة', m('انتهاء شهادة السلامة')),
      ]),
    ));
  }

  // ---------- القيمة المالية والدفعات ----------
  if (data.payments.isNotEmpty) {
    final rate = data.taxRate;
    final rows = <List<String>>[];
    for (var i = 0; i < data.payments.length; i++) {
      final row = data.payments[i];
      final amount = printNum(row[LeaseContractData.kPaymentAmount] ?? '');
      final tax = data.paymentTaxOf(row);
      rows.add([
        '${i + 1}',
        row[LeaseContractData.kPaymentFee] ?? '',
        printMoney(amount),
        printMoney(tax),
        printMoney(amount + tax),
        _showDate(row[LeaseContractData.kPaymentDue] ?? ''),
        row[LeaseContractData.kCollectMethod] ?? '',
        [
          row[LeaseContractData.kPaymentCheque] ?? '',
          row[LeaseContractData.kPaymentBank] ?? '',
        ].where((s) => s.trim().isNotEmpty).join(' · '),
      ]);
    }
    final note = cv(LeaseContractData.kPaymentsNote);
    body.addAll(doc.section('القيمة المالية والدفعات', [
      ...doc.kpis([
        ('القيمة قبل الضريبة', printMoney(data.paymentsTotal), currency, false),
        ('الضريبة', '${_rateLabel(rate)}%', '${printMoney(data.paymentsTax)} $currency', false),
        ('عدد الدفعات', '${data.payments.length}', _tr('دفعة'), false),
        ('الإجمالي', printMoney(data.paymentsGross), currency, true),
      ]),
      ...doc.table(
        ['#', 'اسم الدفعة', 'القيمة', 'الضريبة', 'الإجمالي', 'الاستحقاق', 'طريقة التحصيل', 'شيك / بنك'],
        rows,
        foot: [
          '',
          'الإجمالي',
          printMoney(data.paymentsTotal),
          printMoney(data.paymentsTax),
          printMoney(data.paymentsGross),
          '',
          '',
          '',
        ],
        numeric: const {2, 3, 4},
      ),
      if (note.isNotEmpty) ...doc.note('${_tr('ملاحظات الدفعات')}: $note'),
    ]));
  }
  if (data.deposits.isNotEmpty) {
    body.addAll(doc.section('التأمين', doc.table(
      ['مبلغ التأمين', 'طريقة التحصيل', 'تاريخ التحصيل', 'رقم الإيصال', 'شيك / بنك', 'ملاحظات'],
      [
        for (final row in data.deposits)
          [
            printMoney(printNum(row[LeaseContractData.kDepositAmount] ?? '')),
            row[LeaseContractData.kCollectMethod] ?? '',
            _showDate(row['تاريخ تحصيل التأمين'] ?? ''),
            row['رقم الإيصال'] ?? '',
            [
              row[LeaseContractData.kPaymentCheque] ?? '',
              row[LeaseContractData.kPaymentBank] ?? '',
            ].where((s) => s.trim().isNotEmpty).join(' · '),
            row['ملاحظات'] ?? '',
          ],
      ],
      numeric: const {0},
    )));
  }
  if (data.adminFees.isNotEmpty && data.contractIncludesAdminFees) {
    body.addAll(doc.section('الرسوم الإدارية', doc.table(
      ['نوع الرسم', 'القيمة', 'الضريبة', 'الاستحقاق', 'طريقة التحصيل', 'رقم الإيصال', 'يتحمّلها'],
      [
        for (final row in data.adminFees)
          [
            row[LeaseContractData.kAdminFeeType] ?? '',
            printMoney(printNum(row[LeaseContractData.kAdminFeeAmount] ?? '')),
            printMoney(data.adminFeeTaxOf(row)),
            _showDate(row[LeaseContractData.kAdminFeeDue] ?? ''),
            row[LeaseContractData.kCollectMethod] ?? '',
            row['رقم الإيصال'] ?? '',
            row['على من'] ?? '',
          ],
      ],
      numeric: const {1, 2},
    )));
  }

  // ---------- البنود ----------
  final start = _showDate(cv(LeaseContractData.kStartDate));
  final end = _showDate(cv(LeaseContractData.kEndDate));
  final clauses = <String>[
    if (start.isNotEmpty && end.isNotEmpty)
      '${_tr('مدة العقد من')} $start ${_tr('إلى')} $end${_tr('، ولا يُجدَّد إلا باتفاق مكتوب بين الطرفين.')}',
    _tr('يلتزم المستأجر بسداد الدفعات في مواعيد استحقاقها المبيّنة في جدول الدفعات.'),
    if (data.deposits.isNotEmpty)
      _tr('يُردّ مبلغ التأمين عند انتهاء العقد بعد خصم أي مستحقات أو أضرار إن وُجدت.'),
    _tr(vehicle
        ? 'يتحمّل المستأجر المخالفات والأضرار الناتجة عن سوء الاستخدام طوال مدة التأجير.'
        : 'لا يحق للمستأجر التأجير من الباطن أو تغيير استخدام العين إلا بموافقة كتابية من المؤجر.'),
    _tr('إذا أخلّ أحد الطرفين بالتزاماته يحق للطرف الآخر المطالبة بحقوقه وفق الأنظمة المعمول بها.'),
  ];
  body.addAll(doc.section('البنود', doc.clauses(clauses)));

  final signature = _signatureSvg(await UserSignatureStore.load());
  final stamp = await UserStampStore.load();
  body.addAll(_signatures(
    [
      ('الطرف الأول — المؤجر', (data.lessor[LeaseContractData.kName] ?? '').trim()),
      (
        vehicle ? 'الطرف الثاني — المستأجر' : 'الطرف الثاني — المستأجر / ممثله',
        (data.tenant[LeaseContractData.kName] ?? '').trim(),
      ),
    ],
    signatureSvg: data.isSigned ? signature : '',
    stamp: data.isSigned ? stamp : null,
  ));
  body.add(_signedNote('حُرّر هذا العقد من نسختين، بيد كل طرف نسخة للعمل بموجبها.'));

  final no = cv(LeaseContractData.kNewNo);
  final issued = _parseDate(cv(LeaseContractData.kStartDate)) ?? DateTime.now();
  return _render(
    _Page(
      title: title,
      subtitle: vehicle
          ? 'VEHICLE RENTAL AGREEMENT'
          : activity
          ? 'COMMERCIAL LEASE AGREEMENT'
          : 'LEASE AGREEMENT',
      docNo: no,
      date: issued,
      metaExtra: [('نمط المدة', cv(LeaseContractData.kTermMode))],
    ),
    body,
    format,
  );
}
