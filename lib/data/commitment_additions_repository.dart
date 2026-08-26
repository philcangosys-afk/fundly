// ============================================================================
// Commitment Additions Repository
// Date: 2026-08-20
// Purpose: Data access layer for all commitment addition operations
// ============================================================================
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'commitment_additions_models.dart';

class CommitmentAdditionsRepository {
  final SupabaseClient _client;

  CommitmentAdditionsRepository(this._client);

  String get _userId => _client.auth.currentUser?.id ?? '';

  // ==========================================================================
  // PAYMENTS
  // ==========================================================================

  /// Get all payments for a commitment
  Future<List<CommitmentPayment>> getPayments(String commitmentId) async {
    final response = await _client
        .from('commitment_payments')
        .select()
        .eq('commitment_id', commitmentId)
        .order('payment_date', ascending: false);

    return (response as List)
        .map((json) => CommitmentPayment.fromJson(json))
        .toList();
  }

  /// Add a new payment
  Future<CommitmentPayment> addPayment(CommitmentPayment payment) async {
    final response = await _client
        .from('commitment_payments')
        .insert(payment.toInsertJson())
        .select()
        .single();

    return CommitmentPayment.fromJson(response);
  }

  /// Update a payment
  Future<CommitmentPayment> updatePayment(CommitmentPayment payment) async {
    final response = await _client
        .from('commitment_payments')
        .update({
          'amount': payment.amount,
          'payment_date': payment.paymentDate.toIso8601String().split('T').first,
          'payment_method': payment.paymentMethod,
          'reference_number': payment.referenceNumber,
          'notes': payment.notes,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', payment.id)
        .select()
        .single();

    return CommitmentPayment.fromJson(response);
  }

  /// Delete a payment
  Future<void> deletePayment(String paymentId) async {
    await _client.from('commitment_payments').delete().eq('id', paymentId);
  }

  /// Get payment summary for a commitment
  Future<CommitmentPaymentSummary?> getPaymentSummary(
      String commitmentId) async {
    final response = await _client
        .from('commitment_payment_summary')
        .select()
        .eq('commitment_id', commitmentId)
        .maybeSingle();

    if (response == null) return null;
    return CommitmentPaymentSummary.fromJson(response);
  }

  // ==========================================================================
  // ATTACHMENTS
  // ==========================================================================

  /// Get all attachments for a commitment
  Future<List<CommitmentAttachment>> getAttachments(
      String commitmentId) async {
    final response = await _client
        .from('commitment_attachments')
        .select()
        .eq('commitment_id', commitmentId)
        .order('uploaded_at', ascending: false);

    return (response as List)
        .map((json) => CommitmentAttachment.fromJson(json))
        .toList();
  }

  /// Add a new attachment
  Future<CommitmentAttachment> addAttachment(
      CommitmentAttachment attachment) async {
    final response = await _client
        .from('commitment_attachments')
        .insert(attachment.toInsertJson())
        .select()
        .single();

    return CommitmentAttachment.fromJson(response);
  }

  /// Delete an attachment (and its file from storage)
  Future<void> deleteAttachment(
      String attachmentId, String fileUrl) async {
    // Delete from database
    await _client
        .from('commitment_attachments')
        .delete()
        .eq('id', attachmentId);

    // Delete from storage
    try {
      final path = Uri.parse(fileUrl).path.split('/').last;
      await _client.storage.from('commitment-attachments').remove([path]);
    } catch (e) {
      // Ignore storage errors if file doesn't exist
    }
  }

  /// Upload attachment file to storage
  Future<String> uploadAttachmentFile(
    String commitmentId,
    String fileName,
    List<int> fileBytes,
  ) async {
    final path = '$_userId/$commitmentId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    
    await _client.storage.from('commitment-attachments').uploadBinary(
          path,
          Uint8List.fromList(fileBytes),
          fileOptions: const FileOptions(upsert: false),
        );

    return _client.storage.from('commitment-attachments').getPublicUrl(path);
  }

  // ==========================================================================
  // APPOINTMENTS
  // ==========================================================================

  /// Get all appointments for a commitment
  Future<List<CommitmentAppointment>> getAppointments(
      String commitmentId) async {
    final response = await _client
        .from('commitment_appointments')
        .select()
        .eq('commitment_id', commitmentId)
        .order('appointment_date', ascending: false);

    return (response as List)
        .map((json) => CommitmentAppointment.fromJson(json))
        .toList();
  }

  /// Get upcoming appointments for a commitment
  Future<List<CommitmentAppointment>> getUpcomingAppointments(
      String commitmentId) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final response = await _client
        .from('commitment_appointments')
        .select()
        .eq('commitment_id', commitmentId)
        .eq('status', 'قادم')
        .gte('appointment_date', today)
        .order('appointment_date', ascending: true);

    return (response as List)
        .map((json) => CommitmentAppointment.fromJson(json))
        .toList();
  }

  /// Add a new appointment
  Future<CommitmentAppointment> addAppointment(
      CommitmentAppointment appointment) async {
    final response = await _client
        .from('commitment_appointments')
        .insert(appointment.toInsertJson())
        .select()
        .single();

    return CommitmentAppointment.fromJson(response);
  }

  /// Update an appointment
  Future<CommitmentAppointment> updateAppointment(
      CommitmentAppointment appointment) async {
    final response = await _client
        .from('commitment_appointments')
        .update({
          'appointment_type': appointment.appointmentType,
          'title': appointment.title,
          'description': appointment.description,
          'appointment_date':
              appointment.appointmentDate.toIso8601String().split('T').first,
          'appointment_time': appointment.appointmentTime != null
              ? '${appointment.appointmentTime!.hour.toString().padLeft(2, '0')}:${appointment.appointmentTime!.minute.toString().padLeft(2, '0')}:00'
              : null,
          'duration_minutes': appointment.durationMinutes,
          'location': appointment.location,
          'status': appointment.status,
          'completed_at': appointment.completedAt?.toIso8601String(),
          'reminder_enabled': appointment.reminderEnabled,
          'reminder_minutes_before': appointment.reminderMinutesBefore,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', appointment.id)
        .select()
        .single();

    return CommitmentAppointment.fromJson(response);
  }

  /// Mark appointment as completed
  Future<CommitmentAppointment> completeAppointment(String appointmentId) async {
    final response = await _client
        .from('commitment_appointments')
        .update({
          'status': 'تم',
          'completed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', appointmentId)
        .select()
        .single();

    return CommitmentAppointment.fromJson(response);
  }

  /// Delete an appointment
  Future<void> deleteAppointment(String appointmentId) async {
    await _client
        .from('commitment_appointments')
        .delete()
        .eq('id', appointmentId);
  }

  // ==========================================================================
  // NOTES
  // ==========================================================================

  /// Get all notes for a commitment
  Future<List<CommitmentNote>> getNotes(String commitmentId) async {
    final response = await _client
        .from('commitment_notes')
        .select()
        .eq('commitment_id', commitmentId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => CommitmentNote.fromJson(json))
        .toList();
  }

  /// Add a new note
  Future<CommitmentNote> addNote(CommitmentNote note) async {
    final response = await _client
        .from('commitment_notes')
        .insert(note.toInsertJson())
        .select()
        .single();

    return CommitmentNote.fromJson(response);
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    await _client.from('commitment_notes').delete().eq('id', noteId);
  }

  // ==========================================================================
  // RELATED PEOPLE
  // ==========================================================================

  /// Get all related people for a commitment
  Future<List<CommitmentPerson>> getRelatedPeople(String commitmentId) async {
    final response = await _client
        .from('commitment_people')
        .select()
        .eq('commitment_id', commitmentId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => CommitmentPerson.fromJson(json))
        .toList();
  }

  /// Add a related person
  Future<CommitmentPerson> addRelatedPerson(CommitmentPerson person) async {
    final response = await _client
        .from('commitment_people')
        .insert(person.toInsertJson())
        .select()
        .single();

    return CommitmentPerson.fromJson(response);
  }

  /// Update a related person
  Future<CommitmentPerson> updateRelatedPerson(CommitmentPerson person) async {
    final response = await _client
        .from('commitment_people')
        .update({
          'person_name': person.personName,
          'role_or_relationship': person.roleOrRelationship,
          'phone_number': person.phoneNumber,
          'email': person.email,
          'national_id': person.nationalId,
          'notes': person.notes,
        })
        .eq('id', person.id)
        .select()
        .single();

    return CommitmentPerson.fromJson(response);
  }

  /// Delete a related person
  Future<void> deleteRelatedPerson(String personId) async {
    await _client.from('commitment_people').delete().eq('id', personId);
  }

  // ==========================================================================
  // LOCATIONS
  // ==========================================================================

  /// Get all locations for a commitment
  Future<List<CommitmentLocation>> getLocations(String commitmentId) async {
    final response = await _client
        .from('commitment_locations')
        .select()
        .eq('commitment_id', commitmentId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => CommitmentLocation.fromJson(json))
        .toList();
  }

  /// Add a location
  Future<CommitmentLocation> addLocation(CommitmentLocation location) async {
    final response = await _client
        .from('commitment_locations')
        .insert(location.toInsertJson())
        .select()
        .single();

    return CommitmentLocation.fromJson(response);
  }

  /// Delete a location
  Future<void> deleteLocation(String locationId) async {
    await _client.from('commitment_locations').delete().eq('id', locationId);
  }

  // ==========================================================================
  // FULL SUMMARY
  // ==========================================================================

  /// Get full summary for a commitment with all counts
  Future<CommitmentFullSummary?> getFullSummary(String commitmentId) async {
    final response = await _client
        .from('commitment_full_summary')
        .select()
        .eq('id', commitmentId)
        .maybeSingle();

    if (response == null) return null;
    return CommitmentFullSummary.fromJson(response);
  }

  /// Get all commitments with full summaries
  Future<List<CommitmentFullSummary>> getAllCommitmentsWithSummary() async {
    final response = await _client
        .from('commitment_full_summary')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => CommitmentFullSummary.fromJson(json))
        .toList();
  }
}
