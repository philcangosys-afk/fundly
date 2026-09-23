/**
 * سجلّ جداول قاعدة بيانات fundly كما يكتبها التطبيق فعلًا.
 *
 * أسماء الجداول والأعمدة مأخوذة من مستودعات التطبيق نفسه
 * (personal_entries_repository.dart, shared_entries_repository.dart,
 * project_assets_repository.dart, wallets_repository.dart,
 * delegations_repository.dart, commitment_additions_models.dart).
 *
 * اللوحة لا تعتمد على هذا السجل في القراءة — تقرأ `*` دائمًا وتشتق الأعمدة
 * من الصفوف نفسها — بل تستعمله للتسميات العربية وترتيب الأعمدة ونوع كل
 * خانة. فعمود جديد يُضاف في قاعدة البيانات يظهر تلقائيًا في آخر الجدول بلا
 * تعديل هنا.
 */

export type ColumnType =
  | 'text'
  | 'number'
  | 'amount'
  | 'date'
  | 'datetime'
  | 'bool'
  | 'json'
  | 'url'
  | 'id'

export interface ColumnDef {
  key: string
  label: string
  type?: ColumnType
  /** يظهر في عرض الجدول المختصر. الباقي يظهر عند فتح السجل. */
  primary?: boolean
}

export interface TableDef {
  key: string
  label: string
  /** جملة تشرح ماذا يحوي الجدول — تظهر تحت العنوان. */
  hint: string
  group: 'الالتزامات' | 'الأصول والعقارات' | 'المال' | 'الصلاحيات والمستندات' | 'إضافات الالتزامات'
  columns: ColumnDef[]
  /** أعمدة نصية يبحث فيها مربع البحث. */
  search: string[]
  /** عمود الترتيب الافتراضي (تنازليًا). */
  orderBy?: string
  /** عمود المبلغ الذي يُجمع في بطاقة الإجمالي. */
  amountColumn?: string
  /** عرض فقط (مثل العروض views). */
  readOnly?: boolean
}

const entryColumns: ColumnDef[] = [
  { key: 'title', label: 'العنوان', type: 'text', primary: true },
  { key: 'entry_type', label: 'النوع', type: 'text', primary: true },
  { key: 'category', label: 'الفئة', type: 'text', primary: true },
  { key: 'amount', label: 'المبلغ', type: 'amount', primary: true },
  { key: 'due_date', label: 'تاريخ الاستحقاق', type: 'date', primary: true },
  { key: 'status', label: 'الحالة', type: 'text', primary: true },
  { key: 'created_at', label: 'أُنشئ في', type: 'datetime', primary: true },
  { key: 'details', label: 'التفاصيل', type: 'json' },
  { key: 'attachment_url', label: 'المرفق', type: 'url' },
  { key: 'user_id', label: 'الحساب', type: 'id' },
  { key: 'id', label: 'المعرّف', type: 'id' },
]

