import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'document_store.dart';

/// النسخة السحابية لملفات الجهاز: كل ما يُحفظ في مجلد التطبيق (صور
/// الملاحظات ومرفقاتها، المستندات، إيصالات مصروفات الرحلات...) يُرفع إلى
/// مخزن `fundly-files`، ويُنزَّل عند الدخول من جوال آخر.
///
/// ويُنزَّل كذلك ما رفعه الطرف الآخر ويُذكر في سجل مشترك معك (إيصال مصروف
/// في رحلة، صورة في عهدة)، فيظهر عندك بنفس اسمه.
class FundlyFiles {
  FundlyFiles._();

  static const bucket = 'fundly-files';
  static const _maxBytes = 25 * 1024 * 1024;
  static const _timeout = Duration(minutes: 2);
  static const _pageSize = 500;

  static Future<void>? _uploading;
  static Future<void>? _downloading;
  static DateTime? _lastDownload;

  static SupabaseClient get _client => Supabase.instance.client;

  /// مفتاح الملف في المخزن: اسمه بترميز Base64 آمن للروابط، لأن المخزن
  /// لا يقبل الحروف العربية والمسافات في أسماء الملفات.
  static String keyFor(String fileName) =>
      base64Url.encode(utf8.encode(fileName)).replaceAll('=', '');

  static String? nameFor(String key) {
    try {
      var padded = key;
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }

  static String _doneKey(String userId) => 'fundly_uploaded_files_$userId';

  /// رفع ملفات الجهاز الجديدة (ما رُفع قبلًا لا يُعاد).
  static Future<void> syncUp() {
    return _uploading ??= _syncUp().whenComplete(() => _uploading = null);
  }

  static Future<void> _syncUp() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final dir = await DocumentStore.docsDir();
      final prefs = await SharedPreferences.getInstance();
      final done = (prefs.getStringList(_doneKey(user.id)) ?? const <String>[])
          .toSet();
      final storage = _client.storage.from(bucket);
      var changed = false;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = DocumentStore.fileName(entity.path);
        if (name.isEmpty || done.contains(name)) continue;
        try {
          final length = await entity.length();
          if (length > 0 && length <= _maxBytes) {
            await storage
                .uploadBinary(
                  keyFor(name),
                  await entity.readAsBytes(),
                  fileOptions: const FileOptions(upsert: false),
                )
                .timeout(_timeout);
          }
          done.add(name);
          changed = true;
        } on StorageException catch (error) {
          // موجود في المخزن مسبقًا: يكفي.
          final text = '${error.statusCode} ${error.message}'.toLowerCase();
          if (text.contains('409') || text.contains('exist')) {
            done.add(name);
            changed = true;
          }
        } catch (_) {
          // بلا اتصال: يُعاد في المرة التالية.
        }
      }
      if (changed) {
        await prefs.setStringList(_doneKey(user.id), done.toList());
      }
    } catch (_) {
      // لا يوقف التطبيق.
    }
  }

  /// تنزيل ما ليس على هذا الجهاز: ملفاتك، وما يُذكر في سجلات مشتركة معك.
  /// [force] يتجاوز مهلة الدقائق الخمس بين مرتين.
  static Future<void> syncDown({bool force = false}) {
    final last = _lastDownload;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return Future.value();
    }
    return _downloading ??= _syncDown().whenComplete(() {
      _downloading = null;
      _lastDownload = DateTime.now();
    });
  }

  static Future<void> _syncDown() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final dir = await DocumentStore.docsDir();
      final prefs = await SharedPreferences.getInstance();
      final done = (prefs.getStringList(_doneKey(user.id)) ?? const <String>[])
          .toSet();
      final storage = _client.storage.from(bucket);
      var offset = 0;
      var changed = false;
      while (true) {
        final page = await storage
            .list(
              searchOptions: SearchOptions(limit: _pageSize, offset: offset),
            )
            .timeout(_timeout);
        for (final object in page) {
          if (object.id == null) continue;
          final name = nameFor(object.name);
          if (name == null ||
              name.isEmpty ||
              name.contains('/') ||
              name.contains('\\')) {
            continue;
          }
          final target = File('${dir.path}${Platform.pathSeparator}$name');
          if (!await target.exists()) {
            try {
              final bytes = await storage
                  .download(object.name)
                  .timeout(_timeout);
              await target.writeAsBytes(bytes, flush: true);
            } catch (_) {
              continue;
            }
          }
          // موجود في السحابة: لا يُرفع مرة أخرى.
          if (done.add(name)) changed = true;
        }
        if (page.length < _pageSize) break;
        offset += page.length;
      }
      if (changed) {
        await prefs.setStringList(_doneKey(user.id), done.toList());
      }
    } catch (_) {
      // بلا اتصال: يُعاد عند الرجوع للتطبيق.
    }
  }
}
