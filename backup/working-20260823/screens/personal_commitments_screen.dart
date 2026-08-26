import 'package:flutter/material.dart';

class PersonalCommitmentsScreen extends StatefulWidget {
  const PersonalCommitmentsScreen({super.key});

  @override
  State<PersonalCommitmentsScreen> createState() =>
      _PersonalCommitmentsScreenState();
}

class _PersonalCommitmentsScreenState extends State<PersonalCommitmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatus = 'الكل';

  final List<String> _statusFilters = const [
    'الكل',
    'نشطة',
    'مكتملة',
    'متأخرة',
    'قريبة الاستحقاق',
  ];

  final List<_CommitmentItem> _items = const [
    _CommitmentItem(
      title: 'فاتورة المياه والكهرباء',
      status: 'قريبة الاستحقاق',
      statusColor: Color(0xFFD97706),
      amount: 150,
      dueDate: '2/2/2026',
      progress: 0.30,
      remainingInstallments: 1,
      lastUpdate: '2/5/2025',
      icon: Icons.receipt_long,
      iconColor: Color(0xFFD97706),
      iconBackground: Color(0xFFFDEFD7),
    ),
    _CommitmentItem(
      title: 'قسط السيارة الشهري',
      status: 'نشطة',
      statusColor: Color(0xFF0F9F6E),
      amount: 1250,
      dueDate: '10/2/2026',
      progress: 0.65,
      remainingInstallments: 6,
      lastUpdate: '2/5/2025',
      icon: Icons.directions_car,
      iconColor: Color(0xFF0F9F6E),
      iconBackground: Color(0xFFDDF7EE),
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_CommitmentItem> _filteredItems() {
    final q = _searchController.text.trim();
    return _items
        .where((item) {
          final statusMatches =
              _selectedStatus == 'الكل' || item.status == _selectedStatus;
          final queryMatches =
              q.isEmpty || item.title.contains(q) || item.status.contains(q);
          return statusMatches && queryMatches;
        })
        .toList(growable: false);
  }

  void _openNewEntrySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.84,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close,
                          size: 30,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const Spacer(),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'اختيار نوع الإدخال',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'اختر النوع المناسب للمتابعة إلى تفاصيل الإدخال',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.playlist_add_check_rounded,
                          color: Color(0xFF2563EB),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.95,
                      children: const [
                        _EntryOptionCard(
                          title: 'إدخال مالي',
                          subtitle:
                              'المدفوعات، الإيرادات، الأقساط والالتزامات المالية',
                          count: '15 خيار',
                          color: Color(0xFF0EA5E9),
                          bg: Color(0xFFE0F2FE),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        _EntryOptionCard(
                          title: 'إدخالات إدارية',
                          subtitle: 'المهام والمواعيد والقرارات الإدارية',
                          count: '12 خيار',
                          color: Color(0xFF7C3AED),
                          bg: Color(0xFFF3E8FF),
                          icon: Icons.admin_panel_settings_outlined,
                        ),
                        _EntryOptionCard(
                          title: 'إدخالات المستندات',
                          subtitle:
                              'رفع المستندات والعقود والهوية والمرفقات الرسمية',
                          count: '17 خيار',
                          color: Color(0xFFD97706),
                          bg: Color(0xFFFEF3C7),
                          icon: Icons.folder_open,
                        ),
                        _EntryOptionCard(
                          title: 'إدخالات الأشخاص',
                          subtitle: 'إضافة تواصل وانضمام الأشخاص',
                          count: '2 خيار',
                          color: Color(0xFF059669),
                          bg: Color(0xFFDDF7EE),
                          icon: Icons.person_add_alt_1,
                        ),
                        _EntryOptionCard(
                          title: 'إدخال علاقات',
                          subtitle: 'ربط العناصر والأشخاص داخل النظام',
                          count: '11 خيار',
                          color: Color(0xFF0D9488),
                          bg: Color(0xFFCCFBF1),
                          icon: Icons.hub_outlined,
                        ),
                        _EntryOptionCard(
                          title: 'إدخال أصول',
                          subtitle:
                              'إدارة الأصول الأساسية المرتبطة بالالتزامات',
                          count: '4 خيار',
                          color: Color(0xFFDC2626),
                          bg: Color(0xFFFEE2E2),
                          icon: Icons.grid_view_rounded,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openDetails(_CommitmentItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonalCommitmentDetailsScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'الالتزامات الشخصية',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF0B3A78),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none, size: 24),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '2',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            const Text(
              'عرض شامل لجميع التزاماتك الشخصية',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFD1D9E6)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      textDirection: TextDirection.rtl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'البحث بكل ما يتعلق بالالتزامات الشخصية',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Color(0xFF475569),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD1D9E6)),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF334155),
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFEA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0D4C4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Text(
                        'مركز المتابعة',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3F2D1D),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.bar_chart_rounded,
                        color: Color(0xFF8C6A3C),
                        size: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'يوجد أمور تحتاج متابعة',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8C6A3C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 2.7,
                    children: const [
                      _MetricTile(
                        text: 'شي يحتاج متابعة (1)',
                        icon: Icons.visibility_outlined,
                      ),
                      _MetricTile(text: 'شي متأخر (2)', icon: Icons.schedule),
                      _MetricTile(
                        text: 'شي قريب الاستحقاق (3)',
                        icon: Icons.notifications_none,
                      ),
                      _MetricTile(
                        text: 'تنبيهات جديدة (2)',
                        icon: Icons.new_releases_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'عرض التفاصيل',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8C6A3C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final f = _statusFilters[index];
                  final selected = _selectedStatus == f;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedStatus = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF0B3A78)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Center(
                        child: Text(
                          f,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemCount: _statusFilters.length,
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'تصفية',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...filtered.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CommitmentCard(
                  item: item,
                  onTap: () => _openDetails(item),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewEntrySheet,
        backgroundColor: const Color(0xFFEA580C),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class PersonalCommitmentDetailsScreen extends StatefulWidget {
  final _CommitmentItem item;

  const PersonalCommitmentDetailsScreen({super.key, required this.item});

  @override
  State<PersonalCommitmentDetailsScreen> createState() =>
      _PersonalCommitmentDetailsScreenState();
}

class _PersonalCommitmentDetailsScreenState
    extends State<PersonalCommitmentDetailsScreen> {
  int _sectionIndex = 0;
  int _secondaryIndex = 0;

  final List<String> _sections = const [
    'الملخص',
    'المدفوعات',
    'المستندات',
    'المهام',
  ];

  final List<String> _secondarySections = const [
    'الأشخاص',
    'المالية',
    'الجدول الزمني',
    'التنبيهات',
    'السجل',
    'المزيد',
  ];

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final progressPercent = (item.progress * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'الالتزامات الخاصة (${item.title})',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF0B3A78),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              'آخر تحديث (${item.lastUpdate})',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD1D9E6)),
                    ),
                    child: const TextField(
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'ابحث داخل الالتزام الخاص',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Color(0xFF475569),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD1D9E6)),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF334155),
                    size: 19,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFEA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0D4C4)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'مركز المتابعة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F2D1D),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'يوجد أمور تحتاج متابعة',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8C6A3C)),
                  ),
                  SizedBox(height: 6),
                  _TrackerRow('شي دفعة متأخرة (1) | شي مستند ناقص (1)'),
                  SizedBox(height: 4),
                  _TrackerRow('شي دفعة قادمة (2) | شي تذكير غير مفعل (1)'),
                  SizedBox(height: 6),
                  Text(
                    'عرض التفاصيل',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8C6A3C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'شريط التقدم: تم التحصيل $progressPercent%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(_sections.length, (i) {
                      final selected = i == _sectionIndex;
                      return ChoiceChip(
                        label: Text(_sections[i]),
                        selected: selected,
                        onSelected: (_) => setState(() => _sectionIndex = i),
                        selectedColor: const Color(0xFF0B3A78),
                        backgroundColor: const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF334155),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  _DetailsSectionContent(index: _sectionIndex, item: item),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(_secondarySections.length, (i) {
                final selected = i == _secondaryIndex;
                return ChoiceChip(
                  label: Text(_secondarySections[i]),
                  selected: selected,
                  onSelected: (_) => setState(() => _secondaryIndex = i),
                  selectedColor: const Color(0xFF1E40AF),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            _SecondarySectionContent(index: _secondaryIndex),
          ],
        ),
      ),
    );
  }
}

