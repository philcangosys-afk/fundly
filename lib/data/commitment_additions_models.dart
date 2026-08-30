// ============================================================================
// Commitment Additions Data Models
// Date: 2026-08-20
// Purpose: Dart classes for all commitment addition types
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ============================================================================
// 1. PAYMENT MODEL (الدفعات)
// ============================================================================
@immutable
class CommitmentPayment {
  final String id;
  final String commitmentId;
  final String userId;

  final double amount;
  final DateTime paymentDate;
  final String? paymentMethod; // نقدي، بنكي، بطاقة، تحويل، شيك، أخرى
  final String? referenceNumber;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CommitmentPayment({
    required this.id,
    required this.commitmentId,
    required this.userId,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod,
    this.referenceNumber,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommitmentPayment.fromJson(Map<String, dynamic> json) {
    return CommitmentPayment(
      id: json['id'] as String,
      commitmentId: json['commitment_id'] as String,
      userId: json['user_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentDate: DateTime.parse(json['payment_date'] as String),
      paymentMethod: json['payment_method'] as String?,
      referenceNumber: json['reference_number'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commitment_id': commitmentId,
      'user_id': userId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String().split('T').first,
      'payment_method': paymentMethod,
      'reference_number': referenceNumber,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'commitment_id': commitmentId,
      'user_id': userId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String().split('T').first,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (notes != null) 'notes': notes,
    };
  }

  CommitmentPayment copyWith({
    String? id,
    String? commitmentId,
    String? userId,
    double? amount,
    DateTime? paymentDate,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommitmentPayment(
      id: id ?? this.id,
      commitmentId: commitmentId ?? this.commitmentId,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================================
// 2. ATTACHMENT MODEL (المرفقات)
// ============================================================================
@immutable
class CommitmentAttachment {
  final String id;
  final String commitmentId;
  final String userId;

  final String attachmentType; // فاتورة، مستند، إيصال، عقد، صورة، مرفق آخر
  final String fileName;
  final String fileUrl;
  final int? fileSizeKb;
  final String? mimeType;

  final String title;
  final String? description;

  final DateTime uploadedAt;

  const CommitmentAttachment({
    required this.id,
    required this.commitmentId,
    required this.userId,
    required this.attachmentType,
    required this.fileName,
    required this.fileUrl,
    this.fileSizeKb,
    this.mimeType,
    required this.title,
    this.description,
    required this.uploadedAt,
  });

  factory CommitmentAttachment.fromJson(Map<String, dynamic> json) {
    return CommitmentAttachment(
      id: json['id'] as String,
      commitmentId: json['commitment_id'] as String,
      userId: json['user_id'] as String,
      attachmentType: json['attachment_type'] as String,
      fileName: json['file_name'] as String,
      fileUrl: json['file_url'] as String,
      fileSizeKb: json['file_size_kb'] as int?,
      mimeType: json['mime_type'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commitment_id': commitmentId,
      'user_id': userId,
      'attachment_type': attachmentType,
      'file_name': fileName,
      'file_url': fileUrl,
      'file_size_kb': fileSizeKb,
      'mime_type': mimeType,
      'title': title,
      'description': description,
      'uploaded_at': uploadedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'commitment_id': commitmentId,
      'user_id': userId,
      'attachment_type': attachmentType,
      'file_name': fileName,
      'file_url': fileUrl,
      if (fileSizeKb != null) 'file_size_kb': fileSizeKb,
      if (mimeType != null) 'mime_type': mimeType,
      'title': title,
      if (description != null) 'description': description,
    };
  }
}

// ============================================================================
// 3. APPOINTMENT MODEL (المواعيد)
// ============================================================================
@immutable
class CommitmentAppointment {
  final String id;
  final String commitmentId;
  final String userId;

  final String
  appointmentType; // موعد، تذكير، موعد دفع، موعد تجديد، موعد متابعة، أخرى
  final String title;
  final String? description;

  final DateTime appointmentDate;
  final TimeOfDay? appointmentTime;
  final int? durationMinutes;

  final String? location;

  final String status; // قادم، تم، ملغي، مؤجل
  final DateTime? completedAt;

  final bool reminderEnabled;
  final int? reminderMinutesBefore;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CommitmentAppointment({
    required this.id,
    required this.commitmentId,
    required this.userId,
    required this.appointmentType,
    required this.title,
    this.description,
    required this.appointmentDate,
    this.appointmentTime,
    this.durationMinutes,
    this.location,
    required this.status,
    this.completedAt,
    required this.reminderEnabled,
    this.reminderMinutesBefore,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommitmentAppointment.fromJson(Map<String, dynamic> json) {
    TimeOfDay? time;
    if (json['appointment_time'] != null) {
      final parts = (json['appointment_time'] as String).split(':');
      time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return CommitmentAppointment(
      id: json['id'] as String,
      commitmentId: json['commitment_id'] as String,
      userId: json['user_id'] as String,
      appointmentType: json['appointment_type'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      appointmentDate: DateTime.parse(json['appointment_date'] as String),
      appointmentTime: time,
      durationMinutes: json['duration_minutes'] as int?,
      location: json['location'] as String?,
      status: json['status'] as String,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      reminderEnabled: json['reminder_enabled'] as bool,
      reminderMinutesBefore: json['reminder_minutes_before'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commitment_id': commitmentId,
      'user_id': userId,
      'appointment_type': appointmentType,
      'title': title,
      'description': description,
      'appointment_date': appointmentDate.toIso8601String().split('T').first,
      'appointment_time': appointmentTime != null
          ? '${appointmentTime!.hour.toString().padLeft(2, '0')}:${appointmentTime!.minute.toString().padLeft(2, '0')}:00'
          : null,
      'duration_minutes': durationMinutes,
      'location': location,
      'status': status,
      'completed_at': completedAt?.toIso8601String(),
      'reminder_enabled': reminderEnabled,
      'reminder_minutes_before': reminderMinutesBefore,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'commitment_id': commitmentId,
      'user_id': userId,
      'appointment_type': appointmentType,
      'title': title,
      if (description != null) 'description': description,
      'appointment_date': appointmentDate.toIso8601String().split('T').first,
      if (appointmentTime != null)
        'appointment_time':
            '${appointmentTime!.hour.toString().padLeft(2, '0')}:${appointmentTime!.minute.toString().padLeft(2, '0')}:00',
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (location != null) 'location': location,
      'status': status,
      'reminder_enabled': reminderEnabled,
      if (reminderMinutesBefore != null)
        'reminder_minutes_before': reminderMinutesBefore,
    };
  }
}

// ============================================================================
// 4. NOTE MODEL (الملاحظات)
// ============================================================================
@immutable
class CommitmentNote {
  final String id;
  final String commitmentId;
  final String userId;

  final String noteType; // ملاحظة، تسوية، تجديد، بيانات إدارية، تحديث، أخرى
  final String title;
  final String content;

  final bool impactsAmount;
  final double? amountChange;

  final bool impactsDate;
  final DateTime? newDueDate;

  final DateTime createdAt;

  const CommitmentNote({
    required this.id,
    required this.commitmentId,
    required this.userId,
    required this.noteType,
    required this.title,
    required this.content,
    required this.impactsAmount,
    this.amountChange,
    required this.impactsDate,
    this.newDueDate,
    required this.createdAt,
  });

  factory CommitmentNote.fromJson(Map<String, dynamic> json) {
    return CommitmentNote(
      id: json['id'] as String,
      commitmentId: json['commitment_id'] as String,
      userId: json['user_id'] as String,
      noteType: json['note_type'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      impactsAmount: json['impacts_amount'] as bool,
      amountChange: json['amount_change'] != null
          ? (json['amount_change'] as num).toDouble()
          : null,
      impactsDate: json['impacts_date'] as bool,
      newDueDate: json['new_due_date'] != null
          ? DateTime.parse(json['new_due_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commitment_id': commitmentId,
      'user_id': userId,
      'note_type': noteType,
      'title': title,
      'content': content,
      'impacts_amount': impactsAmount,
      'amount_change': amountChange,
      'impacts_date': impactsDate,
      'new_due_date': newDueDate?.toIso8601String().split('T').first,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'commitment_id': commitmentId,
      'user_id': userId,
      'note_type': noteType,
      'title': title,
      'content': content,
      'impacts_amount': impactsAmount,
      if (amountChange != null) 'amount_change': amountChange,
      'impacts_date': impactsDate,
      if (newDueDate != null)
        'new_due_date': newDueDate!.toIso8601String().split('T').first,
    };
  }
}

// ============================================================================
// 5. RELATED PERSON MODEL (الأشخاص المرتبطين)
// ============================================================================
@immutable
class CommitmentPerson {
  final String id;
  final String commitmentId;
  final String userId;

  final String personName;
  final String? roleOrRelationship; // دائن، مدين، شاهد، طرف ثاني، وكيل، محامي
  final String? phoneNumber;
  final String? email;
  final String? nationalId;

  final String? notes;

  final DateTime createdAt;

  const CommitmentPerson({
    required this.id,
    required this.commitmentId,
    required this.userId,
    required this.personName,
    this.roleOrRelationship,
    this.phoneNumber,
    this.email,
    this.nationalId,
    this.notes,
    required this.createdAt,
  });

  factory CommitmentPerson.fromJson(Map<String, dynamic> json) {
    return CommitmentPerson(
      id: json['id'] as String,
      commitmentId: json['commitment_id'] as String,
      userId: json['user_id'] as String,
      personName: json['person_name'] as String,
      roleOrRelationship: json['role_or_relationship'] as String?,
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      nationalId: json['national_id'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commitment_id': commitmentId,
      'user_id': userId,
      'person_name': personName,
      'role_or_relationship': roleOrRelationship,
      'phone_number': phoneNumber,
      'email': email,
      'national_id': nationalId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'commitment_id': commitmentId,
      'user_id': userId,
      'person_name': personName,
      if (roleOrRelationship != null)
        'role_or_relationship': roleOrRelationship,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (email != null) 'email': email,
      if (nationalId != null) 'national_id': nationalId,
      if (notes != null) 'notes': notes,
    };
  }
}

// ============================================================================
// 6. LOCATION MODEL (المواقع)
// ============================================================================
@immutable
class CommitmentLocation {
  final String id;
  final String commitmentId;
  final String userId;

  final String locationType; // عنوان، موقع حدث، مكتب، فرع، أخرى
  final String address;
  final String? city;
  final String? district;
  final String? postalCode;

  final double? latitude;
  final double? longitude;

  final String? notes;

  final DateTime createdAt;

  const CommitmentLocation({
    required this.id,
    required this.commitmentId,
    required this.userId,
    required this.locationType,
    required this.address,
    this.city,
    this.district,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.notes,
    required this.createdAt,
  });

  factory CommitmentLocation.fromJson(Map<String, dynamic> json) {
    return CommitmentLocation(
      id: json['id'] as String,
      commitmentId: json['commitment_id'] as String,
      userId: json['user_id'] as String,
      locationType: json['location_type'] as String,
      address: json['address'] as String,
      city: json['city'] as String?,
      district: json['district'] as String?,
      postalCode: json['postal_code'] as String?,
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commitment_id': commitmentId,
      'user_id': userId,
      'location_type': locationType,
      'address': address,
      'city': city,
      'district': district,
      'postal_code': postalCode,
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'commitment_id': commitmentId,
      'user_id': userId,
      'location_type': locationType,
      'address': address,
      if (city != null) 'city': city,
      if (district != null) 'district': district,
      if (postalCode != null) 'postal_code': postalCode,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (notes != null) 'notes': notes,
    };
  }
}

// ============================================================================
// 7. PAYMENT SUMMARY MODEL (ملخص الدفعات)
// ============================================================================
@immutable
class CommitmentPaymentSummary {
  final String commitmentId;
  final double originalAmount;
  final double paidAmount;
  final double remainingAmount;
  final String paymentStatus; // مكتمل، جزئي، لم يُسدد
  final int paymentCount;

  const CommitmentPaymentSummary({
    required this.commitmentId,
    required this.originalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentStatus,
    required this.paymentCount,
  });

  factory CommitmentPaymentSummary.fromJson(Map<String, dynamic> json) {
    return CommitmentPaymentSummary(
      commitmentId: json['commitment_id'] as String,
      originalAmount: (json['original_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num).toDouble(),
      remainingAmount: (json['remaining_amount'] as num).toDouble(),
      paymentStatus: json['payment_status'] as String,
      paymentCount: json['payment_count'] as int,
    );
  }

  double get progressPercentage {
    if (originalAmount == 0) return 0.0;
    return (paidAmount / originalAmount * 100).clamp(0.0, 100.0);
  }

  bool get isFullyPaid => remainingAmount <= 0;
  bool get isPartiallyPaid => paidAmount > 0 && remainingAmount > 0;
  bool get isUnpaid => paidAmount == 0;
}

// ============================================================================
// 8. FULL COMMITMENT SUMMARY MODEL (الملخص الكامل)
// ============================================================================
@immutable
class CommitmentFullSummary {
  final String id;
  final String userId;
  final String title;
  final String category;
  final String entryType;
  final double originalAmount;
  final DateTime? dueDate;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Payment summary
  final double paidAmount;
  final double remainingAmount;
  final String paymentStatus;
  final int paymentCount;

  // Counts
  final int attachmentsCount;
  final int upcomingAppointmentsCount;
  final int notesCount;
  final int relatedPeopleCount;
  final int locationsCount;

  // Next appointment
  final DateTime? nextAppointmentDate;

  const CommitmentFullSummary({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    required this.entryType,
    required this.originalAmount,
    this.dueDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentStatus,
    required this.paymentCount,
    required this.attachmentsCount,
    required this.upcomingAppointmentsCount,
    required this.notesCount,
    required this.relatedPeopleCount,
    required this.locationsCount,
    this.nextAppointmentDate,
  });

  factory CommitmentFullSummary.fromJson(Map<String, dynamic> json) {
    return CommitmentFullSummary(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      entryType: json['entry_type'] as String,
      originalAmount: (json['original_amount'] as num).toDouble(),
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      paidAmount: (json['paid_amount'] as num).toDouble(),
      remainingAmount: (json['remaining_amount'] as num).toDouble(),
      paymentStatus: json['payment_status'] as String,
      paymentCount: json['payment_count'] as int,
      attachmentsCount: json['attachments_count'] as int,
      upcomingAppointmentsCount: json['upcoming_appointments_count'] as int,
      notesCount: json['notes_count'] as int,
      relatedPeopleCount: json['related_people_count'] as int,
      locationsCount: json['locations_count'] as int,
      nextAppointmentDate: json['next_appointment_date'] != null
          ? DateTime.parse(json['next_appointment_date'] as String)
          : null,
    );
  }
}
