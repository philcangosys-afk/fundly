# دليل التنفيذ الكامل - نظام الإضافات الجديد
## Implementation Guide for Commitment Additions System

---

## 📋 الملفات التي تم إنشاؤها

### 1. Migration File
**الملف:** `supabase/migrations/202608200001_create_commitment_additions.sql`
- ✅ جداول منظمة لجميع أنواع الإضافات (6 جداول)
- ✅ Views محسوبة للإحصائيات التلقائية
- ✅ Triggers لتحديث حالة الالتزام تلقائيًا
- ✅ Row Level Security policies للأمان
- ✅ Storage bucket للمرفقات

### 2. Data Models
**الملف:** `lib/data/commitment_additions_models.dart`
- ✅ 8 Dart classes متكاملة:
  1. `CommitmentPayment` - الدفعات
  2. `CommitmentAttachment` - المرفقات
  3. `CommitmentAppointment` - المواعيد
  4. `CommitmentNote` - الملاحظات
  5. `CommitmentPerson` - الأشخاص
  6. `CommitmentLocation` - المواقع
  7. `CommitmentPaymentSummary` - ملخص الدفعات
  8. `CommitmentFullSummary` - الملخص الكامل
- ✅ Complete `fromJson()` و `toJson()` methods
- ✅ `toInsertJson()` للإضافة
- ✅ `copyWith()` للتعديل

### 3. Repository
**الملف:** `lib/data/commitment_additions_repository.dart`
- ✅ CRUD operations كاملة لكل نوع إضافة
- ✅ وظائف متقدمة (upload files, get summaries)
- ✅ Error handling مدمج

### 4. Documentation
**الملف:** `COMMITMENT_ADDITIONS_GUIDE.md`
- ✅ شرح تفصيلي لكل نوع إضافة
- ✅ توضيح التأثير المنطقي لكل إضافة
- ✅ أمثلة واقعية للاستخدام

---

## 🚀 خطوات التنفيذ

### المرحلة 1: تطبيق Migration على قاعدة البيانات

#### الخطوة 1.1: التحقق من اتصال Supabase
```bash
# في terminal المشروع
cd c:\Users\alzai\fundly

# تسجيل الدخول إلى Supabase
supabase login

# ربط المشروع (إذا لم يكن مربوط)
supabase link --project-ref YOUR_PROJECT_REF
```

#### الخطوة 1.2: تطبيق Migration
```bash
# تطبيق جميع migrations الجديدة
supabase db push

# أو تطبيق migration محددة
supabase migration up
```

#### الخطوة 1.3: التحقق من نجاح Migration
```sql
-- يمكن تشغيل هذا في Supabase Dashboard > SQL Editor
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public'
  AND table_name LIKE 'commitment_%';

-- يجب أن يعرض:
-- commitment_payments
-- commitment_attachments
-- commitment_appointments
-- commitment_notes
-- commitment_people
-- commitment_locations
```

---

### المرحلة 2: دمج Repository في التطبيق

#### الخطوة 2.1: تحديث main.dart
```dart
// في lib/main.dart
import 'data/commitment_additions_repository.dart';

// بعد تهيئة Supabase
final commitmentAdditionsRepo = CommitmentAdditionsRepository(
  Supabase.instance.client,
);

// يمكن تمريره عبر Provider أو GetIt أو مباشرة إلى screens
```

#### الخطوة 2.2: استخدام Repository في Details Screen
```dart
// في lib/screens/personal_commitments_screen.dart
// في _PersonalCommitmentDetailsScreen

class _PersonalCommitmentDetailsScreenState extends State<_PersonalCommitmentDetailsScreen> {
  late CommitmentAdditionsRepository _additionsRepo;
  
  @override
  void initState() {
    super.initState();
    _additionsRepo = CommitmentAdditionsRepository(Supabase.instance.client);
    _loadAdditions();
  }
  
  Future<void> _loadAdditions() async {
    try {
      final payments = await _additionsRepo.getPayments(widget.item.id);
      final attachments = await _additionsRepo.getAttachments(widget.item.id);
      final appointments = await _additionsRepo.getAppointments(widget.item.id);
      // ... load other additions
      
      setState(() {
        // update state with loaded data
      });
    } catch (e) {
      // handle error
    }
  }
}
```

