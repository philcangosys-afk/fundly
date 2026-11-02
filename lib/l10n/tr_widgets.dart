import 'package:flutter/material.dart' as m;
import 'package:flutter/material.dart' hide Text, Align;

import 'app_language.dart';

/// عناصر "ظلّية" تحل محل عناصر فلاتر بنفس الاسم في ملفات الشاشات
/// (عبر `hide Text, Align` في استيراد material) فتترجم النص وتقلب
/// المحاذاة الفيزيائية عند الإنجليزية دون تعديل آلاف مواضع الاستدعاء —
/// وتبقى قابلة لـ const لأن الترجمة تتم في build وقت التشغيل.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    // «عنوان الحقل *»: نجمة الحقل الإلزامي حمراء في كل التطبيق.
    if (data.length > 2 && data.endsWith(' *')) {
      return m.Text.rich(
        TextSpan(
          children: [
            TextSpan(text: AppTr.tr(data.substring(0, data.length - 2))),
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: Color(0xFFC4392E),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        style: style,
        textAlign: AppTr.mapTextAlign(textAlign),
        textDirection: textDirection,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }
    return m.Text(
      AppTr.tr(data),
      style: style,
      textAlign: AppTr.mapTextAlign(textAlign),
      textDirection: textDirection,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}

class Align extends StatelessWidget {
  const Align({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    this.child,
  });

  final AlignmentGeometry alignment;
  final double? widthFactor;
  final double? heightFactor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return m.Align(
      alignment: AppTr.mapAlignment(alignment),
      widthFactor: widthFactor,
      heightFactor: heightFactor,
      child: child,
    );
  }
}
