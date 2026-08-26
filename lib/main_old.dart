import 'package:flutter/material.dart';
import 'screens/people_management_screen.dart';
import 'screens/personal_commitments_screen.dart';
import 'screens/projects_activities_screen.dart';
import 'screens/shared_commitments_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fundly',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF1E3A8A)),
        useMaterial3: true,
      ),
      home: const HomePage(),
      routes: {'/home': (context) => const HomePage()},
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  int _selectedIndex = 4;
  bool _showPriorityGrid = true;
  late AnimationController _titleAnimationController;
  late Animation<double> _titleAnimation;

  @override
  void initState() {
    super.initState();
    _titleAnimationController = AnimationController(
      duration: Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _titleAnimation = Tween<double>(begin: 0, end: 20).animate(
      CurvedAnimation(
        parent: _titleAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _titleAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 178,
            floating: false,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -50,
                      top: -50,
                      child: CircleAvatar(
                        radius: 100,
                        backgroundColor: Color(0xFF3B82F6).withOpacity(0.08),
                      ),
                    ),
                    Positioned(
                      left: -30,
                      bottom: -30,
                      child: CircleAvatar(
                        radius: 80,
                        backgroundColor: Color(0xFF1E40AF).withOpacity(0.08),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            textDirection: TextDirection.rtl,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Color(0xFF3B82F6).withOpacity(0.28),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xFF3B82F6).withOpacity(0.2),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: Colors.white.withOpacity(
                                        0.2,
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        size: 26,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(
                                                0xFF10B981,
                                              ).withOpacity(0.5),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        padding: EdgeInsets.all(3),
                                        child: Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'مرحباً عبدالله',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E40AF),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    textDirection: TextDirection.rtl,
                                    children: [
                                      Text(
                                        '12 يوليو 2026',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(
                                            0xFF1E3A8A,
                                          ).withOpacity(0.85),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Icon(
                                        Icons.calendar_month,
                                        size: 12,
                                        color: Color(
                                          0xFF1E3A8A,
                                        ).withOpacity(0.85),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 6),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(
                                        0xFF3B82F6,
                                      ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Color(
                                          0xFF3B82F6,
                                        ).withOpacity(0.25),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '⭐ موثوقة جداً',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF1E3A8A),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF3B82F6).withOpacity(0.15),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: TextField(
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        hintText: 'ابحث عن التزام...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 15,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Color(0xFF3B82F6),
                          size: 24,
                        ),
                        suffixIcon: Icon(
                          Icons.tune,
                          color: Color(0xFF3B82F6),
                          size: 24,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: AnimatedBuilder(
                    animation: _titleAnimation,
                    builder: (context, child) {
                      return Text(
                        'دير امورك المالية والاملاك بسهولة احترافية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                          letterSpacing: 0.1,
                        ),
                        textAlign: TextAlign.right,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: _buildCommitmentOverview(),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFCD34D).withOpacity(0.3),
                              Color(0xFFF59E0B).withOpacity(0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.stars,
                          color: Color(0xFFFCD34D),
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'الأولويات الحالية',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Color(0xFFCBD5E1),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          onPressed: () => setState(
                            () => _showPriorityGrid = !_showPriorityGrid,
                          ),
                          icon: Icon(
                            _showPriorityGrid
                                ? Icons.grid_view_rounded
                                : Icons.view_agenda_rounded,
                            color: Color(0xFF1E40AF),
                          ),
                          iconSize: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildTopCategories(),
                SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildCommitmentOverview() {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF3B82F6).withOpacity(0.15),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'مركز المتابعة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E40AF),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Color(0xFF10B981).withOpacity(0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Text(
                            'مؤشر الاستقرار المالي',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF047857),
                            ),
                          ),
                          Spacer(),
                          Icon(
                            Icons.show_chart,
                            size: 14,
                            color: Color(0xFF059669),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        '78%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF047857),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'مستقر مع تحسن',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Color(0xFFF59E0B).withOpacity(0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Text(
                            'مفوّض من آخرين',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                          Spacer(),
                          Icon(
                            Icons.groups,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        '5 حالات',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '2 بانتظار الإجراء',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopCategories() {
    final categories = [
      (
        'الالتزامات الشخصية',
        Icons.person,
        Color(0xFF3B82F6),
        ['مؤشر الالتزام: مستقر', 'حالة السداد: منتظمة'],
      ),
      (
        'الالتزامات المشتركة',
        Icons.group,
        Color(0xFF10B981),
        ['عدد المجموعات: 3', 'مستحق عليك: 3,500 درهم'],
      ),
      (
        'إدارة الأشخاص',
        Icons.admin_panel_settings,
        Color(0xFF8B5CF6),
        ['مستثمرات نشطة: 5', 'تحديثات قريبة: 3'],
      ),
      (
        'المشاريع',
        Icons.business,
        Color(0xFFF59E0B),
        ['عقارات: قارب على الانتهاء', 'عقود: قيد التنفيذ'],
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: _showPriorityGrid
          ? GridView.builder(
              itemCount: categories.length,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) {
                final c = categories[index];
                return _buildCategoryTileCompact(c.$1, c.$2, c.$3, c.$4);
              },
            )
          : Column(
              children: [
                _buildCategoryTile(
                  categories[0].$1,
                  categories[0].$2,
                  categories[0].$3,
                  categories[0].$4,
                ),
                SizedBox(height: 16),
                _buildCategoryTile(
                  categories[1].$1,
                  categories[1].$2,
                  categories[1].$3,
                  categories[1].$4,
                ),
                SizedBox(height: 16),
                _buildCategoryTile(
                  categories[2].$1,
                  categories[2].$2,
                  categories[2].$3,
                  categories[2].$4,
                ),
                SizedBox(height: 16),
                _buildCategoryTile(
                  categories[3].$1,
                  categories[3].$2,
                  categories[3].$3,
                  categories[3].$4,
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryTileCompact(
    String title,
    IconData icon,
    Color color,
    List<String> items,
  ) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.14), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            items.first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              height: 1.35,
            ),
          ),
          SizedBox(height: 8),
          Text(
            items.length > 1 ? items[1] : '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              height: 1.35,
            ),
          ),
          Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _openPriorityScreen(title),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'عرض المزيد',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPriorityScreen(String title) {
    if (title == 'الالتزامات الشخصية') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PersonalCommitmentsScreen()),
      );
      return;
    }

    if (title == 'الالتزامات المشتركة') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SharedCommitmentsScreen()),
      );
      return;
    }

    if (title == 'إدارة الأشخاص') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PeopleManagementScreen()));
      return;
    }

    if (title == 'المشاريع') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProjectsActivitiesScreen()),
      );
      return;
    }

    return;
  }

  Widget _buildCategoryTile(
    String title,
    IconData icon,
    Color color,
    List<String> items,
  ) {
    final bool isPersonalCommitments = title == 'الالتزامات الشخصية';

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.2), width: 1),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...items.map(
            (item) => Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.6)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: color.withOpacity(0.4), blurRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isPersonalCommitments) ...[
            SizedBox(height: 6),
            _buildPersonalCommitmentCards(color),
          ],
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _openPriorityScreen(title),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.2), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(Icons.arrow_forward, color: color, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'عرض المزيد',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalCommitmentCards(Color color) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFEE2E2), Color(0xFFFFF1F2)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color(0xFFFB7185).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.south_east, color: Color(0xFFFB7185), size: 16),
                    Text(
                      'عليك',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9F1239),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildCurrencyAmount('2,000', Color(0xFFBE123C)),
              ],
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color(0xFF10B981).withOpacity(0.35),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.north_west, color: Color(0xFF10B981), size: 16),
                    Text(
                      'لك',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                _buildCurrencyAmount('2,500', Color(0xFF047857)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyAmount(String amount, Color amountColor) {
    return RichText(
      textDirection: TextDirection.rtl,
      text: TextSpan(
        children: [
          TextSpan(
            text: amount,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
          WidgetSpan(child: SizedBox(width: 4)),
          TextSpan(
            text: 'درهم',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: amountColor.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF3B82F6),
        unselectedItemColor: Colors.grey[400],
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'المزيد',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'التقارير',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'الأشخاص'),
          BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'المهام'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
        ],
      ),
    );
  }
}