---

### المرحلة 3: تحديث واجهة الإضافات

#### الخطوة 3.1: إضافة دفعة (Payment)

**النموذج الحالي (قديم):**
```dart
// في _openQuickDetailEntrySheet
// يحفظ النص في details JSON
```

**النموذج الجديد (مطلوب):**
```dart
Future<void> _openAddPaymentSheet() async {
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  String? selectedMethod = 'نقدي';

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة دفعة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF172033),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Amount field
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'المبلغ',
                      hintText: '0.00',
                      prefixText: 'ر.س ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Payment date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        locale: const Locale('ar'),
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'تاريخ الدفعة',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Payment method
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: InputDecoration(
                      labelText: 'طريقة الدفع',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: ['نقدي', 'بنكي', 'بطاقة', 'تحويل', 'شيك', 'أخرى']
                        .map((method) => DropdownMenuItem(
                              value: method,
                              child: Text(method),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setModalState(() {
                        selectedMethod = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  // Reference number (optional)
                  TextField(
                    controller: referenceController,
                    decoration: InputDecoration(
                      labelText: 'رقم المرجع (اختياري)',
                      hintText: 'رقم الإيصال أو المعاملة',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('حفظ الدفعة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  if (saved != true || !mounted) return;
  
  final amount = double.tryParse(amountController.text.trim());
  if (amount == null || amount <= 0) {
    // Show error
    return;
  }

  // Save to database
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final payment = CommitmentPayment(
      id: '', // Will be generated by database
      commitmentId: widget.item.id,
      userId: _additionsRepo._userId,
      amount: amount,
      paymentDate: selectedDate,
      paymentMethod: selectedMethod,
      referenceNumber: referenceController.text.trim().isEmpty 
          ? null 
          : referenceController.text.trim(),
      notes: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _additionsRepo.addPayment(payment);
    
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Close loading
    
    // Reload data to show updated payment status
    await _loadAdditions();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إضافة الدفعة بنجاح')),
    );
  } catch (e) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Close loading
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ: ${e.toString()}')),
    );
  }
}
```

#### الخطوة 3.2: إضافة مرفق (Attachment)

```dart
Future<void> _openAddAttachmentSheet(String attachmentType) async {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  
  // Pick file
  final ImagePicker picker = ImagePicker();
  final XFile? pickedFile = await picker.pickImage(
    source: ImageSource.gallery, // or camera
  );
  
  if (pickedFile == null) return;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'إضافة $attachmentType',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172033),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Show selected file
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedFile.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Title
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'عنوان المرفق',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Description (optional)
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'وصف (اختياري)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('رفع المرفق'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (saved != true || !mounted) return;
  
  final title = titleController.text.trim();
  if (title.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الرجاء إدخال عنوان المرفق')),
    );
    return;
  }

  // Upload file and save to database
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    // Read file bytes
    final fileBytes = await pickedFile.readAsBytes();
    final fileSize = (fileBytes.length / 1024).round(); // KB
    
    // Upload to storage
    final fileUrl = await _additionsRepo.uploadAttachmentFile(
      widget.item.id,
      pickedFile.name,
      fileBytes,
    );
    
    // Save metadata to database
    final attachment = CommitmentAttachment(
      id: '',
      commitmentId: widget.item.id,
      userId: _additionsRepo._userId,
      attachmentType: attachmentType,
      fileName: pickedFile.name,
      fileUrl: fileUrl,
      fileSizeKb: fileSize,
      mimeType: pickedFile.mimeType,
      title: title,
      description: descriptionController.text.trim().isEmpty 
          ? null 
          : descriptionController.text.trim(),
      uploadedAt: DateTime.now(),
    );

    await _additionsRepo.addAttachment(attachment);
    
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Close loading
    
    await _loadAdditions();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم رفع المرفق بنجاح')),
    );
  } catch (e) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Close loading
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ: ${e.toString()}')),
    );
  }
}
```

