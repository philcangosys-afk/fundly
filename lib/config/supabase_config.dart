class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pcppwpbaknxflzbqbrxj.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBjcHB3cGJha254Zmx6YnFicnhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NDkwMDcsImV4cCI6MjEwMDAyNTAwN30.kyUladJf7EUZeVhtjJDfnEPbHPiqKx8ovyRSbBEL0Is',
  );

  // ============================================================
  // حساب التطبيق الثابت
  // ============================================================
  // يدخل التطبيق به تلقائيًا دون أي شاشة تسجيل دخول، فتبقى البيانات
  // مرتبطة بالحساب لا بنسخة التطبيق — تنجو من حذف التطبيق وتظهر على أي
  // جهاز. بديلًا عن الدخول المجهول الذي كان يُنشئ معرّفًا جديدًا كل مرة
  // فتختفي كل البيانات السابقة.
  //
  // مهم: بما أن هذه البيانات مضمَّنة داخل التطبيق، فكل من يملك نسخة منه
  // يصل إلى نفس السجلات. مناسب للاستخدام الشخصي أو لدائرة موثوقة فقط.
  //
  // يمكن تجاوزهما عند البناء دون تعديل الملف:
  //   flutter build apk --release --dart-define=APP_ACCOUNT_PASSWORD=...
  static const appAccountEmail = String.fromEnvironment(
    'APP_ACCOUNT_EMAIL',
    defaultValue: 'fundly.app.2026@gmail.com',
  );

  static const appAccountPassword = String.fromEnvironment(
    'APP_ACCOUNT_PASSWORD',
    defaultValue: 'Fundly-Shared-2026!',
  );
}