class _DetailsSectionContent extends StatelessWidget {
  final int index;
  final _CommitmentItem item;

  const _DetailsSectionContent({required this.index, required this.item});

  @override
  Widget build(BuildContext context) {
    final List<List<String>> entries = [
      [
        'اسم الالتزام: ${item.title}',
        'الحالة: ${item.status}',
        'المبلغ: ${item.amount} درهم',
        'تاريخ الاستحقاق القادم: ${item.dueDate}',
        'عدد الدفعات المتبقية: ${item.remainingInstallments}',
        'نسبة الإنجاز: ${(item.progress * 100).toInt()}%',
        'آخر دفعة: 150 درهم',
        'تنبيه الاستحقاق: مفعّل',
      ],
      [
        'سجل جميع الدفعات',
        'دفعات جديدة / مستقبلية / متأخرة',
        'إجمالي المدفوع: 300 درهم',
        'إجمالي المتبقي: 450 درهم',
        'إيصالات الدفع',
        'طرق الدفع المستخدمة',
      ],
      [
        'العقود',
        'الفواتير',
        'الإيصالات',
        'الضمانات',
        'الصور',
        'ملفات PDF',
        'مستندات التجديد',
      ],
      ['مهام قادمة', 'مهام متأخرة', 'مهام مكتملة', 'تذكيرات', 'ملاحظات تنفيذ'],
    ];

    final rows = entries[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: rows
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                e,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _SecondarySectionContent extends StatelessWidget {
  final int index;

  const _SecondarySectionContent({required this.index});

  @override
  Widget build(BuildContext context) {
    final List<List<String>> entries = [
      [
        'مالك الالتزام',
        'المفوّضون',
        'جهات الاتصال',
        'الشركة/المورد',
        'أرقام التواصل',
        'سجل التواصل',
      ],
      [
        'الميزانية المخصصة',
        'المصروفات المرتبطة',
        'إجمالي التكلفة السنوية',
        'الرسوم والغرامات',
        'الضرائب',
        'التوقعات المالية',
      ],
      ['الجدول الزمني للدفعات', 'المواعيد القادمة', 'خط زمني للتحديثات'],
      [
        'تنبيهات مالية',
        'تنبيهات زمنية',
        'تنبيهات مستندات',
        'تنبيهات أشخاص',
        'تنبيهات ذكية',
      ],
      ['سجل النشاط', 'تغييرات الحالة', 'عمليات الدفع'],
      ['خيارات إضافية', 'تصدير البيانات', 'أرشفة الالتزام'],
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries[index]
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  e,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _TrackerRow extends StatelessWidget {
  final String text;

  const _TrackerRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: Color(0xFF4B3621),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CommitmentCard extends StatelessWidget {
  final _CommitmentItem item;
  final VoidCallback onTap;

  const _CommitmentCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progressPercent = (item.progress * 100).toInt();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.iconBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F2E68),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: item.statusColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.status,
                          style: TextStyle(
                            fontSize: 11,
                            color: item.statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_vert, size: 20, color: Color(0xFF64748B)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: _MetaColumn(
                    label: 'المبلغ',
                    value: '${item.amount} درهم',
                    color: const Color(0xFF0F9F6E),
                  ),
                ),
                Expanded(
                  child: _MetaColumn(
                    label: 'الاستحقاق',
                    value: item.dueDate,
                    color: const Color(0xFF1D4ED8),
                  ),
                ),
                Expanded(
                  child: _MetaColumn(
                    label: 'المتبقي',
                    value: '${item.remainingInstallments} دفعة',
                    color: const Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'نسبة الإنجاز $progressPercent%',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: item.progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(item.statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetaColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String text;
  final IconData icon;

  const _MetricTile({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6C9B8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        textDirection: TextDirection.rtl,
        children: [
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4B3621),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 12, color: const Color(0xFF6B4C2A)),
        ],
      ),
    );
  }
}

class _EntryOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String count;
  final Color color;
  final Color bg;
  final IconData icon;

  const _EntryOptionCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.bg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_back_ios_new_rounded, color: color, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitmentItem {
  final String title;
  final String status;
  final Color statusColor;
  final int amount;
  final String dueDate;
  final double progress;
  final int remainingInstallments;
  final String lastUpdate;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  const _CommitmentItem({
    required this.title,
    required this.status,
    required this.statusColor,
    required this.amount,
    required this.dueDate,
    required this.progress,
    required this.remainingInstallments,
    required this.lastUpdate,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
  });
}
