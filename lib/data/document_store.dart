import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_language.dart';

/// مخزن المستندات المرفوعة داخل التطبيق.
///
/// يُنسخ كل ملف يختاره المستخدم إلى مجلد خاص بالتطبيق (`fundly_docs`)
/// فيبقى محفوظًا بعد إغلاق التطبيق، ويُخزَّن مساره فقط داخل بيانات العنصر
/// (لا حاجة لأي تعديل على مخطط قاعدة البيانات).
class DocumentStore {
  DocumentStore._();

  static const String kFileField = 'الملف المرفق';

  static Directory? _cachedDir;

  static Future<Directory> _docsDir() async {
    final cached = _cachedDir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}fundly_docs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// مجلد ملفات التطبيق (للنسخة السحابية).
  static Future<Directory> docsDir() => _docsDir();

  /// يُستدعى عند الإقلاع ليُعرف المجلد مسبقًا لـ [localPathFor].
  static Future<void> init() async {
    try {
      await _docsDir();
    } catch (_) {
      // بلا مجلد: تبقى المسارات كما هي.
    }
  }

  /// المسار الفعلي على هذا الجهاز: الملف بمساره نفسه إن وُجد، وإلا نسخته
  /// بنفس الاسم في مجلد التطبيق (حُفظ على جوال آخر ونُزّل من السحابة، أو
  /// رفعه الطرف الآخر في سجل مشترك).
  static String localPathFor(String path) {
    if (path.trim().isEmpty) return path;
    try {
      if (File(path).existsSync()) return path;
    } catch (_) {}
    final dir = _cachedDir;
    if (dir == null) return path;
    final candidate = '${dir.path}${Platform.pathSeparator}${fileName(path)}';
    try {
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {}
    return path;
  }

  /// اسم الملف من مساره.
  static String fileName(String path) {
    if (path.trim().isEmpty) return '';
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  /// اسم مختصر للعرض داخل الصفوف.
  static String shortName(String path, {int max = 28}) {
    final name = fileName(path);
    if (name.length <= max) return name;
    return '${name.substring(0, max - 4)}…${name.substring(name.length - 4)}';
  }

  static bool existsSync(String path) {
    if (path.trim().isEmpty) return false;
    try {
      return File(localPathFor(path)).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// فتح منتقي الملفات ونسخ الملف المختار داخل مساحة التطبيق.
  /// يُعيد المسار المحفوظ، أو `null` إذا ألغى المستخدم أو فشل النسخ.
  /// من أين يأتي الملف: الكاميرا، أو المعرض، أو ملفات الجوال (PDF وغيره).
  static Future<String?> _askSource(
    BuildContext context, {
    bool allowFiles = true,
  }) {
    Widget tile(BuildContext sheet, String value, IconData icon, String label) =>
        ListTile(
          leading: Icon(icon, color: const Color(0xFF0E7161)),
          title: Text(
            AppTr.tr(label),
            textAlign: AppTr.alignEnd,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          onTap: () => Navigator.pop(sheet, value),
        );
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Directionality(
          textDirection: AppTr.uiDir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(sheet, 'camera', Icons.photo_camera_outlined,
                    'التقاط صورة بالكاميرا'),
                tile(sheet, 'gallery', Icons.photo_library_outlined,
                    'اختيار صورة من المعرض'),
                if (allowFiles)
                  tile(sheet, 'files', Icons.insert_drive_file_outlined,
                      'اختيار ملف من الجوال (PDF وغيره)'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// يختار ملفًا من الكاميرا أو المعرض أو الملفات — null إن أُلغي.
  static Future<XFile?> pickXFile(
    BuildContext context, {
    bool allowFiles = true,
    int imageQuality = 85,
  }) async {
    final source = await _askSource(context, allowFiles: allowFiles);
    if (source == null) return null;
    try {
      if (source == 'files') {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: false,
          withData: false,
        );
        final file = result?.files.single;
        final path = file?.path;
        if (file == null || path == null || path.isEmpty) return null;
        return XFile(path, name: file.name);
      }
      return await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: imageQuality,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppTr.tr('تعذّر فتح الكاميرا أو الملفات — تحقق من الأذونات'),
            ),
          ),
        );
      }
      return null;
    }
  }

  /// [context] يتيح الاختيار بين الكاميرا والمعرض والملفات؛ بدونه الملفات فقط.
  static Future<String?> pickAndStore({BuildContext? context}) async {
    String? sourcePath;
    var name = '';
    if (context != null) {
      final file = await pickXFile(context);
      if (file == null) return null;
      sourcePath = file.path;
      name = file.name;
    } else {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final picked = result?.files.single;
      sourcePath = picked?.path;
      name = picked?.name ?? '';
    }
    if (sourcePath == null || sourcePath.isEmpty) return null;
    if (name.isEmpty) name = fileName(sourcePath);
    try {
      final dir = await _docsDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final target = '${dir.path}${Platform.pathSeparator}${stamp}_$safeName';
      await File(sourcePath).copy(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// نسخ ملف موجود (صورة من المعرض أو الكاميرا) إلى مساحة التطبيق.
  static Future<String?> copyIntoApp(String sourcePath, String name) async {
    if (sourcePath.trim().isEmpty) return null;
    try {
      final dir = await _docsDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final target = '${dir.path}${Platform.pathSeparator}${stamp}_$safeName';
      await File(sourcePath).copy(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// فتح مستند محفوظ بالتطبيق المناسب على الجهاز.
  /// يُعيد رسالة الخطأ عند الفشل، أو `null` عند النجاح.
  static Future<String?> open(String path) async {
    if (path.trim().isEmpty) return 'لا يوجد ملف مرفق';
    if (!existsSync(path)) return 'الملف المحفوظ غير موجود على الجهاز';
    try {
      final result = await OpenFilex.open(localPathFor(path));
      if (result.type == ResultType.done) return null;
      return result.message.isEmpty ? 'تعذر فتح الملف' : result.message;
    } catch (_) {
      return 'تعذر فتح الملف';
    }
  }

  /// حفظ نص (عقد مثلًا) كملف داخل مساحة التطبيق ثم إعادة مساره.
  static Future<String?> saveText(String fileName, String content) async {
    try {
      final dir = await _docsDir();
      final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final target = '${dir.path}${Platform.pathSeparator}$safeName';
      await File(target).writeAsString(content);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// حذف نسخة الملف المحفوظة داخل التطبيق.
  static Future<void> delete(String path) async {
    if (!existsSync(path)) return;
    try {
      await File(localPathFor(path)).delete();
    } catch (_) {
      // تجاهل: حذف المرفق لا يجب أن يُسقط حذف العنصر نفسه.
    }
  }
}
