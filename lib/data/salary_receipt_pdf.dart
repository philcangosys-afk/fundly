import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n/app_language.dart';
import 'salary_receipts.dart';

/// سند القبض / الراتب كملف PDF: صفحة A4 احترافية لكل سند (الأطراف، تفاصيل
/// الراتب، المبلغ المدفوع، توقيع المستلم ووقته). عدة سندات = عدة صفحات في
/// ملف واحد. يُرسم داخل التطبيق بلا إنترنت وبخط التطبيق نفسه.

const _deep = PdfColor.fromInt(0xFF0A5A50);
const _brand = PdfColor.fromInt(0xFF0E7161);
const _gold = PdfColor.fromInt(0xFFCE8422);
const _ink = PdfColor.fromInt(0xFF0F1F1C);
const _muted = PdfColor.fromInt(0xFF6B7A77);
const _line = PdfColor.fromInt(0xFFDCE6E3);
const _soft = PdfColor.fromInt(0xFFF3F8F6);
const _green = PdfColor.fromInt(0xFF178F7B);
const _orange = PdfColor.fromInt(0xFFA6691A);
const _red = PdfColor.fromInt(0xFFC4392E);

pw.Font? _regular;
pw.Font? _bold;

Future<void> _loadFonts() async {
  _regular ??= pw.Font.ttf(
    await rootBundle.load('assets/fonts/CairoRegular.ttf'),
  );
  _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/CairoBold.ttf'));
}

String _t(String text) => AppTr.tr(text);

/// مكتبة الاتجاه (bidi) في PDF تنهار مع التشكيل فوق الحروف المهموزة
/// (مثل «أُرسل»)، فيُزال التشكيل من نص الملف فقط — الحروف نفسها لا تتغيّر.
final _harakat = RegExp('[\u064B-\u0652\u0670]');
String _pdfSafe(String text) => text.replaceAll(_harakat, '');

/// 2,300 أو 2,300.50
String salaryMoney(double value) {
  final negative = value < 0;
  final abs = value.abs();
  final fixed = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  final decimals = parts.length > 1 ? '.${parts[1]}' : '';
  return '${negative ? '-' : ''}$out$decimals';
}

String _stamp(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.day}/${l.month}/${l.year}  ${two(l.hour)}:${two(l.minute)}';
}

/// رقم مختصر ثابت للسند من معرّفه.
String salaryReceiptNo(SalaryReceipt r) {
  final id = (r.id ?? '').replaceAll('-', '');
  return id.isEmpty ? '—' : id.substring(0, id.length < 8 ? id.length : 8).toUpperCase();
}

PdfColor _statusColor(SalaryReceipt r) => r.isApproved
    ? _green
    : r.isRejected
    ? _red
    : _orange;

pw.Widget _txt(
  String text, {
  double size = 10,
  bool bold = false,
  PdfColor color = _ink,
  pw.TextAlign? align,
  pw.TextDirection? dir,
}) => pw.Text(
  _pdfSafe(text),
  textAlign: align,
  textDirection: dir,
  style: pw.TextStyle(
    fontSize: size,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: color,
  ),
);

/// التوقيع: خطوط بنقاط نسبية (0..1) داخل مربع.
pw.Widget _signature(SalaryReceipt r, double side) {
  final strokes = r.strokes;
  if (strokes.isEmpty) {
    return pw.SizedBox(width: side, height: side);
  }
  return pw.CustomPaint(
    size: PdfPoint(side, side),
    painter: (canvas, size) {
      canvas
        ..setStrokeColor(_ink)
        ..setLineWidth(1.6)
        ..setLineCap(PdfLineCap.round)
        ..setLineJoin(PdfLineJoin.round);
      for (final stroke in strokes) {
        if (stroke.isEmpty) continue;
        final first = stroke.first;
        canvas.moveTo(first.dx * size.x, size.y - first.dy * size.y);
        if (stroke.length == 1) {
          canvas.lineTo(first.dx * size.x + 0.5, size.y - first.dy * size.y);
        }
        for (final p in stroke.skip(1)) {
          canvas.lineTo(p.dx * size.x, size.y - p.dy * size.y);
        }
        canvas.strokePath();
      }
    },
  );
}