#### الخطوة 3.3: عرض الإضافات في صفحة التفاصيل

**إضافة state variables:**
```dart
class _PersonalCommitmentDetailsScreenState extends State<_PersonalCommitmentDetailsScreen> {
  late CommitmentAdditionsRepository _additionsRepo;
  
  List<CommitmentPayment> _payments = [];
  List<CommitmentAttachment> _attachments = [];
  List<CommitmentAppointment> _appointments = [];
  List<CommitmentNote> _notes = [];
  List<CommitmentPerson> _people = [];
  CommitmentPaymentSummary? _paymentSummary;
  
  bool _isLoadingAdditions = false;
  
  // ... rest of code
}
```

**عرض ملخص الدفعات:**
```dart
Widget _buildPaymentSummaryCard() {
  if (_paymentSummary == null) return const SizedBox.shrink();
  
  return Card(
    margin: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص الدفعات',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المبلغ الأصلي:'),
              Text(
                '${_paymentSummary!.originalAmount.toStringAsFixed(2)} ر.س',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المبلغ المدفوع:'),
              Text(
                '${_paymentSummary!.paidAmount.toStringAsFixed(2)} ر.س',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المبلغ المتبقي:'),
              Text(
                '${_paymentSummary!.remainingAmount.toStringAsFixed(2)} ر.س',
                style: TextStyle(
                  color: _paymentSummary!.isFullyPaid 
                      ? Colors.grey 
                      : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Progress bar
          LinearProgressIndicator(
            value: _paymentSummary!.progressPercentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              _paymentSummary!.isFullyPaid 
                  ? Colors.green 
                  : Colors.blue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_paymentSummary!.progressPercentage.toStringAsFixed(1)}% مكتمل',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
```

**عرض قائمة الدفعات:**
```dart
Widget _buildPaymentsList() {
  if (_payments.isEmpty) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('لا توجد دفعات مسجلة'),
      ),
    );
  }
  
  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _payments.length,
    itemBuilder: (context, index) {
      final payment = _payments[index];
      return ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.payments, color: Colors.white),
        ),
        title: Text('${payment.amount.toStringAsFixed(2)} ر.س'),
        subtitle: Text(
          '${payment.paymentDate.day}/${payment.paymentDate.month}/${payment.paymentDate.year}'
          '${payment.paymentMethod != null ? ' - ${payment.paymentMethod}' : ''}',
        ),
        trailing: payment.referenceNumber != null
            ? Text(
                '#${payment.referenceNumber}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            : null,
      );
    },
  );
}
```

---

### المرحلة 4: الهجرة من النظام القديم (Migration Script)

#### نقل البيانات من details JSONB إلى الجداول الجديدة

```sql
-- في Supabase SQL Editor أو كـ migration جديدة

-- 1. نقل الأشخاص من details إلى commitment_people
INSERT INTO public.commitment_people (commitment_id, user_id, person_name, role_or_relationship)
SELECT 
  id as commitment_id,
  user_id,
  substring(value from 'إضافة شخص: (.+)') as person_name,
  null as role_or_relationship
FROM public.personal_entries,
     jsonb_each_text(details)
WHERE key LIKE 'إضافة شخص%'
  AND value IS NOT NULL;

-- 2. نقل الملاحظات من details إلى commitment_notes
INSERT INTO public.commitment_notes (
  commitment_id, 
  user_id, 
  note_type, 
  title, 
  content,
  impacts_amount,
  impacts_date
)
SELECT 
  id as commitment_id,
  user_id,
  'ملاحظة' as note_type,
  key as title,
  value as content,
  false as impacts_amount,
  false as impacts_date
FROM public.personal_entries,
     jsonb_each_text(details)
WHERE key NOT LIKE 'إضافة شخص%'
  AND key NOT LIKE 'إضافة دفعة%'
  AND value IS NOT NULL;

-- 3. بعد نقل البيانات، يمكن تنظيف details JSONB (اختياري)
-- UPDATE public.personal_entries SET details = '{}'::jsonb;
```

