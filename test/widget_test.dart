import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fundly/data/personal_entries_repository.dart';
import 'package:fundly/main.dart' show HomePage;
import 'package:fundly/screens/people_management_screen.dart';
import 'package:fundly/screens/personal_commitments_screen.dart';
import 'package:fundly/screens/projects_activities_screen.dart';
import 'package:fundly/screens/shared_commitments_screen.dart';
import 'package:fundly/widgets/entry_overview_card.dart';
import 'package:fundly/widgets/management_dashboard_chrome.dart';

class _FakePersonalEntriesRepository implements PersonalEntriesRepository {
  final List<PersonalEntryRecord> records;
  PersonalEntryRecord? updatedEntry;
  String? deletedEntryId;

  _FakePersonalEntriesRepository({this.records = const []});

  @override
  Future<PersonalEntryRecord> create(
    PersonalEntryRecord entry, {
    XFile? attachment,
  }) async => entry;

  @override
  Future<List<PersonalEntryRecord>> fetchAll() async => records;

  @override
  Future<void> delete(String entryId) async {
    deletedEntryId = entryId;
  }

  @override
  Future<PersonalEntryRecord> update(
    PersonalEntryRecord entry, {
    XFile? attachment,
  }) async {
    updatedEntry = entry;
    return entry;
  }
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PersonalCommitmentsScreen(
        repository: _FakePersonalEntriesRepository(),
      ),
    ),
  );
  await tester.tap(find.text('إضافة التزام'));
  await tester.pumpAndSettle();
}