pw.Widget _page(SalaryReceipt r, bool rtl) {
  final currency = _t(r.currency.isEmpty ? 'درهم' : r.currency);
  String money(double v) => '${salaryMoney(v)} $currency';
  final title = _t(r.isSalary ? 'سند قبض راتب' : 'سند قبض');
  final subtitle = r.isSalary ? 'SALARY RECEIPT' : 'PAYMENT RECEIPT';
  final status = _t(r.status);
  final statusColor = _statusColor(r);

  final breakdown = <(String, String, bool)>[
    if (r.isSalary) ...[
      ('الراتب الأساسي', money(r.basic), false),
      if (r.allowances > 0) ('العلاوات', money(r.allowances), false),
      if (r.overtime > 0) ('العمل الإضافي', money(r.overtime), false),
      if (r.loan > 0) ('السلفة', '- ${money(r.loan)}', false),
      if (r.deductions > 0) ('الخصومات', '- ${money(r.deductions)}', false),
      ('المجموع', money(r.total), true),
    ] else
      ('البيان', r.description.isEmpty ? '—' : r.description, false),
  ];

  pw.Widget infoCell(String label, String value, {String extra = ''}) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _soft,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: _line, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _txt(_t(label), size: 8.5, color: _muted),
              pw.SizedBox(height: 3),
              _txt(value.isEmpty ? '—' : value, size: 11.5, bold: true),
              if (extra.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                _txt(
                  extra,
                  size: 8.5,
                  color: _muted,
                  dir: pw.TextDirection.ltr,
                ),
              ],
            ],
          ),
        ),
      );

  final meta = <(String, String)>[
    ('رقم السند', salaryReceiptNo(r)),
    ('التاريخ', r.receiptDate),
    if (r.isSalary) ('الشهر', _t(r.periodLabel)),
  ];

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // الرأس: العنوان والحالة، ومربع الرقم والتاريخ.
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _txt(title, size: 22, bold: true, color: _deep),
                pw.Text(
                  _pdfSafe(subtitle),
                  textDirection: pw.TextDirection.ltr,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: _gold,
                    letterSpacing: 2.5,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(20),
                    border: pw.Border.all(color: statusColor, width: 1.2),
                  ),
                  child: _txt(status, size: 10, bold: true, color: statusColor),
                ),
              ],
            ),
          ),
          pw.Container(
            width: 190,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line, width: 0.8),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                for (var i = 0; i < meta.length; i++)
                  pw.Container(
                    color: i.isEven ? _soft : null,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    child: pw.Row(
                      children: [
                        _txt(_t(meta[i].$1), size: 8.5, color: _muted),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: _txt(
                            meta[i].$2,
                            size: 9.5,
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
      pw.SizedBox(height: 14),
      pw.Container(height: 1.4, color: _brand),
      pw.SizedBox(height: 14),
      // الأطراف.
      pw.Row(
        children: [
          infoCell('صاحب العمل', r.ownerName),
          pw.SizedBox(width: 10),
          infoCell(
            r.isSalary ? 'الموظف المستلم' : 'المستلم',
            r.employeeName,
            extra: r.employeeFnd,
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      // المبلغ المدفوع بارزًا.
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: pw.BoxDecoration(
          color: _deep,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: _txt(
                _t('المبلغ المدفوع'),
                size: 12,
                bold: true,
                color: PdfColors.white,
              ),
            ),
            _txt(money(r.paid), size: 18, bold: true, color: PdfColors.white),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
      // التفاصيل.
      _txt(
        _t(r.isSalary ? 'تفاصيل الراتب' : 'تفاصيل السند'),
        size: 11,
        bold: true,
        color: _deep,
      ),
      pw.SizedBox(height: 6),
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            for (var i = 0; i < breakdown.length; i++)
              pw.Container(
                color: breakdown[i].$3
                    ? _soft
                    : (i.isOdd ? const PdfColor.fromInt(0xFFFAFCFB) : null),
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: _txt(
                        _t(breakdown[i].$1),
                        size: 10,
                        bold: breakdown[i].$3,
                        color: breakdown[i].$3 ? _ink : _muted,
                      ),
                    ),
                    _txt(
                      breakdown[i].$2,
                      size: 10.5,
                      bold: true,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (r.notes.trim().isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _txt(_t('ملاحظات'), size: 9, color: _muted),
        pw.SizedBox(height: 2),
        _txt(r.notes.trim(), size: 10.5),
      ],
      if (r.isRejected && r.rejectReason.trim().isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _txt(_t('سبب الرفض'), size: 9, color: _red),
        pw.SizedBox(height: 2),
        _txt(r.rejectReason.trim(), size: 10.5),
      ],
      pw.Spacer(),
      // التوقيع.
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line, width: 0.8),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _txt(_t('توقيع المستلم'), size: 9, color: _muted),
                  pw.SizedBox(height: 4),
                  pw.Center(child: _signature(r, 90)),
                  pw.SizedBox(height: 4),
                  _txt(r.employeeName, size: 10.5, bold: true),
                  if (r.signedAt != null && !r.isRejected)
                    _txt(
                      '${_t('وقت التوقيع')}: ${_stamp(r.signedAt!)}',
                      size: 8.5,
                      color: _muted,
                    ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line, width: 0.8),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _txt(_t('طريقة التوقيع'), size: 9, color: _muted),
                  pw.SizedBox(height: 3),
                  _txt(
                    _t(
                      r.signMode == SalaryReceipt.signHere
                          ? 'وقّع على جوال صاحب العمل'
                          : 'أُرسل للاعتماد والتوقيع',
                    ),
                    size: 10,
                    bold: true,
                  ),
                  pw.SizedBox(height: 8),
                  _txt(_t('الحالة'), size: 9, color: _muted),
                  pw.SizedBox(height: 3),
                  _txt(status, size: 10.5, bold: true, color: statusColor),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// ملف PDF لسند واحد أو أكثر (صفحة لكل سند).
Future<Uint8List> buildSalaryReceiptsPdf(List<SalaryReceipt> receipts) async {
  await _loadFonts();
  final rtl = !AppTr.isEnglish;
  final doc = pw.Document(title: _t('سندات القبض والرواتب'));
  final issued = _stamp(DateTime.now());
  for (final r in receipts) {
    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 30),
          textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Stack(
              children: [
                pw.Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: pw.Container(height: 6, color: _brand),
                ),
                pw.Positioned(
                  left: 0,
                  top: 0,
                  child: pw.Container(width: 150, height: 6, color: _gold),
                ),
                pw.Positioned(
                  left: 36,
                  right: 36,
                  bottom: 14,
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: _txt(
                          '${_t('صدر بتاريخ')} $issued',
                          size: 7.5,
                          color: _muted,
                        ),
                      ),
                      _txt('Fundly', size: 7.5, color: _muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        build: (context) => _page(r, rtl),
      ),
    );
  }
  return doc.save();
}

/// اسم الملف: سند واحد بشهره، أو عدد السندات.
String salaryPdfFileName(List<SalaryReceipt> receipts) {
  if (receipts.length == 1) {
    final r = receipts.first;
    final stamp = r.period.isEmpty ? salaryReceiptNo(r) : r.period;
    return 'salary-receipt-$stamp.pdf';
  }
  return 'salary-receipts-${receipts.length}.pdf';
}

/// مشاركة سند أو أكثر كملف PDF.
Future<void> shareSalaryReceiptsPdf(List<SalaryReceipt> receipts) async {
  if (receipts.isEmpty) return;
  final bytes = await buildSalaryReceiptsPdf(receipts);
  await Printing.sharePdf(bytes: bytes, filename: salaryPdfFileName(receipts));
}