---

## ✅ التحقق من نجاح التنفيذ

### 1. اختبار الدفعات
```dart
// في test file أو debug console
final repo = CommitmentAdditionsRepository(Supabase.instance.client);

// Add test payment
final payment = await repo.addPayment(CommitmentPayment(
  id: '',
  commitmentId: 'YOUR_COMMITMENT_ID',
  userId: 'USER_ID',
  amount: 1000.0,
  paymentDate: DateTime.now(),
  paymentMethod: 'نقدي',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
));

print('Payment added: ${payment.id}');

// Get summary
final summary = await repo.getPaymentSummary('YOUR_COMMITMENT_ID');
print('Remaining: ${summary?.remainingAmount}');
```

### 2. اختبار Trigger
```sql
-- في Supabase SQL Editor
-- أضف دفعة جديدة
INSERT INTO commitment_payments (commitment_id, user_id, amount, payment_date)
VALUES ('YOUR_COMMITMENT_ID', 'USER_ID', 1000.00, current_date);

-- تحقق من أن status تحدث تلقائيًا
SELECT id, title, amount, status 
FROM personal_entries 
WHERE id = 'YOUR_COMMITMENT_ID';
```

---

## 📊 التقارير والإحصائيات الجديدة الممكنة

بفضل النظام الجديد، يمكن الآن:

### 1. تقرير إجمالي الدفعات
```dart
final summary = await repo.getPaymentSummary(commitmentId);
print('إجمالي المدفوع: ${summary.paidAmount}');
print('المتبقي: ${summary.remainingAmount}');
print('نسبة الإنجاز: ${summary.progressPercentage}%');
```

### 2. تقرير المواعيد القادمة
```dart
final upcomingAppointments = await repo.getUpcomingAppointments(commitmentId);
print('عدد المواعيد القادمة: ${upcomingAppointments.length}');
```

### 3. تقرير شامل
```dart
final fullSummary = await repo.getFullSummary(commitmentId);
print('عدد المرفقات: ${fullSummary.attachmentsCount}');
print('عدد المواعيد: ${fullSummary.upcomingAppointmentsCount}');
print('عدد الأشخاص: ${fullSummary.relatedPeopleCount}');
```

---

## 🔍 استعلامات SQL مفيدة للتحليلات

```sql
-- 1. الالتزامات التي اكتملت دفعاتها
SELECT * FROM commitment_payment_summary
WHERE payment_status = 'مكتمل';

-- 2. إجمالي المدفوعات لكل طريقة دفع
SELECT payment_method, COUNT(*), SUM(amount)
FROM commitment_payments
GROUP BY payment_method;

-- 3. المواعيد القادمة خلال أسبوع
SELECT ca.*, pe.title as commitment_title
FROM commitment_appointments ca
JOIN personal_entries pe ON pe.id = ca.commitment_id
WHERE ca.status = 'قادم'
  AND ca.appointment_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
ORDER BY ca.appointment_date;

-- 4. الالتزامات حسب عدد المرفقات
SELECT 
  pe.title,
  COUNT(ca.id) as attachments_count
FROM personal_entries pe
LEFT JOIN commitment_attachments ca ON ca.commitment_id = pe.id
GROUP BY pe.id, pe.title
ORDER BY attachments_count DESC;
```

---

## 🎯 الخطوة التالية المقترحة

1. **تطبيق Migration** على قاعدة البيانات أولاً
2. **اختبار الجداول** يدويًا عبر Supabase Dashboard
3. **تحديث Details Screen** لاستخدام Repository الجديد
4. **اختبار** إضافة دفعة واحدة والتحقق من تحديث الحالة
5. **توسيع** تدريجيًا لباقي أنواع الإضافات

---

**تاريخ الإنشاء:** 2026-08-20  
**الحالة:** جاهز للتطبيق ✅  
**آخر تحديث:** 2026-08-20
