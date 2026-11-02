import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text, Align;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';

/// معاينة ورقة الطباعة (A4) ثم الطباعة أو حفظها PDF ومشاركتها.
class TemplatePrintScreen extends StatelessWidget {
  const TemplatePrintScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.buildPdf,
  });

  final String title;
  final String fileName;

  /// يبني ملف PDF بالبيانات الحالية (مرسوم داخل التطبيق بلا متصفح).
  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;

  static const _accent = Color(0xFF0A5A50);

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String failure,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure), behavior: SnackBarBehavior.floating),
      );
    }
  }

  String get _pdfName {
    final clean = fileName.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), '-').trim();
    return '${clean.isEmpty ? 'document' : clean}.pdf';
  }

  Future<Uint8List> _pdf(PdfPageFormat format) => buildPdf(format);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppTr.uiDir,
      child: Scaffold(
        backgroundColor: const Color(0xFFEFF3F2),
        appBar: AppBar(
          backgroundColor: AppTheme.page,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppTheme.title,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              )),
              const Text(
                'معاينة الطباعة',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
        body: PdfPreview(
          build: _pdf,
          initialPageFormat: PdfPageFormat.a4,
          pdfFileName: _pdfName,
          useActions: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          maxPageWidth: 720,
          scrollViewDecoration: const BoxDecoration(color: Color(0xFFEFF3F2)),
          pdfPreviewPageDecoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22022E2A),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          loadingWidget: const Center(
            child: CircularProgressIndicator(color: _accent),
          ),
          onError: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تعذّر تجهيز الملف على هذا الجهاز.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x14022E2A),
                  blurRadius: 12,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _run(
                      context,
                      () => Printing.layoutPdf(
                        name: _pdfName,
                        format: PdfPageFormat.a4,
                        onLayout: _pdf,
                      ),
                      'تعذّرت الطباعة',
                    ),
                    icon: const Icon(Icons.print_rounded, size: 19),
                    label: const Text(
                      'طباعة',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _run(
                      context,
                      () async => Printing.sharePdf(
                        bytes: await _pdf(PdfPageFormat.a4),
                        filename: _pdfName,
                      ),
                      'تعذّرت مشاركة الملف',
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 19),
                    label: const Text(
                      'مشاركة PDF',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