export const TABLES: TableDef[] = [
  {
    key: 'personal_entries',
    label: 'الالتزامات الشخصية',
    hint: 'كل ما يسجّله المستخدم في وحدة الالتزامات الشخصية: مالية ومستندات ومتابعة.',
    group: 'الالتزامات',
    columns: entryColumns,
    search: ['title', 'entry_type', 'category', 'status'],
    orderBy: 'created_at',
    amountColumn: 'amount',
  },
  {
    key: 'shared_entries',
    label: 'الالتزامات المشتركة',
    hint: 'المشاركات المشتركة والرحلات والجمعيات المالية واللقاءات، ومعها الأعضاء وسجل المصروفات داخل التفاصيل.',
    group: 'الالتزامات',
    columns: entryColumns,
    search: ['title', 'entry_type', 'category', 'status'],
    orderBy: 'created_at',
    amountColumn: 'amount',
  },
  {
    key: 'project_assets',
    label: 'العقارات والأنشطة والآليات',
    hint: 'كل أصل: عقار أو نشاط تجاري أو آلية ومعدة، ومعه حالته ومؤشراته.',
    group: 'الأصول والعقارات',
    columns: [
      { key: 'title', label: 'الاسم', type: 'text', primary: true },
      { key: 'category', label: 'الفئة', type: 'text', primary: true },
      { key: 'sub_type', label: 'النوع الفرعي', type: 'text', primary: true },
      { key: 'status', label: 'الحالة', type: 'text', primary: true },
      { key: 'location_or_type', label: 'الموقع', type: 'text', primary: true },
      { key: 'amount_label', label: 'القيمة', type: 'text', primary: true },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime', primary: true },
      { key: 'owner', label: 'المالك', type: 'text' },
      { key: 'tenant', label: 'المستأجر', type: 'text' },
      { key: 'rent_value', label: 'قيمة الإيجار', type: 'text' },
      { key: 'end_date', label: 'تاريخ الانتهاء', type: 'text' },
      { key: 'annual_yield', label: 'العائد السنوي', type: 'text' },
      { key: 'occupancy_rate', label: 'نسبة الإشغال', type: 'text' },
      { key: 'contract_progress', label: 'تقدم العقود', type: 'number' },
      { key: 'payment_progress', label: 'تقدم الدفعات', type: 'number' },
      { key: 'documents_progress', label: 'تقدم المستندات', type: 'number' },
      { key: 'needs_attention', label: 'يحتاج متابعة', type: 'bool' },
      { key: 'followup_note', label: 'ملاحظة المتابعة', type: 'text' },
      { key: 'serial_number', label: 'الرقم التسلسلي', type: 'text' },
      { key: 'is_frozen', label: 'مجمّد', type: 'bool' },
      { key: 'is_pinned', label: 'مثبّت', type: 'bool' },
      { key: 'is_sublease', label: 'إيجار من الباطن', type: 'bool' },
      { key: 'map_link', label: 'رابط الخريطة', type: 'url' },
      { key: 'cover_url', label: 'صورة الغلاف', type: 'url' },
      { key: 'description', label: 'الوصف', type: 'text' },
      { key: 'units_json', label: 'الوحدات', type: 'json' },
      { key: 'employees_json', label: 'الموظفون', type: 'json' },
      { key: 'logs_json', label: 'السجل', type: 'json' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['title', 'category', 'sub_type', 'status', 'owner', 'tenant'],
    orderBy: 'created_at',
  },
  {
    key: 'project_asset_entries',
    label: 'بنود الأصول',
    hint: 'ما يُضاف داخل كل أصل: مالية ومستندات ومتابعة ومواقع.',
    group: 'الأصول والعقارات',
    columns: [
      { key: 'kind', label: 'النوع', type: 'text', primary: true },
      { key: 'asset_id', label: 'الأصل', type: 'id', primary: true },
      { key: 'data', label: 'البيانات', type: 'json', primary: true },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime', primary: true },
      { key: 'attachment_url', label: 'المرفق', type: 'url' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['kind'],
    orderBy: 'created_at',
  },
  {
    key: 'property_unit_contracts',
    label: 'عقود الوحدات',
    hint: 'عقد إيجار لكل وحدة داخل عقار: المستأجر والقيمة ودورة الدفع والمدة.',
    group: 'الأصول والعقارات',
    columns: [
      { key: 'unit_name', label: 'الوحدة', type: 'text', primary: true },
      { key: 'tenant_name', label: 'المستأجر', type: 'text', primary: true },
      { key: 'annual_rent', label: 'الإيجار السنوي', type: 'amount', primary: true },
      { key: 'payment_cycle', label: 'دورة الدفع', type: 'text', primary: true },
      { key: 'start_date', label: 'من', type: 'date', primary: true },
      { key: 'end_date', label: 'إلى', type: 'date', primary: true },
      { key: 'status', label: 'الحالة', type: 'text', primary: true },
      { key: 'tenant_phone', label: 'هاتف المستأجر', type: 'text' },
      { key: 'lease_type', label: 'نوع العقد', type: 'text' },
      { key: 'unit_key', label: 'مفتاح الوحدة', type: 'text' },
      { key: 'group_key', label: 'المجموعة', type: 'text' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'asset_id', label: 'الأصل', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['unit_name', 'tenant_name', 'status', 'lease_type'],
    orderBy: 'end_date',
    amountColumn: 'annual_rent',
  },
  {
    key: 'property_unit_payments',
    label: 'دفعات الوحدات',
    hint: 'جدول دفعات كل عقد: المستحق والمدفوع وتاريخ السداد.',
    group: 'الأصول والعقارات',
    columns: [
      { key: 'due_date', label: 'تاريخ الاستحقاق', type: 'date', primary: true },
      { key: 'amount_due', label: 'المستحق', type: 'amount', primary: true },
      { key: 'amount_paid', label: 'المدفوع', type: 'amount', primary: true },
      { key: 'status', label: 'الحالة', type: 'text', primary: true },
      { key: 'paid_at', label: 'سُدِّد في', type: 'datetime', primary: true },
      { key: 'reference_no', label: 'رقم المرجع', type: 'text' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'contract_id', label: 'العقد', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['status', 'reference_no'],
    orderBy: 'due_date',
    amountColumn: 'amount_due',
  },
  {
    key: 'property_unit_transactions',
    label: 'حركات الوحدات',
    hint: 'مصروفات وإيرادات مسجَّلة على وحدة بعينها.',
    group: 'الأصول والعقارات',
    columns: [
      { key: 'kind', label: 'النوع', type: 'text', primary: true },
      { key: 'amount', label: 'المبلغ', type: 'amount', primary: true },
      { key: 'occurred_on', label: 'التاريخ', type: 'date', primary: true },
      { key: 'category', label: 'الفئة', type: 'text', primary: true },
      { key: 'unit_key', label: 'الوحدة', type: 'text', primary: true },
      { key: 'note', label: 'ملاحظة', type: 'text' },
      { key: 'asset_id', label: 'الأصل', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['kind', 'category', 'note'],
    orderBy: 'occurred_on',
    amountColumn: 'amount',
  },
  {
    key: 'wallets',
    label: 'المحافظ',
    hint: 'حسابات ومحافظ المستخدم: الرصيد الافتتاحي والعملة وجهة الإصدار.',
    group: 'المال',
    columns: [
      { key: 'name', label: 'الاسم', type: 'text', primary: true },
      { key: 'kind', label: 'النوع', type: 'text', primary: true },
      { key: 'issuer', label: 'الجهة', type: 'text', primary: true },
      { key: 'opening_balance', label: 'الرصيد الافتتاحي', type: 'amount', primary: true },
      { key: 'currency', label: 'العملة', type: 'text', primary: true },
      { key: 'is_default', label: 'الافتراضية', type: 'bool', primary: true },
      { key: 'last4', label: 'آخر 4 أرقام', type: 'text' },
      { key: 'color', label: 'اللون', type: 'text' },
      { key: 'is_archived', label: 'مؤرشفة', type: 'bool' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['name', 'kind', 'issuer', 'currency'],
    orderBy: 'created_at',
    amountColumn: 'opening_balance',
  },
  {
    key: 'wallet_transactions',
    label: 'حركات المحافظ',
    hint: 'كل إيداع وسحب وتحويل بين المحافظ.',
    group: 'المال',
    columns: [
      { key: 'kind', label: 'النوع', type: 'text', primary: true },
      { key: 'amount', label: 'المبلغ', type: 'amount', primary: true },
      { key: 'occurred_on', label: 'التاريخ', type: 'date', primary: true },
      { key: 'category', label: 'الفئة', type: 'text', primary: true },
      { key: 'wallet_id', label: 'المحفظة', type: 'id', primary: true },
      { key: 'note', label: 'ملاحظة', type: 'text' },
      { key: 'transfer_group', label: 'مجموعة التحويل', type: 'text' },
      { key: 'counterparty_wallet_id', label: 'المحفظة المقابلة', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['kind', 'category', 'note'],
    orderBy: 'occurred_on',
    amountColumn: 'amount',
  },
  {
    key: 'delegations',
    label: 'التفويضات',
    hint: 'من فُوِّض، وعلى أي نطاق، وبأي صلاحيات، ولأي مدة.',
    group: 'الصلاحيات والمستندات',
    columns: [
      { key: 'delegate_name', label: 'المفوَّض له', type: 'text', primary: true },
      { key: 'scope', label: 'النطاق', type: 'text', primary: true },
      { key: 'permissions', label: 'الصلاحيات', type: 'json', primary: true },
      { key: 'start_date', label: 'من', type: 'date', primary: true },
      { key: 'end_date', label: 'إلى', type: 'date', primary: true },
      { key: 'is_paused', label: 'موقوف', type: 'bool', primary: true },
      { key: 'delegate_ref', label: 'مرجع المفوَّض له', type: 'text' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['delegate_name', 'scope', 'notes'],
    orderBy: 'created_at',
  },
  {
    key: 'document_records',
    label: 'المستندات',
    hint: 'المستندات والإيصالات المنشأة من القوالب، ومعها أرقامها وتواريخها.',
    group: 'الصلاحيات والمستندات',
    columns: [
      { key: 'doc_type', label: 'نوع المستند', type: 'text', primary: true },
      { key: 'doc_number', label: 'رقم المستند', type: 'text', primary: true },
      { key: 'linked_label', label: 'مرتبط بـ', type: 'text', primary: true },
      { key: 'linked_kind', label: 'نوع الارتباط', type: 'text', primary: true },
      { key: 'issued_on', label: 'تاريخ الإصدار', type: 'date', primary: true },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime', primary: true },
      { key: 'fields', label: 'الحقول', type: 'json' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'linked_id', label: 'معرّف الارتباط', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['doc_type', 'doc_number', 'linked_label'],
    orderBy: 'created_at',
  },
  {
    key: 'commitment_payments',
    label: 'دفعات الالتزامات',
    hint: 'كل دفعة سُدِّدت على التزام، بطريقتها ومرجعها.',
    group: 'إضافات الالتزامات',
    columns: [
      { key: 'amount', label: 'المبلغ', type: 'amount', primary: true },
      { key: 'payment_date', label: 'تاريخ الدفع', type: 'date', primary: true },
      { key: 'payment_method', label: 'طريقة الدفع', type: 'text', primary: true },
      { key: 'reference_number', label: 'رقم المرجع', type: 'text', primary: true },
      { key: 'commitment_id', label: 'الالتزام', type: 'id', primary: true },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['payment_method', 'reference_number', 'notes'],
    orderBy: 'payment_date',
    amountColumn: 'amount',
  },
  {
    key: 'commitment_people',
    label: 'أشخاص الالتزامات',
    hint: 'الأطراف المرتبطة بالتزام: الاسم والدور ووسيلة التواصل.',
    group: 'إضافات الالتزامات',
    columns: [
      { key: 'person_name', label: 'الاسم', type: 'text', primary: true },
      { key: 'role_or_relationship', label: 'الدور', type: 'text', primary: true },
      { key: 'phone_number', label: 'الهاتف', type: 'text', primary: true },
      { key: 'email', label: 'البريد', type: 'text', primary: true },
      { key: 'commitment_id', label: 'الالتزام', type: 'id', primary: true },
      { key: 'national_id', label: 'رقم الهوية', type: 'text' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['person_name', 'role_or_relationship', 'phone_number', 'email'],
    orderBy: 'created_at',
  },
  {
    key: 'commitment_attachments',
    label: 'مرفقات الالتزامات',
    hint: 'الملفات المرفوعة على الالتزامات وأحجامها وأنواعها.',
    group: 'إضافات الالتزامات',
    columns: [
      { key: 'title', label: 'العنوان', type: 'text', primary: true },
      { key: 'attachment_type', label: 'النوع', type: 'text', primary: true },
      { key: 'file_name', label: 'اسم الملف', type: 'text', primary: true },
      { key: 'file_size_kb', label: 'الحجم (ك.ب)', type: 'number', primary: true },
      { key: 'uploaded_at', label: 'رُفع في', type: 'datetime', primary: true },
      { key: 'file_url', label: 'الرابط', type: 'url' },
      { key: 'mime_type', label: 'نوع الملف', type: 'text' },
      { key: 'description', label: 'الوصف', type: 'text' },
      { key: 'commitment_id', label: 'الالتزام', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['title', 'file_name', 'attachment_type'],
    orderBy: 'uploaded_at',
    amountColumn: 'file_size_kb',
  },
  {
    key: 'commitment_notes',
    label: 'ملاحظات الالتزامات',
    hint: 'ملاحظات قد تغيّر المبلغ أو تاريخ الاستحقاق.',
    group: 'إضافات الالتزامات',
    columns: [
      { key: 'title', label: 'العنوان', type: 'text', primary: true },
      { key: 'note_type', label: 'النوع', type: 'text', primary: true },
      { key: 'impacts_amount', label: 'يؤثر في المبلغ', type: 'bool', primary: true },
      { key: 'amount_change', label: 'مقدار التغيير', type: 'amount', primary: true },
      { key: 'new_due_date', label: 'الاستحقاق الجديد', type: 'date', primary: true },
      { key: 'commitment_id', label: 'الالتزام', type: 'id', primary: true },
      { key: 'content', label: 'النص', type: 'text' },
      { key: 'impacts_date', label: 'يؤثر في التاريخ', type: 'bool' },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['title', 'note_type', 'content'],
    orderBy: 'created_at',
  },
  {
    key: 'commitment_appointments',
    label: 'مواعيد الالتزامات',
    hint: 'المواعيد والتذكيرات المرتبطة بالتزام.',
    group: 'إضافات الالتزامات',
    columns: [
      { key: 'title', label: 'العنوان', type: 'text', primary: true },
      { key: 'appointment_type', label: 'النوع', type: 'text', primary: true },
      { key: 'appointment_date', label: 'التاريخ', type: 'date', primary: true },
      { key: 'appointment_time', label: 'الوقت', type: 'text', primary: true },
      { key: 'status', label: 'الحالة', type: 'text', primary: true },
      { key: 'location', label: 'المكان', type: 'text', primary: true },
      { key: 'duration_minutes', label: 'المدة (دقيقة)', type: 'number' },
      { key: 'reminder_enabled', label: 'تذكير', type: 'bool' },
      { key: 'reminder_minutes_before', label: 'التذكير قبل (دقيقة)', type: 'number' },
      { key: 'completed_at', label: 'اكتمل في', type: 'datetime' },
      { key: 'description', label: 'الوصف', type: 'text' },
      { key: 'commitment_id', label: 'الالتزام', type: 'id' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['title', 'appointment_type', 'status', 'location'],
    orderBy: 'appointment_date',
  },
  {
    key: 'commitment_locations',
    label: 'مواقع الالتزامات',
    hint: 'العناوين والإحداثيات المرتبطة بالالتزامات.',
    group: 'إضافات الالتزامات',
    columns: [
      { key: 'address', label: 'العنوان', type: 'text', primary: true },
      { key: 'city', label: 'المدينة', type: 'text', primary: true },
      { key: 'district', label: 'الحي', type: 'text', primary: true },
      { key: 'location_type', label: 'النوع', type: 'text', primary: true },
      { key: 'commitment_id', label: 'الالتزام', type: 'id', primary: true },
      { key: 'postal_code', label: 'الرمز البريدي', type: 'text' },
      { key: 'latitude', label: 'خط العرض', type: 'number' },
      { key: 'longitude', label: 'خط الطول', type: 'number' },
      { key: 'notes', label: 'ملاحظات', type: 'text' },
      { key: 'created_at', label: 'أُنشئ في', type: 'datetime' },
      { key: 'user_id', label: 'الحساب', type: 'id' },
      { key: 'id', label: 'المعرّف', type: 'id' },
    ],
    search: ['address', 'city', 'district', 'location_type'],
    orderBy: 'created_at',
  },
]

export const TABLE_GROUPS = [
  'الالتزامات',
  'الأصول والعقارات',
  'المال',
  'الصلاحيات والمستندات',
  'إضافات الالتزامات',
] as const

export function tableByKey(key: string): TableDef | undefined {
  return TABLES.find((table) => table.key === key)
}

/** ترتيب الأعمدة: المعروفة أولًا بترتيب السجل، ثم أي عمود جديد لم يُسجَّل. */
export function orderColumns(table: TableDef | undefined, rows: Record<string, unknown>[]) {
  const seen = new Set<string>()
  rows.forEach((row) => Object.keys(row).forEach((key) => seen.add(key)))
  const known = (table?.columns ?? []).filter((column) => seen.has(column.key))
  const knownKeys = new Set(known.map((column) => column.key))
  const extra: ColumnDef[] = [...seen]
    .filter((key) => !knownKeys.has(key))
    .map((key) => ({ key, label: key, type: 'text' as ColumnType }))
  return [...known, ...extra]
}
