import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/commitment_additions_menu.dart';
import '../config/commitment_additions_config.dart';
import '../data/commitment_additions_models.dart';
import '../data/commitment_additions_repository.dart';

/// Example screen showing how to use the additions menu
/// Replace this with your actual commitment details screen
class CommitmentDetailsExampleScreen extends StatefulWidget {
  final String commitmentId;
  final String entryType;
  final String title;
  final double amount;

  const CommitmentDetailsExampleScreen({
    super.key,
    required this.commitmentId,
    required this.entryType,
    required this.title,
    required this.amount,
  });

  @override
  State<CommitmentDetailsExampleScreen> createState() =>
      _CommitmentDetailsExampleScreenState();
}

class _CommitmentDetailsExampleScreenState
    extends State<CommitmentDetailsExampleScreen> {
  late final CommitmentAdditionsRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = CommitmentAdditionsRepository(Supabase.instance.client);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل الالتزام'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Commitment Info Card
            _buildInfoCard(),

            const SizedBox(height: 24),

            // Additions Summary
            _buildAdditionsSummaryCard(),

            const SizedBox(height: 24),

            // Add Button
            _buildAddButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'النوع: ${widget.entryType}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              'المبلغ: ${widget.amount.toStringAsFixed(2)} ر.س',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionsSummaryCard() {
    final logical = widget.entryType.logicalAdditions;
    final additional = widget.entryType.additionalAdditions;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الإضافات المتاحة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.check_circle,
                    label: 'الإضافات المقترحة',
                    count: logical.length,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryItem(
                    icon: Icons.more_horiz,
                    label: 'إضافات أخرى',
                    count: additional.length,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: _showAdditionsMenu,
      icon: const Icon(Icons.add_circle_outline, size: 28),
      label: const Text('إضافة جديدة', style: TextStyle(fontSize: 18)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showAdditionsMenu() async {
    final selected = await showCommitmentAdditionsMenu(
      context: context,
      entryType: widget.entryType,
      commitmentId: widget.commitmentId,
    );

    if (selected != null) {
      _handleAdditionSelection(selected);
    }
  }

  void _handleAdditionSelection(AdditionType addition) {
    // Handle the selected addition based on its category
    switch (addition.category) {
      case AdditionCategory.payment:
        _showAddPaymentDialog(addition);
        break;

      case AdditionCategory.attachment:
        _handleAttachment(addition);
        break;

      case AdditionCategory.appointment:
        _showAddAppointmentDialog(addition);
        break;

      case AdditionCategory.note:
        _showAddNoteDialog(addition);
        break;

      case AdditionCategory.person:
        _showAddPersonDialog();
        break;

      case AdditionCategory.location:
        _showAddLocationDialog();
        break;
    }
  }

  // === PAYMENT ===
  Future<void> _showAddPaymentDialog(AdditionType addition) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedMethod;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${addition.icon} ${addition.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    suffixText: 'ر.س',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedMethod,
                  decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                  items: ['نقدي', 'بنكي', 'بطاقة', 'تحويل', 'شيك', 'أخرى']
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => selectedMethod = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true && amountController.text.isNotEmpty) {
      try {
        final now = DateTime.now();
        await _repository.addPayment(
          CommitmentPayment(
            id: '',
            commitmentId: widget.commitmentId,
            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
            amount: double.parse(amountController.text),
            paymentDate: now,
            paymentMethod: selectedMethod,
            notes: notesController.text.isEmpty ? null : notesController.text,
            createdAt: now,
            updatedAt: now,
          ),
        );
        _showSuccessSnackBar('تمت إضافة الدفعة بنجاح');
      } catch (e) {
        _showErrorSnackBar('فشل في إضافة الدفعة: $e');
      }
    }
  }

  // === ATTACHMENT ===
  Future<void> _handleAttachment(AdditionType addition) async {
    // Map addition ID to attachment type
    String attachmentType;
    switch (addition.id) {
      case 'invoice':
        attachmentType = 'فاتورة';
        break;
      case 'document':
        attachmentType = 'مستند';
        break;
      case 'receipt':
        attachmentType = 'إيصال';
        break;
      case 'contract':
        attachmentType = 'عقد';
        break;
      case 'image':
        attachmentType = 'صورة';
        break;
      default:
        attachmentType = 'مرفق آخر';
    }

    // TODO: Implement file picker
    // final file = await FilePicker.platform.pickFiles();
    // if (file != null) {
    //   await _repository.uploadAttachment(...);
    // }

    _showInfoSnackBar('سيتم إضافة دعم اختيار الملفات قريباً');
  }

  // === APPOINTMENT ===
  Future<void> _showAddAppointmentDialog(AdditionType addition) async {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    // وقت الموعد غير مستخدم حاليًا في واجهة الإدخال.

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${addition.icon} ${addition.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('التاريخ'),
                subtitle: Text('${selectedDate.toLocal()}'.split(' ')[0]),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => selectedDate = date);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true && titleController.text.isNotEmpty) {
      // Map addition ID to appointment type
      String appointmentType;
      switch (addition.id) {
        case 'payment_appointment':
          appointmentType = 'موعد دفع';
          break;
        case 'renewal_appointment':
          appointmentType = 'موعد تجديد';
          break;
        case 'followup_appointment':
          appointmentType = 'موعد متابعة';
          break;
        case 'reminder':
          appointmentType = 'تذكير';
          break;
        default:
          appointmentType = 'موعد';
      }

      try {
        final now = DateTime.now();
        await _repository.addAppointment(
          CommitmentAppointment(
            id: '',
            commitmentId: widget.commitmentId,
            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
            appointmentType: appointmentType,
            title: titleController.text,
            appointmentDate: selectedDate,
            status: 'قادم',
            reminderEnabled: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
        _showSuccessSnackBar('تمت إضافة الموعد بنجاح');
      } catch (e) {
        _showErrorSnackBar('فشل في إضافة الموعد: $e');
      }
    }
  }

  // === NOTE ===
  Future<void> _showAddNoteDialog(AdditionType addition) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${addition.icon} ${addition.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              decoration: const InputDecoration(labelText: 'المحتوى'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true &&
        titleController.text.isNotEmpty &&
        contentController.text.isNotEmpty) {
      // Map addition ID to note type
      String noteType;
      switch (addition.id) {
        case 'settlement':
          noteType = 'تسوية';
          break;
        case 'renewal':
          noteType = 'تجديد';
          break;
        case 'administrative_data':
          noteType = 'بيانات إدارية';
          break;
        default:
          noteType = 'ملاحظة';
      }

      try {
        final now = DateTime.now();
        await _repository.addNote(
          CommitmentNote(
            id: '',
            commitmentId: widget.commitmentId,
            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
            noteType: noteType,
            title: titleController.text,
            content: contentController.text,
            impactsAmount: false,
            impactsDate: false,
            createdAt: now,
          ),
        );
        _showSuccessSnackBar('تمت إضافة ${addition.displayName} بنجاح');
      } catch (e) {
        _showErrorSnackBar('فشل في الإضافة: $e');
      }
    }
  }

  // === PERSON ===
  Future<void> _showAddPersonDialog() async {
    final nameController = TextEditingController();
    final roleController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('👤 إضافة شخص'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: roleController,
              decoration: const InputDecoration(
                labelText: 'الدور/العلاقة (اختياري)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (اختياري)',
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await _repository.addRelatedPerson(
          CommitmentPerson(
            id: '',
            commitmentId: widget.commitmentId,
            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
            personName: nameController.text,
            roleOrRelationship: roleController.text.isEmpty
                ? null
                : roleController.text,
            phoneNumber: phoneController.text.isEmpty
                ? null
                : phoneController.text,
            createdAt: DateTime.now(),
          ),
        );
        _showSuccessSnackBar('تمت إضافة الشخص بنجاح');
      } catch (e) {
        _showErrorSnackBar('فشل في إضافة الشخص: $e');
      }
    }
  }

  // === LOCATION ===
  Future<void> _showAddLocationDialog() async {
    final addressController = TextEditingController();
    final cityController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📍 إضافة موقع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'العنوان'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: cityController,
              decoration: const InputDecoration(labelText: 'المدينة'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == true && addressController.text.isNotEmpty) {
      try {
        await _repository.addLocation(
          CommitmentLocation(
            id: '',
            commitmentId: widget.commitmentId,
            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
            locationType: 'عنوان',
            address: addressController.text,
            city: cityController.text.isEmpty ? null : cityController.text,
            createdAt: DateTime.now(),
          ),
        );
        _showSuccessSnackBar('تمت إضافة الموقع بنجاح');
      } catch (e) {
        _showErrorSnackBar('فشل في إضافة الموقع: $e');
      }
    }
  }

  // === SNACKBARS ===
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