Future<void> _pumpSharedTypeForm(WidgetTester tester, String type) async {
  await tester.pumpWidget(const MaterialApp(home: SharedCommitmentsScreen()));
  await tester.tap(find.text('إضافة التزام مشترك'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(type).last);
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('personal dashboard follows up, searches, filters, and edits', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakePersonalEntriesRepository(
      records: const [
        PersonalEntryRecord(
          id: 'expense-1',
          category: 'financial',
          entryType: 'مصروف',
          title: 'فاتورة الكهرباء',
          amount: 1250,
          dueDate: '15/8/2026',
          status: 'متأخرة',
          details: {},
        ),
        PersonalEntryRecord(
          id: 'task-1',
          category: 'administrative',
          entryType: 'مهمة',
          title: 'مهمة إدارية',
          amount: 0,
          dueDate: '20/8/2026',
          status: 'نشطة',
          details: {},
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: PersonalCommitmentsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('الالتزامات الشخصية'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal-follow-up-center')),
      findsOneWidget,
    );
    expect(find.text('مركز المتابعة'), findsOneWidget);
    expect(find.text('المزيد'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsOneWidget);
    expect(find.text('مستحقات'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(
      tester.getCenter(find.text('الكل')).dx,
      greaterThan(tester.getCenter(find.text('المالية')).dx),
    );
    expect(
      tester.getCenter(find.text('الأحدث أولاً')).dy,
      closeTo(tester.getCenter(find.text('جميع الالتزامات')).dy, 2),
    );
    expect(
      tester.getCenter(find.text('الأحدث أولاً')).dx,
      lessThan(tester.getCenter(find.text('جميع الالتزامات')).dx),
    );
    await tester.tap(find.byKey(const ValueKey('personal-follow-up-more')));
    await tester.pumpAndSettle();
    expect(find.text('قائمة المتابعة الكاملة'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal-follow-up-list')),
      findsOneWidget,
    );
    expect(find.text('فاتورة الكهرباء'), findsWidgets);
    expect(find.text('مهمة إدارية'), findsWidgets);
    Navigator.of(tester.element(find.text('قائمة المتابعة الكاملة'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('personal-filter-button')));
    await tester.pumpAndSettle();
    for (final label in [
      'الكل',
      'المالية',
      'مستند',
      'عنصر إداري',
      'بيانات وحسابات',
      'مناسبة / إشتراك / هدية',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('الكل').last);
    await tester.pumpAndSettle();
    expect(find.text('فاتورة الكهرباء'), findsOneWidget);
    expect(find.text('مهمة إدارية'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('personal-search-field')),
      'مهمة',
    );
    await tester.pump();
    expect(find.text('فاتورة الكهرباء'), findsNothing);
    expect(find.text('مهمة إدارية'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('personal-search-field')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('personal-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المالية').last);
    await tester.pumpAndSettle();
    expect(find.text('فاتورة الكهرباء'), findsOneWidget);
    expect(find.text('مهمة إدارية'), findsNothing);
    expect(find.text('متابعة المالية'), findsOneWidget);
    expect(find.textContaining('1250.00'), findsOneWidget);
    expect(find.text('متأخر'), findsOneWidget);
    final sortControl = find.byTooltip('ترتيب الالتزامات');
    expect(
      tester.getCenter(sortControl).dy,
      closeTo(tester.getCenter(find.text('المالية').last).dy, 2),
    );

    await tester.tap(find.byKey(const ValueKey('personal-follow-up-more')));
    await tester.pumpAndSettle();
    expect(find.text('متابعة المالية'), findsWidgets);
    expect(find.text('فاتورة الكهرباء'), findsWidgets);
    expect(find.text('مهمة إدارية'), findsNothing);
    Navigator.of(tester.element(find.text('متابعة المالية').last)).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('خيارات الالتزام'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('خيارات الالتزام'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل'), findsOneWidget);
    expect(find.text('إضافة'), findsOneWidget);

    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل الالتزام'), findsOneWidget);
  });

  testWidgets('keeps list cards separate from add-entry choices', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final screens = <Widget>[
      PersonalCommitmentsScreen(
        repository: _FakePersonalEntriesRepository(
          records: const [
            PersonalEntryRecord(
              id: 'expense-card',
              category: 'financial',
              entryType: 'مصروف',
              title: 'فاتورة تجريبية',
              amount: 100,
              dueDate: '1/8/2026',
              status: 'نشطة',
              details: {},
            ),
          ],
        ),
      ),
      const SharedCommitmentsScreen(),
      const ProjectsActivitiesScreen(),
      const PeopleManagementScreen(),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
      expect(find.byType(EntryOverviewCard), findsNothing);
      final layoutException = tester.takeException();
      expect(
        layoutException,
        isNull,
        reason: 'Overflow in ${screen.runtimeType}',
      );
    }

    await _pumpScreen(tester);
    expect(find.text('اختيار نوع الإدخال'), findsOneWidget);
    expect(find.text('إدخال مالي'), findsOneWidget);
    expect(find.text('إدخال إداري'), findsOneWidget);
    expect(find.text('إدخال البيانات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('management pages share a pinned header with distinct colors', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final screens = <(Widget, String)>[
      (
        PersonalCommitmentsScreen(repository: _FakePersonalEntriesRepository()),
        'الالتزامات الشخصية',
      ),
      (const SharedCommitmentsScreen(), 'الالتزامات المشتركة'),
      (
        const ProjectsActivitiesScreen(),
        'العقارات / الأنشطة التجارية / المعدات وأخرى',
      ),
      (const PeopleManagementScreen(), 'إدارة الأشخاص والجهات'),
    ];
    final firstColors = <Color>{};

    for (final (screen, title) in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      final headerFinder = find.byType(ManagementDashboardHeader);
      expect(headerFinder, findsOneWidget);
      final header = tester.widget<ManagementDashboardHeader>(headerFinder);
      firstColors.add(header.colors.first);
      expect(header.title, title);

      final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(appBar.pinned, isTrue);
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    expect(firstColors, hasLength(screens.length));
  });

  testWidgets('property categories fit inside their pinned controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: ProjectsActivitiesScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('projects-category-list')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('pinned-dashboard-controls')))
          .height,
      242,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('peer management pages use the complete compact dashboard', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final screens = <Widget>[
      const SharedCommitmentsScreen(),
      const ProjectsActivitiesScreen(),
      const PeopleManagementScreen(),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      expect(find.byType(ManagementSearchBar), findsOneWidget);
      expect(find.byType(ManagementFollowUpCenter), findsOneWidget);
      expect(find.text('مركز المتابعة'), findsOneWidget);
      expect(find.text('التصنيفات'), findsOneWidget);
      expect(find.byType(ManagementCategoryTab), findsWidgets);
      expect(find.byType(ManagementSortHeader), findsOneWidget);
      expect(find.text('الأحدث أولاً'), findsOneWidget);
      final sortHeader = tester.widget<ManagementSortHeader>(
        find.byType(ManagementSortHeader),
      );
      expect(
        tester.getCenter(find.text('الأحدث أولاً')).dy,
        closeTo(tester.getCenter(find.text(sortHeader.title)).dy, 2),
      );
      expect(find.byType(ManagementCompactCard), findsWidgets);
      expect(
        tester.getSize(find.byType(ManagementCompactCard).first).height,
        94,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'dashboard followup and categories stay pinned while lists move',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final personalRecords = List.generate(
        8,
        (index) => PersonalEntryRecord(
          id: 'pinned-$index',
          category: 'administrative',
          entryType: 'مهمة',
          title: 'مهمة متابعة $index',
          amount: index,
          dueDate: '20/8/2026',
          status: 'نشطة',
          details: const {},
        ),
      );
      final screens = <Widget>[
        PersonalCommitmentsScreen(
          repository: _FakePersonalEntriesRepository(records: personalRecords),
        ),
        const SharedCommitmentsScreen(),
        const ProjectsActivitiesScreen(),
        const PeopleManagementScreen(),
      ];

      for (final screen in screens) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();

        final scrollView = find.byType(CustomScrollView);
        final pinnedControls = find.byKey(
          const ValueKey('pinned-dashboard-controls'),
        );
        final verticalScrollable = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              (widget.axisDirection == AxisDirection.down ||
                  widget.axisDirection == AxisDirection.up),
        );
        final scrollPosition = tester
            .state<ScrollableState>(verticalScrollable)
            .position;

        await tester.drag(scrollView, const Offset(0, -100));
        await tester.pumpAndSettle();
        final pinnedCenter = tester.getCenter(pinnedControls).dy;
        final firstOffset = scrollPosition.pixels;

        if (scrollPosition.maxScrollExtent > firstOffset + 5) {
          await tester.drag(scrollView, const Offset(0, -40));
          await tester.pumpAndSettle();
          expect(tester.getCenter(pinnedControls).dy, closeTo(pinnedCenter, 1));
          expect(scrollPosition.pixels, greaterThan(firstOffset + 5));
        } else {
          expect(firstOffset, closeTo(scrollPosition.maxScrollExtent, 1));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('management dashboards use unified flat green followup', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const screens = <Widget>[
      SharedCommitmentsScreen(),
      ProjectsActivitiesScreen(),
      PeopleManagementScreen(),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      final center = tester.widget<ManagementFollowUpCenter>(
        find.byType(ManagementFollowUpCenter),
      );
      expect(center.accentColor, const Color(0xFF047857));
      final surface = tester.widget<Container>(
        find.byKey(const ValueKey('management-follow-up-surface')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFFAF7EC));
      expect(decoration.border!.top.color, const Color(0xFFE8DCB5));
      expect(
        find.descendant(
          of: find.byType(ManagementFollowUpCenter),
          matching: find.byIcon(Icons.arrow_forward_ios_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ManagementFollowUpCenter),
          matching: find.text('المزيد'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('management-flat-metric-0')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('management-flat-metric-1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(
      const MaterialApp(home: ProjectsActivitiesScreen()),
    );
    await tester.pumpAndSettle();

    for (final label in ['الكل', 'العقارات', 'الأنشطة التجارية']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('المعدات'), findsWidgets);
    expect(find.textContaining('صيانة'), findsWidgets);
    expect(find.text('مشاريع'), findsNothing);
    expect(find.text('أنشطة تجارية'), findsNothing);
    expect(find.text('تحتاج متابعة'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('management detail pages use the personal compact template', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const screens = <({Widget screen, String itemTitle})>[
      (screen: SharedCommitmentsScreen(), itemTitle: 'الرحلة إلى دبي'),
      (screen: PeopleManagementScreen(), itemTitle: 'أحمد محمد سالم'),
      (screen: ProjectsActivitiesScreen(), itemTitle: 'فيلا الياسمينة'),
    ];

    for (final item in screens) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: item.screen));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 4; attempt++) {
        if (find.text(item.itemTitle).evaluate().isNotEmpty) break;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(find.text(item.itemTitle), findsOneWidget);
      await tester.tap(find.text(item.itemTitle).first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('shared-detail-page-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shared-detail-page-tabs')),
        findsOneWidget,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 60);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('people details shows updated header data and actions menu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PeopleManagementScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('أحمد محمد سالم').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('رقم التواصل: 0501234567'), findsOneWidget);
    expect(find.textContaining('تحتاج متابعة (عام): 1'), findsWidgets);
    expect(
      find.byKey(const ValueKey('add-person-detail-entry')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('تعديل البيانات'), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
    expect(find.text('تجميد / إلغاء التجميد'), findsOneWidget);
    expect(find.text('تثبيت / إلغاء التثبيت'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('أحمد محمد سالم').first);
    await tester.pumpAndSettle();
    expect(find.text('مجمّد'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();

    expect(find.text('أحمد محمد سالم'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('people creation separates person and entity classifications', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PeopleManagementScreen()));
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();

    expect(find.text('اختيار نوع الإضافة'), findsOneWidget);
    expect(find.text('إضافة شخص'), findsOneWidget);
    expect(find.text('إضافة جهة'), findsOneWidget);

    await tester.tap(find.text('إضافة جهة'));
    await tester.pumpAndSettle();
    expect(find.text('إدخالات الجهات'), findsOneWidget);
    expect(find.text('إضافة تواصل'), findsOneWidget);
    expect(find.text('إضافة مستند'), findsOneWidget);
    expect(find.text('الشركات'), findsOneWidget);
    expect(find.text('بنك'), findsOneWidget);

    await tester.tap(find.text('الشركات'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة جهة · الشركات'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'اسم الجهة'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'رقم الهاتف'), findsOneWidget);

    Navigator.of(
      tester.element(find.widgetWithText(TextField, 'اسم الجهة')),
    ).pop();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة شخص'));
    await tester.pumpAndSettle();
    expect(find.text('إدخالات الأشخاص'), findsOneWidget);
    expect(find.text('قريب'), findsWidgets);

    await tester.tap(find.text('قريب').last);
    await tester.pumpAndSettle();
    expect(find.text('إضافة شخص · قريب'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'الاسم'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'البريد الإلكتروني'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'الاسم'),
      'شخص تجريبي',
    );
    await tester.tap(find.text('حفظ الشخص'));
    await tester.pumpAndSettle();
    expect(find.text('شخص تجريبي'), findsOneWidget);

    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة شخص'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('الهوية'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('الهوية'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة مستند · الهوية'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'اسم الشخص'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projects add button shows activity types then details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProjectsActivitiesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة').first);
    await tester.pumpAndSettle();

    expect(find.text('اختيار نوع الإضافة'), findsOneWidget);
    expect(find.byKey(const ValueKey('projects-entry-type-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('projects-entry-type-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('projects-entry-remove-activity')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('projects-entry-type-0')));
    await tester.pumpAndSettle();
    expect(find.text('إضافة أصل / نشاط'), findsOneWidget);
    expect(find.text('نوع النشاط المختار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home summary opens in a modal and modules navigate', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('نظرة شاملة على يومك وأعمالك'), findsNothing);
    expect(find.text('حياتك كلها تدار من هنا'), findsNothing);
    expect(
      find.text('أموالك، أصولك، التزاماتك وعلاقاتك في لوحة واحدة'),
      findsOneWidget,
    );
    final homeHeader = tester.widget<SliverAppBar>(
      find.byType(SliverAppBar).first,
    );
    expect(homeHeader.expandedHeight, 88);
    expect(homeHeader.toolbarHeight, 88);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('home-header-tagline')))
          .textAlign,
      TextAlign.center,
    );
    expect(find.text('أبحث عن أي شيء'), findsOneWidget);
    expect(find.text('الملخص الشامل'), findsOneWidget);
    expect(find.text('اعرض واعرف أمورك بضغطة زر'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.text('مركز المتابعة'), findsNothing);
    expect(find.text('1. الملخص الشامل'), findsNothing);
    expect(find.text('إجمالي الدخل'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-global-summary-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byKey(const ValueKey('global-summary-sheet')), findsOneWidget);
    expect(find.text('1. الملخص الشامل'), findsOneWidget);
    expect(find.text('2. معلومات الوحدات'), findsOneWidget);
    expect(find.text('إجمالي الدخل'), findsOneWidget);
    expect(find.text('إجمالي المصروفات'), findsOneWidget);
    expect(find.text('إجمالي الديون'), findsOneWidget);
    expect(find.text('المستندات'), findsOneWidget);
    expect(find.text('التفويضات'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-selected-summary')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('summary-income')));
    await tester.pumpAndSettle();
    final incomeRow = find.descendant(
      of: find.byKey(const ValueKey('summary-income')),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(incomeRow).onTap!();
    await tester.pumpAndSettle();
    final summaryList = find.byKey(const ValueKey('global-summary-sheet'));
    await tester.fling(summaryList, const Offset(0, -1600), 1800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-selected-summary')), findsOneWidget);
    expect(find.text('إرسال ملخص إجمالي الدخل'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-complete-summary')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('send-complete-summary'))).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('summary-authorizations')))
            .dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('close-global-summary')));
    await tester.pumpAndSettle();
    expect(find.text('1. الملخص الشامل'), findsNothing);
    expect(find.byKey(const ValueKey('send-selected-summary')), findsNothing);
    expect(find.byKey(const ValueKey('global-summary-sheet')), findsNothing);
    expect(find.text('أدر أموالك وأملاكك باحترافية'), findsOneWidget);
    expect(find.text('ملخص سريع لكل جزء من أعمالك'), findsNothing);
    expect(find.text('ديون لك: 500 درهم'), findsOneWidget);
    expect(find.text('ديون عليك: 200 درهم'), findsOneWidget);
    expect(find.text('الالتزامات النشطة: 8'), findsOneWidget);
    expect(find.text('التزامات مشتركة: 3'), findsOneWidget);
    expect(find.text('غير مفعلة: 2'), findsOneWidget);
    expect(find.text('إدارة الأشخاص والجهات'), findsOneWidget);
    expect(
      find.text('العقارات/الأنشطة التجارية/المعدات وأخرى'),
      findsOneWidget,
    );
    expect(find.text('مستند واحد قريب الانتهاء'), findsNWidgets(2));
    expect(find.text('فتح الوحدة'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNWidgets(4));

    final categoriesGrid = find.byKey(const ValueKey('home-categories-grid'));
    expect(
      (tester.widget<GridView>(categoriesGrid).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      1,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-category-0'))).height,
      lessThanOrEqualTo(108),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-categories-layout-toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey('home-categories-layout-toggle')),
    );
    await tester.pumpAndSettle();
    expect(
      (tester.widget<GridView>(categoriesGrid).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    final compactPersonalTitle = tester.widget<Text>(
      find.byKey(const ValueKey('home-category-title-0')),
    );
    expect(compactPersonalTitle.data, 'الالتزامات الشخصية');
    expect(compactPersonalTitle.maxLines, 2);
    expect(compactPersonalTitle.overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(find.byKey(const ValueKey('home-category-0'))).height,
      lessThanOrEqualTo(124),
    );

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('home-category-1')));
    await tester.tap(find.byKey(const ValueKey('home-category-1')));
    await tester.pumpAndSettle();
    expect(find.byType(SharedCommitmentsScreen), findsOneWidget);
  });

  testWidgets('opens the dynamic expense entry form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.textContaining('التقارير'), findsOneWidget);
    expect(find.text('التفويضات'), findsNothing);
    expect(find.text('المحافظ'), findsOneWidget);
    expect(find.text('المزيد'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-account-avatar-entry')));
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.textContaining('التقارير'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('إنشاء تقرير عام'), findsOneWidget);

    await tester.tap(find.text('الرئيسية'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('أدر أموالك وأملاكك باحترافية'), findsOneWidget);

    await _pumpScreen(tester);
    expect(find.text('إدخال مالي'), findsOneWidget);
    expect(find.text('إدخال إداري'), findsOneWidget);
    expect(find.text('إدخال البيانات'), findsOneWidget);
    await tester.tap(find.text('إدخال مالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المصروفات الشخصية'));
    await tester.pumpAndSettle();

    expect(find.text('إضافة المصروفات الشخصية'), findsOneWidget);
    expect(find.text('الحقول الأساسية'), findsOneWidget);
    expect(find.text('الحقول الإضافية'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'المبلغ'), findsOneWidget);
    expect(find.text('التصنيف الرئيسي'), findsOneWidget);
    expect(find.text('التصنيف الفرعي'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.widgetWithText(TextFormField, 'جهة الصرف'), findsNothing);
    expect(find.text('إرفاق مستند'), findsNothing);

    await tester.tap(find.text('الحقول الإضافية'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'جهة الصرف'), findsOneWidget);
    expect(find.text('إرفاق مستند'), findsOneWidget);
    expect(find.text('حفظ المصروفات الشخصية'), findsOneWidget);
  });

  testWidgets('opens financial custody with logical fields', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpScreen(tester);
    await tester.tap(find.text('إدخال مالي'));
    await tester.pumpAndSettle();

    expect(find.text('عهدة مالية'), findsOneWidget);
    await tester.tap(find.text('عهدة مالية'));
    await tester.pumpAndSettle();

    expect(find.text('إضافة عهدة مالية'), findsOneWidget);
    for (final label in [
      'اسم العهدة',
      'قيمة العهدة',
      'اسم المستلم',
      'نوع العهدة',
      'تاريخ الاستحقاق والإرجاع',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('الحقول الإضافية'));
    await tester.pumpAndSettle();
    for (final label in [
      'تاريخ التسليم',
      'الجهة أو القسم',
      'الغرض من العهدة',
      'حالة العهدة',
      'رقم المرجع أو المستند',
      'ملاحظات',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('حفظ عهدة مالية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters expense subcategories by main category', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('إدخال مالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المصروفات الشخصية'));
    await tester.pumpAndSettle();

    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await tester.tap(dropdowns.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مواصلات').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();

    expect(find.text('تطبيقات توصيل'), findsOneWidget);
    expect(find.text('نقل عام وتاكسي'), findsOneWidget);
    expect(find.text('أخرى'), findsOneWidget);
    expect(find.text('+ إضافة أخرى'), findsOneWidget);
    expect(find.text('بقالة وسوبرماركت'), findsNothing);

    await tester.tap(find.text('+ إضافة أخرى').last);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'اسم التصنيف الجديد'),
      findsOneWidget,
    );
  });

  testWidgets('shows the requested administrative entry types', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('إدخال إداري'));
    await tester.pumpAndSettle();

    for (final label in [
      'مستند',
      'مهمة',
      'موعد',
      'عادة',
      'ملاحظات',
      'مناسبة',
      'اشتراكات',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('opens the requested data entry forms', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('إدخال البيانات'));
    await tester.pumpAndSettle();

    expect(find.text('حسابات'), findsOneWidget);
    expect(find.text('أدوية وبياناتها'), findsOneWidget);
    expect(find.text('مواقع وأماكن'), findsOneWidget);

    await tester.tap(find.text('أدوية وبياناتها'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة أدوية وبياناتها'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'اسم الدواء'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'لمن هذا الدواء'),
      findsOneWidget,
    );
  });

  testWidgets('saves an entry and closes the form', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('إدخال البيانات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حسابات'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم الحساب'),
      'حساب تجريبي',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم المستخدم'),
      'test-user',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'كلمة السر'),
      'secret',
    );
    await tester.tap(find.text('التصنيف الرئيسي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خدمات رقمية').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيقات').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('حفظ حسابات'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('حفظ حسابات'));
    await tester.tap(find.text('حفظ حسابات'));
    await tester.pumpAndSettle();

    expect(find.text('إضافة حسابات'), findsNothing);
    expect(find.text('حساب تجريبي'), findsOneWidget);
    expect(find.text('جارٍ الحفظ...'), findsNothing);
  });

  testWidgets('shows unified details sections and updates the commitment', (
    WidgetTester tester,
  ) async {
    final repository = _FakePersonalEntriesRepository(
      records: const [
        PersonalEntryRecord(
          id: 'entry-1',
          category: 'financial',
          entryType: 'مصروف',
          title: 'إيجار المكتب',
          amount: 2500,
          dueDate: '25/7/2026',
          status: 'نشطة',
          details: {'جهة الصرف': 'المالك'},
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: PersonalCommitmentsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('إيجار المكتب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إيجار المكتب'));
    await tester.pumpAndSettle();

    expect(find.text('تفاصيل مصروف'), findsOneWidget);
    expect(find.text('تحديث بيانات الالتزام'), findsNothing);
    expect(find.text('2500'), findsOneWidget);
    expect(find.text('25/7/2026'), findsWidgets);
    expect(
      find.byKey(const ValueKey('compact-personal-details')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compact-details-header')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inline-details-tabs')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('compact-details-header')))
          .height,
      lessThan(260),
    );
    for (final section in ['الملخص', 'السجل', 'المستندات', 'المتابعة']) {
      expect(find.text(section), findsOneWidget);
    }

    final addButton = find.byKey(const ValueKey('add-commitment-attachment'));
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    final addButtonCenter = tester.getCenter(addButton);
    expect(
      addButtonCenter.dx,
      inInclusiveRange(
        40.0,
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 40.0,
      ),
    );

    await tester.tap(find.text('المستندات'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد مستندات'), findsOneWidget);

    await tester.tap(find.text('الملخص'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compact-details-edit')));
    await tester.pumpAndSettle();
    for (final action in ['تعديل', 'مشاركة', 'حذف', 'أرشيف']) {
      expect(find.text(action), findsOneWidget);
    }
    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم الالتزام'),
      'إيجار المكتب الجديد',
    );
    await tester.tap(find.text('حفظ التغييرات'));
    await tester.pumpAndSettle();

    expect(repository.updatedEntry?.title, 'إيجار المكتب الجديد');
    expect(find.text('إيجار المكتب الجديد'), findsWidgets);
    expect(find.text('تم تحديث الالتزام بنجاح'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compact-details-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرشيف'));
    await tester.pumpAndSettle();
    expect(repository.updatedEntry?.status, 'مؤرشف');
    expect(find.text('مؤرشف'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('compact-details-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الالتزام'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(repository.deletedEntryId, 'entry-1');
    expect(find.text('إيجار المكتب الجديد'), findsNothing);
  });

  testWidgets('shows shared commitment type choices', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SharedCommitmentsScreen()));

    for (final label in ['الرحلات / السفر', 'جمعيات مالية', 'اللقاءات']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('إضافة التزام مشترك'));
    await tester.pumpAndSettle();

    expect(find.text('اختيار نوع الالتزام المشترك'), findsOneWidget);
    for (final label in ['الرحلة / السفر', 'جمعيات مالية', 'اللقاءات']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('opens association fields from shared commitments', (
    WidgetTester tester,
  ) async {
    await _pumpSharedTypeForm(tester, 'جمعيات مالية');

    for (final label in [
      'اسم الالتزام',
      'الأعضاء',
      'المسؤول',
      'تاريخ البداية',
      'تاريخ النهاية',
      'قيمة الاشتراك',
      'دور الاستلام',
      'عدد الشهور',
      'موعد الدفع الشهري',
      'ملاحظات',
    ]) {
      expect(find.widgetWithText(TextFormField, label), findsOneWidget);
    }
    expect(find.text('العملة (اختياري)'), findsOneWidget);
  });

  testWidgets('opens travel fields from shared commitments', (
    WidgetTester tester,
  ) async {
    await _pumpSharedTypeForm(tester, 'الرحلة / السفر');

    for (final label in [
      'اسم الرحلة / السفر',
      'الميزانية',
      'التقسيم المالي',
      'الأعضاء مع المسؤول',
      'المسؤول',
      'الوجهة',
      'تاريخ السفر',
      'تاريخ العودة',
      'ملاحظات',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('opens meeting fields from shared commitments', (
    WidgetTester tester,
  ) async {
    await _pumpSharedTypeForm(tester, 'اللقاءات');

    for (final label in [
      'اسم الالتزام',
      'الأعضاء',
      'المسؤول',
      'المبلغ',
      'مكان التجمع',
      'تاريخ التجمع',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
