import 'package:flutter/material.dart' hide Text, Align;
import 'package:printing/printing.dart';

import '../data/report_document.dart';
import '../l10n/app_language.dart';
import '../l10n/tr_widgets.dart';
import '../widgets/shared/app_design.dart';
import '../data/subscription_plans.dart';
import '../widgets/shared/plan_gate.dart';

/// معاينة التقرير/الأرشيف كملف PDF بصفحاته الفعلية، مع أزرار الطباعة
/// والمشاركة (واتساب، بريد، حفظ في الملفات...).
class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({super.key, required this.document});

  final ReportDocument document;

  static const _accent = Color(0xFF0A5A50);

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String failure,
  ) async {
    // الطباعة والمشاركة PDF من الباقة الذهبية.
    if (!PlanGate.hasFeature(context, PlanFeatures.pdf)) return;
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

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
                document.title,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              )),
              Text(
                document.archive ? 'معاينة الأرشيف' : 'معاينة التقرير',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
        body: PdfPreview(
          build: (format) => buildReportPdf(document, format),
          initialPageFormat: kReportPageFormat,
          pdfFileName: document.fileName,
          // الطباعة والمشاركة من الشريط السفلي أدناه بأزرار واضحة.
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
          onError: (context, error) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'تعذّر تجهيز الملف على هذا الجهاز.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
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
                      () => shareReportDocument(document),
                      'تعذّرت مشاركة الملف',
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 19),
                    label: const Text(
                      'مشاركة / إرسال',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _run(
                      context,
                      () => printReportDocument(document),
                      'تعذّر فتح الطباعة',
                    ),
                    icon: const Icon(Icons.print_rounded, size: 19),
                    label: const Text(
                      'طباعة',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: _accent, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.rField),
                      ),
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
