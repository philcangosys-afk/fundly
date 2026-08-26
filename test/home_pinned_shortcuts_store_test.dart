import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fundly/data/home_pinned_shortcuts_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists record pins and migrates legacy module pins', () async {
    SharedPreferences.setMockInitialValues({
      'home_pinned_shortcuts_v1': [
        jsonEncode({'id': 'personal', 'title': 'الالتزامات الشخصية'}),
      ],
    });

    final legacy = await HomePinnedShortcutsStore.load();
    expect(legacy.single.moduleId, 'personal');

    const recordPin = HomePinnedShortcut(
      id: 'personal:entry-42',
      title: 'سداد القسط',
      moduleId: 'personal',
      subtitle: 'قسط',
    );
    await HomePinnedShortcutsStore.save([recordPin]);

    final restored = await HomePinnedShortcutsStore.load();
    expect(restored.single.id, 'personal:entry-42');
    expect(restored.single.moduleId, 'personal');
    expect(restored.single.subtitle, 'قسط');
  });
}
