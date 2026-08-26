# 📚 دليل استخدام نظام الإضافات الذكي

## 🎯 نظرة عامة

نظام إضافات ذكي يعرض الإضافات المنطقية لكل نوع من أنواع الالتزامات، مع زر "مزيد من الإضافات" لباقي الخيارات.

---

## 📁 الملفات المُنشأة

### 1. `lib/config/commitment_additions_config.dart`
ملف التكوين الذي يحدد الإضافات المنطقية لكل نوع.

### 2. `lib/widgets/commitment_additions_menu.dart`
Widget يعرض قائمة الإضافات مع زر "مزيد من الإضافات".

---

## 🚀 كيفية الاستخدام

### الطريقة 1: استخدام مباشر في أي شاشة

```dart
import 'package:flutter/material.dart';
import '../widgets/commitment_additions_menu.dart';
import '../config/commitment_additions_config.dart';

class MyCommitmentDetailScreen extends StatelessWidget {
  final String commitmentId;
  final String entryType; // مثل: "مصروف شخصي"

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تفاصيل الالتزام')),
      body: Column(
        children: [
          // محتوى الشاشة...
          
          // زر إضافة
          ElevatedButton.icon(
            onPressed: () async {
              final selected = await showCommitmentAdditionsMenu(
                context: context,
                entryType: entryType,
                commitmentId: commitmentId,
              );
              
              if (selected != null) {
                // تعامل مع الإضافة المختارة
                _handleAddition(selected);
              }
            },
            icon: Icon(Icons.add),
            label: Text('إضافة جديدة'),
          ),
        ],
      ),
    );
  }

  void _handleAddition(AdditionType addition) {
    print('تم اختيار: ${addition.displayName}');
    
    // حسب نوع الإضافة
    switch (addition.category) {
      case AdditionCategory.payment:
        // افتح شاشة إضافة دفعة
        break;
      case AdditionCategory.attachment:
        // افتح شاشة اختيار ملف
        break;
      case AdditionCategory.appointment:
        // افتح شاشة إضافة موعد
        break;
      case AdditionCategory.note:
        // افتح شاشة إضافة ملاحظة
        break;
      case AdditionCategory.person:
        // افتح شاشة إضافة شخص
        break;
      case AdditionCategory.location:
        // افتح شاشة إضافة موقع
        break;
    }
  }
}
```

---

### الطريقة 2: استخدام كـ FloatingActionButton

```dart
FloatingActionButton(
  onPressed: () async {
    final selected = await showCommitmentAdditionsMenu(
      context: context,
      entryType: widget.entryType,
      commitmentId: widget.commitmentId,
    );
    
    if (selected != null) {
      _navigateToAdditionScreen(selected);
    }
  },
  child: Icon(Icons.add),
)
```

---

### الطريقة 3: استخدام Extension

```dart
// استخدام extension للحصول على الإضافات مباشرة
String entryType = 'مصروف شخصي';

// الإضافات المنطقية
List<AdditionType> logical = entryType.logicalAdditions;

// الإضافات الإضافية
List<AdditionType> additional = entryType.additionalAdditions;

// كل الإضافات
List<AdditionType> all = entryType.allAdditions;

// التحقق إذا كانت إضافة منطقية
bool isLogical = entryType.isLogicalAddition('payment');
```

---

## 🎨 التخصيص

### تغيير الإضافات المنطقية لنوع معين

عدّل ملف `commitment_additions_config.dart`:

```dart
case 'مصروف شخصي':
  return [
    AllAdditions.payment,
    AllAdditions.receipt,
    AllAdditions.image,
    AllAdditions.note,
    // أضف المزيد هنا...
  ];
```

### تغيير الألوان والأيقونات

في `commitment_additions_menu.dart`:

```dart
// لون الإضافات المنطقية
color: isPrimary ? Colors.blue.shade50 : Colors.grey.shade50,

// لون الحدود
borderColor: isPrimary ? Colors.blue.shade200 : Colors.grey.shade300,
```

---

## 📊 الإضافات المنطقية لكل نوع

### 1. مصروف شخصي
✅ دفعة، إيصال، صورة، ملاحظة

### 2. دخل
✅ دفعة، إيصال، فاتورة، مستند، ملاحظة

### 3. تحويل مالي
✅ دفعة، إيصال، شخص، بيانات إدارية، ملاحظة

### 4. دين/قرض/سلفة
✅ دفعة، شخص، مستند، موعد دفع، تذكير، ملاحظة

### 5. قسط
✅ دفعة، فاتورة، عقد، موعد دفع، تذكير، بيانات إدارية

### 6. غرامة
✅ دفعة، فاتورة، مستند، صورة، موعد دفع، بيانات إدارية

### 7. عهدة مالية
✅ دفعة، إيصال، شخص، تسوية، ملاحظة

---

## 🔍 أمثلة متقدمة

### مثال 1: تصفية الإضافات حسب الصلاحيات

```dart
List<AdditionType> getAvailableAdditions(String entryType, User user) {
  final logical = entryType.logicalAdditions;
  
  // تصفية حسب صلاحيات المستخدم
  return logical.where((addition) {
    if (addition.id == 'administrative_data') {
      return user.isAdmin; // فقط المدير يمكنه إضافة بيانات إدارية
    }
    return true;
  }).toList();
}
```

### مثال 2: عرض عدد الإضافات الحالية

```dart
Widget _buildAdditionsSummary() {
  final logical = widget.entryType.logicalAdditions;
  
  return Row(
    children: [
      Text('الإضافات المقترحة: ${logical.length}'),
      SizedBox(width: 8),
      Text('إضافات أخرى متاحة: ${widget.entryType.additionalAdditions.length}'),
    ],
  );
}
```

### مثال 3: البحث في الإضافات

```dart
List<AdditionType> searchAdditions(String entryType, String query) {
  final all = entryType.allAdditions;
  
  if (query.isEmpty) return all;
  
  return all.where((addition) {
    return addition.displayName.contains(query) ||
           addition.id.contains(query);
  }).toList();
}
```

---

## ✅ مزايا النظام

1. ✅ **ذكي**: يعرض الإضافات المنطقية فقط حسب نوع الالتزام
2. ✅ **منظم**: الإضافات مرتبة حسب الأهمية
3. ✅ **مرن**: زر "مزيد من الإضافات" للخيارات الإضافية
4. ✅ **قابل للتخصيص**: سهل التعديل والتوسع
5. ✅ **واضح**: تصميم بصري يميز الإضافات المنطقية

---

## 🔧 الخطوات التالية

1. ✅ استبدل الكود القديم في الشاشة الحالية
2. ✅ اختبر مع كل نوع من الأنواع السبعة
3. ✅ عدّل الألوان حسب تصميم التطبيق
4. ✅ أضف أي إضافات جديدة في المستقبل

---

## 📞 دعم

إذا واجهت أي مشكلة أو تريد إضافة ميزات جديدة، يمكنك:
- تعديل `commitment_additions_config.dart` للتكوين
- تعديل `commitment_additions_menu.dart` للـ UI
