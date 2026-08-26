# MASTER PROMPT FOR GITHUB COPILOT (VS Code — Agent Mode)
## Project: "Fondly" — existing Flutter app · Arabic / RTL · Modification spec

---

# ⚠️ HOW TO USE THIS FILE (instructions for the human, delete before pasting)

1. Put this file in the repo root as `COPILOT_PROMPT_FONDLY.md`.
2. Open **Copilot Chat → Agent mode** in VS Code.
3. First message to Copilot:
   > Read `COPILOT_PROMPT_FONDLY.md` completely. Then execute **PHASE 0** only. Do not touch any other phase. When PHASE 0 is done, print its acceptance checklist and stop.
4. After each phase finishes and the app builds, send:
   > Execute **PHASE N** from `COPILOT_PROMPT_FONDLY.md`. Do not start any other phase. Stop when its acceptance checklist passes.
5. Never ask for two phases at once. The phases are ordered so the app is always in a working state.

---

# SECTION A — SYSTEM RULES FOR THE AI AGENT

You are working on an **existing, functioning Flutter application**. This is a **modification task, not a rewrite**.

### A.1 Absolute rules

1. **DO NOT redesign anything.** The visual system is final: card shapes, corner radii, shadows, spacing, module colors (blue = Personal Commitments, dark teal = Shared Commitments, purple = People & Entities, green/amber = Properties & Businesses), the beige "Follow-up Center" banner, chips, FAB, bottom nav, fonts. You change **fields, categories, navigation logic, and behavior** — never the look.
2. **If a screen/widget/button already exists → edit it in place.** Never create `HomeScreenV2`, `NewPersonPage`, etc. Never leave a dead duplicate.
3. **If something in this spec does not exist in the code → create it**, and style it by **copying the closest existing widget** as the visual base.
4. **Never delete an existing feature** that this spec does not mention. Leave it untouched.
5. **The app UI language is Arabic and the layout is RTL.** Every label in this document is written as `English meaning (النص العربي)`. **The string you write into the UI is the Arabic one, exactly as given.** The English is only so you understand the intent.
6. **No hardcoded strings.** Put all Arabic strings in the existing localization/strings layer (`ARB`/`intl`/constants file — use whatever the project already uses; if none exists, create `lib/l10n/app_ar.arb` and route everything through it).
7. **Never invent placeholder data.** Every number shown in the UI is computed from the data layer. If data does not exist yet, show `0` / an empty state — never fake numbers.
8. **Work incrementally and verify.** After each sub-step: `flutter analyze` must be clean of new errors, and `flutter build` (or hot reload) must succeed. Fix your own errors before continuing.
9. **Do not refactor unrelated code.** No mass reformatting, no dependency upgrades, no state-management migration unless a phase explicitly asks.
10. At the end of every phase output: (a) list of files created/modified, (b) 3–6 line summary, (c) the phase's acceptance checklist with ✅/❌, (d) any assumption you had to make.

### A.2 Repeating conventions that apply to the whole app

- **`+ Add other (+ إضافة أخرى)`** — **every** category list and sub-category list in this document ends with this item. It is a real feature, not a label: tapping it opens a small dialog (name + optional icon), saves a **user-defined category** to local storage, selects it immediately, and shows it in that same picker forever after. Custom items are editable/deletable; built-in items are not.
- **Field types:** date → date picker · time → time picker · amount → numeric keyboard + currency (default `درهم`, overridable where a currency field exists) · phone → phone keyboard · "attach document (إرفاق مستند)" → camera / gallery / files picker, multiple files allowed.
- **Form structure:** every entry form is split into two visual sections — **main fields** at top, then a collapsible **"Additional information (معلومات إضافية)"** section. Follow the exact field order given in this document.
- **Expiry + reminder:** every document, receipt, warranty and contract carries `expiryDate` **and** a user-chosen reminder lead time (7 / 15 / 30 / 60 / 90 days or custom). These feed the Smart Calendar, the Follow-up Centers, and the notification bell.
- **Linking:** anything created inside a detail page (a person, a trip, a property) is linked to that parent **and** simultaneously appears in the relevant global module list and in the calendar/counters. One record, many views — never duplicate the row.

---

# SECTION B — THE PHASES

---

## PHASE 0 — Audit (no behavior changes)

**Goal:** understand the codebase before modifying it.

**Steps**
1. Print a tree of `lib/` and list: all routes/screens, the four module list screens, all models, the storage layer (Hive / SQLite / Isar / Firebase — say which), the state management in use, and the theme file.
2. Locate and report the files behind these existing UI pieces:
   - Home dashboard with the 4 module cards
   - Bottom navigation bar
   - The beige **Follow-up Center (مركز المتابعة)** banner
   - The category chips row
   - The "+ Add (+ إضافة)" FAB and its bottom sheet
   - Any existing detail page with tabs
3. Report whether each of the following is **shared** or **duplicated per module**, and list duplicates:
   `ModuleHeader`, `SearchAndFilterBar`, `FollowUpCenter`, `CategoryChipsRow`, `ListHeaderRow`, `EntityCard`, `AddFab`, `AddTypeSheet`, `DetailScaffold`, `ThreeDotMenu`.
4. Report any conflict between the current code and this spec.

**Do not change any file in Phase 0.**

**Acceptance**
- [ ] Inventory printed
- [ ] Duplicated widgets identified
- [ ] Conflicts listed

---

## PHASE 1 — Extract shared widgets (visual result must be identical)

**Goal:** one source of truth per component, so later phases are configured, not copy-pasted.

**Steps**
1. Create `lib/widgets/shared/` and move/merge the duplicated widgets found in Phase 0 into single configurable widgets:

| Widget | Configurable inputs |
|---|---|
| `ModuleHeader` | icon, title, subtitle, module color, smart-calendar icon, close button |
| `SearchAndFilterBar` | hint text, onSearch, onFilter |
| `FollowUpCenter` | **exactly 3 KPI slots** (label + number + icon) + "More (المزيد)" chevron. **Design is identical in all four modules — only the 3 metrics differ.** |
| `CategoryChipsRow` | list of `(label, count, onTap)`, first chip always "All (الكل)" |
| `ListHeaderRow` | count badge, title, sort dropdown default "Newest first (الأحدث أولاً)" |
| `EntityCard` | leading image/icon, title, `(category)`, subtitle lines, trailing pills, onTap |
| `AddFab` | label "+ إضافة", **must be draggable by the user and its position persisted per screen** |
| `AddTypeSheet` | grouped options: `group title → [option, option, ...]` |
| `DetailScaffold` | header card slot, horizontal tab strip, action buttons row, 3-dot menu |
| `ThreeDotMenu` | fixed items: تعديل البيانات / مشاركة / حذف / تجميد / تثبيت الصفحة في الصفحة الرئيسية |

2. Replace every duplicate usage with the shared widget.
3. **Pixel-parity requirement:** the app must look exactly the same after this phase as before it.

**Acceptance**
- [ ] Zero duplicated versions of the above widgets remain
- [ ] App builds, all screens visually unchanged

---

## PHASE 2 — Data layer: taxonomy, models, custom categories

**Goal:** encode every category and every form field-set as data **before** any UI work.

**Steps**

1. Create `lib/data/taxonomy/` and encode, as Dart const maps or JSON assets, **every** main-category → sub-category list and **every** form field list from Phases 5–8 of this file. Nothing may be typed ad-hoc inside a widget later.

2. Models:

```dart
class EntryType   { String id, module, groupId, labelAr; IconData icon; List<FieldSpec> fields; }
class MainCategory{ String id, entryTypeId, labelAr; bool isCustom; }
class SubCategory { String id, mainCategoryId, labelAr; bool isCustom; }
class FieldSpec   { String key, labelAr; FieldKind kind; bool required; bool optionalTag;
                    FieldSection section; /* main | additional */ }

enum FieldKind { text, number, money, date, time, dropdown, multiselect, toggle,
                 notes, attachment, phone, email, location, currency, repeat,
                 reminder, image, personRef, membersRef, priority }
```

3. Unified record:

```dart
class Entry {
  String id, module, entryTypeId;
  String? mainCategoryId, subCategoryId, ownerRefId; // person / property / trip / null
  num? amount; String? currency;
  DateTime? date; TimeOfDay? time;
  String? title, notes, status;
  DateTime? expiryDate; int? reminderLeadDays;
  List<String> attachments;
  Map<String, dynamic> extra;
  DateTime createdAt, updatedAt;
  bool isArchived, isFrozen, isPinned;
}
```

4. `custom_categories` store: `{id, module, entryTypeId, parentId, labelAr, createdAt}` + CRUD + the `+ إضافة أخرى` dialog widget that any picker can call.

5. **Migration:** map all existing user records onto the new schema. **No data loss.** Write and run the migration, and print how many records were migrated.

6. Repositories with live streams so the Home KPIs, Follow-up Centers and calendar recompute automatically.

**Acceptance**
- [ ] All categories/fields from Phases 5–8 exist in the taxonomy files
- [ ] Migration runs, old data intact
- [ ] Creating a custom category from a unit test persists and reappears

---

## PHASE 3 — App shell: bottom nav, header, Profile & Settings

### 3.1 Bottom navigation — exactly 4 items (current labels are wrong)

| RTL order (right → left) | Label | Destination |
|---|---|---|
| 1 | Home (الرئيسية) | dashboard |
| 2 | **Reports / Archive (التقارير / الأرشيف)** | **rename the existing "التقارير" tab to this** — one screen, two tabs (Phase 4) |
| 3 | Wallets (المحافظ) | existing screen, unchanged |
| 4 | **More (المزيد)** — NEW | Profile & Settings |

The separate **الأرشيف** bottom tab that exists today is **merged into item 2 and removed from the bar**.

### 3.2 Home top header

- Avatar + **"مرحباً عبدالعزيز الهاجري"** → **tapping the name OR the avatar opens the Profile & Settings screen** (identical destination to "المزيد").
- **Smart Calendar icon (كلندر ذكي)** → Smart Calendar screen (Phase 4.3). Place this same icon in the header of **all four module list screens**.
- **Notification bell** with unread badge → notifications center listing due dates, expiries, reminders.
- Subtitle line: `أموالك، أصولك، التزاماتك وعلاقاتك في لوحة واحدة`

### 3.3 Profile & Settings screen (create if missing)
Sections: profile data (photo, name, phone, email) · **signature & stamp (التوقيع والختم)** placeholders (implemented in Phase 9) · currency & language · notifications & reminder defaults · security (biometric lock for passwords section) · backup/export · about.

**Acceptance**
- [ ] Bottom bar = الرئيسية / التقارير-الأرشيف / المحافظ / المزيد
- [ ] Name, avatar and المزيد all open Profile & Settings
- [ ] Calendar icon present on Home + all four module headers

---

## PHASE 4 — Home screen, Smart Calendar, General Summary, Reports/Archive

### 4.1 Home
- **Layout toggle** (the small squares icon next to `أدر أموالك وأملاكك باحترافية`): switches the 4 module cards between **grid (two side by side — DEFAULT)** and **stacked (one per row)**. Persist the choice.
- **Search + filter** across all modules. **Layout note:** the search box and the "General Summary" box must be inset the same small margin (~0.5 cm) from both the right and left edges — use one shared horizontal padding token.
- **Pin (تثبيت):** long-press any module card or any detail page → pin it to Home; a pinned-shortcuts strip renders on Home. Long-press again or 3-dot → unpin.
- **The four module cards** keep their current look; only the mini-stats change, all computed live:

| Card | The 3 stats |
|---|---|
| العقارات / الأنشطة التجارية / المعدات وأخرى | عدد العقارات · عدد الأنشطة التجارية · تحتاج متابعة |
| الأفراد والجهات | عدد الأفراد · عدد الجهات · تحتاج متابعة |
| الالتزامات المشتركة | رحلات نشطة · جمعيات نشطة · تحتاج متابعة |
| الالتزامات الشخصية | ديون لك · ديون عليك · تحتاج متابعة |

### 4.2 General Summary sheet — `ملخص عام` / `أعرف أمورك بضغطة زر`
Bottom sheet (the visual already exists) with **selectable rows (radio)**:
- **الملخص الشامل:** إجمالي الدخل · إجمالي المصروفات · إجمالي الديون · المستندات (قريبة الانتهاء) · الالتزامات والمهام · إجمالي الأصول
- **معلومات الوحدات:** one row per module
Selected rows are compiled into a summary that can be **read and shared/sent** (text + PDF).

### 4.3 Smart Calendar screen
Calendar on top; below it, everything due on the selected day, aggregated from all modules: debt due dates, installments, document/contract expiries, tasks, appointments, occasions, medication dose times, subscription renewals, money-circle payment days. Tapping an item opens its detail page.

### 4.4 Draw / Raffle tool (قرعة)
Small utility screen: user enters a list of names → runs a randomized draw → result can be saved or shared. Used to set the receiving order of a money circle (Phase 6). Reachable from the Home quick-action shortcut.

### 4.5 Reports / Archive screen — one screen, two top tabs
**Tab التقارير:** the user picks a module and generates a report for it:
`الالتزامات الشخصية` · `العقارات / الأنشطة التجارية / المعدات وأخرى` · `إدارة الأشخاص والجهات` · `الالتزامات المشتركة`
Report builder: date range + category filter + entity filter → preview → **export/share as PDF** and print. Primary button: **`إنشئ الآن`**.
**Tab الأرشيف:** everything archived from any module, filterable by module and date, with **restore** and **permanent delete**.

**Acceptance**
- [ ] Toggle works, default grid, persists
- [ ] 4 cards show real numbers and navigate correctly
- [ ] Pin, general summary, calendar, raffle all functional
- [ ] One report exports as PDF; archive/restore works

---

## PHASE 5 — Module list template (build once, configure four times)

Every one of the four module list screens must be composed of exactly this skeleton:

```
ModuleHeader (icon · title · subtitle · smart-calendar icon · close)
SearchAndFilterBar
FollowUpCenter (3 KPIs + المزيد)      ← identical design in all four modules
"التصنيفات" → CategoryChipsRow (الكل + chips with counts)
ListHeaderRow (count badge · title · "الأحدث أولاً")
List<EntityCard>
AddFab ("+ إضافة") → AddTypeSheet
```

**Critical:** a category chip is **not just a text filter**. **Tapping a chip runs that category's own logic and renders its own card content.** Example: in Phase 7, `الأفراد` and `الجهات` show different fields, different card layout and different quick actions.

The **`المزيد`** chevron on the Follow-up Center opens the full list of items behind those 3 KPIs.

**Acceptance**
- [ ] All four list screens use the same template classes
- [ ] Chips switch logic, not just filter text

---

## PHASE 6 — Module: الالتزامات الشخصية (Personal Commitments)

### 6.1 List screen
- Header subtitle: `إدارة ومتابعة كل التزاماتك في مكان واحد`
- Chips: **`الكل` · `المالية` · `مستند` · `عنصر إداري` · `بيانات وحسابات` · `مناسبة / إشتراك / هدية`**  *(replace the current chips)*
- Follow-up Center KPIs: **`مستحقات` · `مهام` · `وثائق`**
- Card examples: `دين خالد محمد (الديون) — المبلغ / المتبقي` · `طعام ومشروبات (المصروفات الشخصية) — المبلغ / التاريخ`

### 6.2 `+ إضافة` sheet — grouped exactly like this
- **إضافة مالية:** المصروفات الشخصية · الإيراد · دين / قرض / سلفة · العهدة المالية · الغرامات · القسط · تحويل مالي
- **إضافة مستند:** مستندات · وثائق شخصية · ضمانات
- **إضافة عنصر إداري:** مهمة · موعد · عادة · ملاحظات · + إضافة أخرى
- **إضافة بيانات وحسابات:** الأدوية وبياناتها · الكلمات والأرقام السرية
- **إضافة مناسبة / إشتراك:** مناسبة · إشتراك · هدية

### 6.3 FINANCIAL ENTRIES

#### (a) Expense — `مصروف`
**Main:** المبلغ · التصنيف الرئيسي · التصنيف الفرعي · التاريخ · الملاحظات
**معلومات إضافية:** جهة الصرف · طريقة الدفع · الموقع · إرفاق مستند

**Main → sub categories (every list also gets `+ إضافة أخرى`):**

| التصنيف الرئيسي | التصنيفات الفرعية |
|---|---|
| طعام ومشروبات | بقالة وسوبرماركت · مطاعم وكوفيهات · توصيل وطلبات · لحوم ودواجن · خضروات وفواكه · مخبوزات ومعجنات |
| مواصلات | تطبيقات توصيل · نقل عام وتاكسي |
| دفع فواتير | ايجار · انترنت واتصالات · تأمينات · رسوم دراسية |
| صحة | أدوية وصيدلية · أطباء وأشعة · تحاليل وفحوصات |
| تعليم | مصروفات مدرسية · دروس خصوصية · دورات تدريبية · كتب ومراجع |
| تسوق | ملابس · مستلزمات منزلية · تسوق إلكتروني · إلكترونيات · عناية وجمال |
| مغسلة وكوي (مصبغة) | عادي · مستعجل |
| ترفيه | رياضة وجيم · ألعاب · سينما |
| سفر | فنادق وإقامة · تذاكر ورسوم سفر |
| سيارة | وقود · مواقف ورسوم طرق · صيانة وإصلاح · قطع غيار · اكسسوارات سيارات · غسيل وتلميع · مخالفات |
| مصروفات أخرى | خدمات حكومية · سداد أقساط · سداد قروض · رسوم بنكية · غرامات (عام) |

#### (b) Income — `دخل`
Same field-set as the expense form.

| التصنيف الرئيسي | التصنيفات الفرعية |
|---|---|
| الراتب / معاش | الراتب · عمولات · عمل إضافي |
| تعويض واسترجاع | مصروف · كاش باك |

#### (c) Money transfer — `تحويل مالي`
**Main:** المبلغ · تحويل من: · إلى: · التاريخ · العنوان · الملاحظات · **`تفعيل عملية متكررة` (toggle)**
**معلومات إضافية:** طريقة الدفع · إرفاق مستند

#### (d) Debts — `ديون`
Step 1 — choose: **`يدين لي` / `أدين له`**
Step 2 — **بيانات الطرف:** اسم الجهة · العملة · رقم الهاتف · البريد الإلكتروني (اختياري) · ملاحظات (اختياري)
Step 3 — **تفاصيل الدين:** المبلغ · تاريخ الدين · تاريخ الاستحقاق · **`قسّم المبلغ إلى` (عدد الأقساط)**
→ Splitting **auto-generates the installment schedule**; each installment becomes its own due item in the Smart Calendar and the Follow-up Center, and can be marked paid individually with a running remaining balance.

#### (e) Fine — `غرامة`
**Fields:** مبلغ الغرامة · نوع الغرامة (**taken from the sub-category selected above**) · الجهة · تاريخ الاستحقاق
**Sub-categories:** غرامات مرور · حكومية · مالية · تعاقدية · خدمات

### 6.4 ADMINISTRATIVE ENTRIES

**مستند (Document)**
Fields: اسم المستند · التصنيف الرئيسي · التصنيف الفرعي · رقم المستند · الجهة المصدرة · تاريخ الإصدار (اختياري) · **تاريخ الانتهاء** · ملاحظات · إرفاق مستند
Sub-categories: هوية · جواز سفر · إقامة وتأشيرة · رخصة قيادة · ملكية سيارة · تأمين سيارة · تأمين صحي · مستند دراسي · مستند سفر · مستند بنكي · تقرير طبي · تصاريح · ضمانات · فواتير · إيصالات

**التنظيم والمتابعة** — types: مهمة · موعد · عادة · ملاحظات
Fields: عنوان · الوصف · تاريخ الاستحقاق · وقت الاستحقاق · تكرار · الأولوية · ملاحظات · **تفعيل تذكيرات**

**مناسبة (Occasion)** — types: عيد ميلاد · ذكرى زواج / خطوبة · تخرج · وظيفة جديدة · مناسبة عائلية · مناسبة دينية
Fields: اختيار صورة للمناسبة · عنوان المناسبة · نوع المناسبة (from sub-category) · أهمية المناسبة · تاريخ المناسبة · رقم الهاتف · تكرار · تذكيرات · إرفاق مستند

**اشتراكات (Subscriptions)** — types: قنوات تلفزيونية · الهاتف والإنترنت · التطبيقات · خصومات
Fields: الاسم · المبلغ · التكرار · تاريخ الاستحقاق · تذكيرات · ملاحظات · إرفاق مستند

### 6.5 DATA ENTRIES

**كلمات السر (Passwords)** — types: إيميلات · حسابات بنكية · تطبيقات
Fields: اسم الحساب · اسم المستخدم · كلمة السر · الرابط · ملاحظات · إرفاق مستند (اختياري)
**Security requirement:** store encrypted (`flutter_secure_storage` or equivalent); the password is masked by default and revealing it requires device biometric/PIN.

**الأدوية وبياناتها (Medications)** — model this like a dedicated medication-tracker app.
- **لمن هذا الدواء:** `لي` / `لشخص آخر` → if another person, link to a record in `الأفراد والجهات`.
- **بيانات الدواء:** اسم الدواء · فترة الدواء (من: / إلى:) · جدول الجرعات · **`إضافة وقت`** (repeatable, multiple dose times) · **تفعيل التذكيرات**
- **معلومات إضافية:** الاسم العلمي · نوع الدواء (قرص / كبسولة / شراب / حقنة) · التركيز · الجرعة · قبل أو بعد الطعام أو أي وقت · تخصيص الشكل (لون/شكل الحبة) · تفاصيل · اسم الطبيب (اختياري) · اسم الصيدلية (اختياري) · رقم الوصفة (اختياري) · **تفعيل متابعة الكمية المتبقية** · ملاحظات · إرفاق مستند · **تفعيل إخفاء التفاصيل من الشاشة**
- Each dose time creates a recurring local notification and appears in the Smart Calendar. "Remaining quantity" decrements per taken dose and warns when low.

**مواقع وأماكن (Locations)** — types: المنزل · العمل · مطعم · منزل صديق
Fields: **اختيار الموقع الحالي / إضافة من الرابط / من اسم المكان** · التصنيف · الوصف · ملاحظات · صور المكان (اختياري)

### 6.6 Detail page (after tapping a commitment card)
- Header card: title + `(التصنيف)`, amount, address/title line
- Tabs: **`الملخص` · `السجل` · `المستندات` · `المتابعة`**
- Summary fields: تاريخ الإنشاء · نوع الالتزام · الحالة · التاريخ · الساعة · العنوان · المرفقات
- Buttons: **`+ إضافة`** · 3-dot menu (تعديل / مشاركة / حذف / تجميد / تثبيت في الرئيسية)

**Acceptance**
- [ ] Every entry type above creates, lists, filters, opens, edits, archives
- [ ] Installment splitting generates a correct schedule
- [ ] Medication / subscription / occasion reminders fire and show in the calendar
- [ ] Passwords encrypted and biometric-gated

---

## PHASE 7 — Module: إدارة الأشخاص والجهات (People & Entities)
> **This module has the most additions. Read it twice.**

### 7.1 List screen
- Subtitle: `تنظيم العلاقات والالتزامات وبيانات التواصل`
- Chips: **`الكل` · `الأفراد` · `الجهات`** — with the relationship chips (`قريب`, `صديق`, `موظف`, …) as a second-level filter.
  **`الأفراد` and `الجهات` each open their own logic:** different card content, different fields, different quick actions.
- Follow-up Center KPIs: **`مستحقات` · `مهام` · `وثائق`**
- Card: **person photo (user can add one)** · الاسم + `(التصنيف)` · رقم التواصل · `تحتاج متابعة: N` · balance pill (`لك ٥٠٠` / `عليك ١٢٠`) · urgency tag (عاجل / متابعة / تنبيه)
- **`+ إضافة`:** `إضافة فرد` · `إضافة جهة`

### 7.2 `إضافة شخص` (Add individual)
**Main:** التصنيف · الاسم · رقم الهاتف
**معلومات إضافية:** الجنسية · تاريخ الميلاد · البريد الإلكتروني · العنوان · الموقع على الخريطة · ملاحظات · إضافة مستند
**التصنيفات:** قريب · صديق · موظف · عميل · مستأجر · مورد · مقاول · شريك · مؤجر · مندوب · مستشار
**المستندات القابلة للإرفاق:** الهوية · جواز السفر · رخصة القيادة · صور · ضمان صحي · الإقامة · عقد العمل · + إضافة مستند آخر

### 7.3 `إضافة جهة` (Add entity)
**Main:** التصنيف · الاسم · رقم الهاتف · البريد الإلكتروني · ملاحظات
**معلومات إضافية:** العنوان · الموقع على الخريطة · إضافة مستند
**التصنيفات:** شركات · جهة حكومية · بنك · مؤسسات تعليمية · مؤسسات صحية · منظمات
**المستندات:** عقود · رخص تجارية · مستندات مالية · + إضافة أخرى

### 7.4 Detail page (e.g. tapping `محمد سالم`)
Header card: photo · الاسم + `(التصنيف)` · رقم التواصل · `تحتاج متابعة (عام): N`

**Tabs (exactly these six):**
`الملخص` · `المالية` · `المستندات` · `التنظيم والمتابعة والبيانات` · `كلمات السر` · `الملاحظات`

**`الملخص` must display exactly these rows:**
تاريخ الإنشاء · الإسم · الجنسية (اختياري) · تاريخ الميلاد (اختياري) · التصنيف · آخر تحديث · **الرصيد المستحق له** · **الرصيد المستحق عليه** · المهام المفتوحة · المستندات المتوفرة · تحتاج متابعة (عام) · ملاحظات

The two balance rows are **computed** from all financial items linked to this person, never entered by hand.

**3-dot menu:** تعديل البيانات · مشاركة · حذف · تجميد · تثبيت الصفحة في الصفحة الرئيسية

**`+ إضافة` → `اختر نوع الإضافة`:**
- **إضافة مالية:** عهدة مالية · دخل · مصروف · قسط · إشتراك · غرامة
- **إضافة مستند:** مستندات عامة · وثائق شخصية · عقد · فاتورة
- **إضافة عنصر إداري:** مهمة · إجتماع · ملاحظة · تذكير · موعد
- **إضافة تفويض:** تفويض
- **إضافة مواقع وروابط:** موقع · رابط

Everything added here is linked to that person **and** appears in the matching global module list, the calendar, and the counters.

**Acceptance**
- [ ] Person created with photo + documents
- [ ] Adding a financial item updates both balance rows automatically
- [ ] All six tabs populated from real linked data
- [ ] `الأفراد` vs `الجهات` chips render different logic

---

## PHASE 8 — Module: الالتزامات المشتركة (Shared Commitments)

### 8.1 List screen
- Subtitle: `تنظيم الالتزامات المشتركة والدفعات بين المشاركين`
- Chips: **`الكل` · `الرحلات / السفر` · `جمعيات مالية` · `اللقاءات`**
- Follow-up Center KPIs: **`التزامات` · `مستحقات` · `مستندات تحتاج متابعة`**
- Card: الاسم + `(النوع)` · عدد الأعضاء · تاريخ البداية · status pill (`نشطة` / `متأخرة`)
- **`+ إضافة`:** الرحلات / السفر · جمعيات مالية · اللقاءات

### 8.2 Creation forms

**`جمعية مالية`:** اسم الجمعية المالية · الأعضاء · المسؤول · تاريخ البداية · تاريخ النهاية (اختياري) · العملة (اختياري) · قيمة الاشتراك · **دور الاستلام** · عدد الأشهر · موعد الدفع الشهري · ملاحظات (اختياري)
→ Auto-generate the monthly payment schedule and the per-member receiving order. The **قرعة** tool from Phase 4.4 can set that order.

**`الرحلة / السفر`:** اسم الرحلة / السفر · العملة (اختياري) · الميزانية · **التقسيم المالي: `بالتساوي` / `بالنسبة` / `بالمبلغ المحدد`** · الأعضاء مع المسؤول · المسؤول · الوجهة · تاريخ السفر · تاريخ العودة · ملاحظات (اختياري)
→ Every trip expense is split per the chosen method and each member's share/balance is shown in the `المالية` tab.

**`اللقاءات`:** اسم الالتزام · الأعضاء · المسؤول · المبلغ · العملة (اختياري) · مكان التجمع · تاريخ التجمع · ملاحظات (اختياري)

### 8.3 Detail page (e.g. `الرحلة إلى دبي`)
Header card: الاسم + `(النوع)` + status dot · **الميزانية** · **الأعضاء**
Two action buttons under the header: **`+ إضافة`** and **`طلب`**
Tabs: **`الملخص` · `المالية` · `السجل` · `الأعضاء` · `المستندات` · `الملاحظات`**
`الملخص` rows: تاريخ الإنشاء · الاسم · التصنيف · الميزانية · الأعضاء · المسؤول · تاريخ البداية · تاريخ النهاية (اختياري) · العملة · التقسيم المالي · مكان التجمع · ملاحظات
3-dot menu: standard.

**`+ إضافة`:**
- **مالية:** مصروف · إيراد · ميزانية إضافية · تحويل مالي
- **مستند:** مستندات · وثائق شخصية
- **عنصر إداري:** مهمة · إجتماع · ملاحظة · تذكير
- **أعضاء:** عضو
- **تفويض:** تفويض
- **مواقع وروابط:** موقع · رابط

**`طلب` — this is where objections and voting live:**
- **تسوية مالية** — settle balances between members and record who paid whom
- **تصويت** — a question + options sent to members, live tally, result recorded
- **إعتراض** — a member objects to an entry; the objection is attached to that entry until resolved
- **إستبيان** — multi-question survey to the members
Every request is logged in the `السجل` tab with its status (مفتوح / منتهي).

**Acceptance**
- [ ] Money circle generates correct monthly schedule + receiving order
- [ ] All three trip split methods compute per-member shares correctly
- [ ] A vote and an objection can be raised, answered, and resolved

---

## PHASE 9 — Module: العقارات / الأنشطة التجارية / المعدات وأخرى

### 9.1 List screen
- Subtitle: `متابعة الأصول والتجارة والمهام والأداء`
- Chips: **`الكل` · `العقارات` · `الأنشطة التجارية` · `المعدات` · `صيانة`**
- Follow-up Center KPIs: **`دفعات تحتاج متابعة` · `وثائق شخصية تحتاج متابعة` · `عقود تحتاج متابعة`**
- **`+ إضافة`:** إضافة عقار · إضافة نشاط تجاري · إضافة معدة · صيانة · أخرى
- Cards: type logo/icon + state pill —
  عقار → `مؤجرة` / `شاغرة` · نشاط تجاري → `فعال` / `متوقف` · معدة → `تعمل` / `متوقفة` / `تحت الصيانة`
  plus 3 mini-KPIs and, where relevant, **`حالة العقد: قريب الإنتهاء / قريب الاستحقاق`**

### 9.2 Property detail page
Header card: الاسم + `(النوع / المدينة)` + الحالة · **اجمالي الإيجار** · **المتبقي من الإيجار** · **وثائق شخصية تحتاج متابعة**
Action buttons: **`+ إضافة`** · **`طلب تفويض`**
Tabs: **`الملخص` · `المالية` · `المتابعة` · `الصيانة` · `السجل` · `العقود` · `المستندات العامة`**
`الملخص` rows: تاريخ الإنشاء · اسم المشروع · النوع · الحالة · المالك · المستأجر / العميل · تاريخ بداية العقد · تاريخ نهاية العقد · قيمة العقد · العائد السنوي · نسبة الإشغال · ملاحظات

**`+ إضافة`:** الصيانة · العقود · مستندات عامة · الإيرادات · المصروفات
**`طلب تفويض`:** delegate a person (picked from `الأفراد والجهات`) to manage the property — scope, permissions, validity period, and a generated delegation document.

### 9.3 Property description — special requirement
The property's general description must **explicitly capture its annexes**, implemented as a structured checklist with counts **plus** a free-text field — not a plain text box:
`ممرات` · `درج` · `سطح` · `بلكونات` · `غرفة الاتصالات` · `غرفة الكهرباء` · `غرفة الدفاع المدني` · `+ إضافة أخرى`

### 9.4 Business & Equipment detail pages
Same `DetailScaffold` shell, with their own fields:
- **نشاط تجاري:** الرخصة التجارية · تاريخ انتهاء الرخصة · الشركاء · الإيرادات · المصروفات · العقود · حالة العقد
- **معدة:** النوع · الرقم التسلسلي · حالة التشغيل · سجل الصيانة · الضمان وتاريخ انتهائه · المستندات

**Acceptance**
- [ ] All three asset types creatable and editable
- [ ] Contract expiry + payment due items appear in Follow-up Center and calendar
- [ ] Delegation works end to end
- [ ] Annex checklist saved with the property

---

## PHASE 10 — Documents engine: templates, signature & stamp, expiry reminders

1. **Ready-made fillable templates, exported as Arabic RTL PDFs** (professional layout, the user fills the blanks, data auto-fills from the linked person/property/entry where possible):
   - `إيصال أمانة` (debt trust receipt)
   - `إيصالات استلام وتسليم` (handover / receipt vouchers)
   - `فواتير` (invoices)
   - `تقارير ضريبية` (tax reports)
   - `عقود` (contracts)
   - `إنذارات` (legal warnings / notices)
2. **`التوقيع والختم`:** in Profile & Settings the user draws or uploads a **signature** and uploads a **stamp** image; either can then be placed on any generated document before export/share.
3. **Expiry reminders (global):** every document, receipt, warranty and contract has `تاريخ الانتهاء` + a chosen reminder lead time. Expiring items surface in: the Smart Calendar, the module Follow-up Centers, and the notification bell.

**Acceptance**
- [ ] `إيصال أمانة` and `فاتورة` export as correct RTL PDFs
- [ ] Signature and stamp can be added to an exported document
- [ ] A document nearing expiry triggers a notification at the configured lead time

---

## PHASE 11 — Final QA pass

Go through this list and fix anything failing:

- [ ] Bottom nav = `الرئيسية` / `التقارير / الأرشيف` / `المحافظ` / `المزيد`
- [ ] Name, avatar and `المزيد` all open Profile & Settings
- [ ] Smart calendar reachable from Home + all four module headers, aggregating every due item
- [ ] Home layout toggle works, defaults to grid, persists
- [ ] Long-press pin works; pinned shortcuts render on Home
- [ ] General Summary computes real totals and can be shared
- [ ] `مركز المتابعة` is visually identical in all four modules; only its 3 metrics differ
- [ ] Every chip applies its own logic, not just a text filter
- [ ] Every main/sub category from Phases 6–9 exists and is correctly nested
- [ ] `+ إضافة أخرى` creates persistent custom categories everywhere
- [ ] Every form field appears, in the given order, split into main vs `معلومات إضافية`
- [ ] Every detail page has its exact tab set, summary rows, 3-dot menu, and add/request buttons
- [ ] Attachments, expiry dates and reminders all working
- [ ] Full RTL correctness, Arabic date/number formatting, zero hardcoded strings
- [ ] `flutter analyze` clean; no visual regression versus the original design

---

# SECTION C — REFERENCE SCREENSHOTS

The screenshots supplied with this spec (Home dashboard · Properties & Businesses list · General Summary sheet · People & Entities list · Personal Commitments list · Shared Commitments list) are the **visual baseline**. Every structural and field change described above is applied **inside** those existing layouts — same colors, same cards, same spacing.

---

# SECTION D — EXECUTED IMPLEMENTATION LOG (حتى آخر تعديل)

> هذا القسم يوثّق ما تم تنفيذه فعليًا داخل المشروع حتى آخر تعديل، وبنفس نمط التتبع المرحلي داخل الملف.

## D.1 آخر نقطة توقف (Current Stop Point)

- تم **ربط** قائمة الثلاث نقاط في صفحة **تفاصيل الالتزام المشترك** بمنطق فعلي:
  - `تعديل`
  - `مشاركة`
  - `حذف`
  - `أرشيف`
- لم تعد الثلاث نقاط تنقلك إلى تبويب `الملاحظات` (تم إصلاح السلوك الخاطئ).

## D.2 المنطق المطبق في الربط الأخير (Shared Details 3-dot)

1. `تعديل`
   - فتح نموذج تعديل داخل التفاصيل (اسم الالتزام، الميزانية، الملاحظات).
   - تحديث الكائن الحالي داخل صفحة التفاصيل مباشرة.
   - تمرير التحديث إلى القائمة الرئيسية عبر callback (`onUpdate`).

2. `مشاركة`
   - تفعيل مشاركة حقيقية عبر `share_plus`.
   - مشاركة ملخص الالتزام: الاسم، النوع، الميزانية، المتبقي، الحالة.

3. `حذف`
   - نافذة تأكيد حذف.
   - عند التأكيد: حذف الالتزام من القائمة الرئيسية عبر callback (`onDelete`) ثم إغلاق التفاصيل.

4. `أرشيف`
   - تحويل الحالة إلى `مؤرشف` وتحديث اللون و`lastUpdate`.
   - تمرير الحالة المحدثة للقائمة الرئيسية عبر `onUpdate`.

5. دعم النموذج
   - إضافة `copyWith` في نموذج `_SharedCommitment` لعمليات التعديل/الأرشفة.
   - جعل شاشة التفاصيل تعتمد على نسخة حالة داخلية (`_currentCommitment`) بدل القراءة الثابتة فقط.

## D.3 ما تم تنفيذه قبل ذلك (ملخص التعديلات المنجزة)

### D.3.1 المشاريع/العقارات والأنشطة
- تعديل تدفق `+ إضافة` في الشاشة الرئيسية للمشاريع ليعرض **أنواع الأنشطة أولًا** ثم نموذج التفاصيل.
- إزالة مسار إلغاء/نزع النشاط من تدفق الإضافة.
- معالجة Overflow في أوراق الإدخال عبر قيود ارتفاع + Scroll.

### D.3.2 شاشة القرعة
- إعادة بناء القرعة كعجلة دوران حقيقية مع اختيار عشوائي.
- إصلاح ظهور الأسماء داخل العجلة.
- تحسين الإحساس الواقعي: دورات أكثر + مدة دوران أطول.

### D.3.3 الصفحة الرئيسية والتنبيهات
- تحديث نص البحث إلى: `أبحث عن أي شيء`.
- إضافة تبويبات مركز التنبيهات:
  - `الكل`
  - `يحتاج انتباهك`
  - `التحديثات`
  - `النشاط`

### D.3.4 الالتزامات الشخصية (التفاصيل)
- إعادة تصميم تدفق `+ إضافة` إلى أقسام وخيارات فرعية.
- إضافة نماذج إدخال سريع وخيارات مرفقات.
- تحويل زر الإضافة في التفاصيل إلى زر عائم من نوع `AddFab`.
- توحيد ورقة اختيار النوع لتكون بنفس أسلوب الالتزام المشترك.

### D.3.5 الالتزامات المشتركة (التفاصيل)
- إضافة محدد تصنيف مالي بسهم للأسفل داخل تبويب `المالية`:
  - `مصروف`
  - `إيراد`
  - `ميزانية إضافية`
  - `تحويل مالي`
- ربط المحتوى المعروض في بطاقة `المالية` حسب التصنيف المختار.
- توحيد هيكل خيارات `+ إضافة` بالتسميات المطلوبة.

### D.3.6 توحيد الأربع صفحات (التفاصيل)
- توحيد سلوك زر الإضافة العائم وورقة اختيار النوع في:
  - تفاصيل الالتزام الشخصي
  - تفاصيل الالتزام المشترك
  - تفاصيل الأفراد/الجهات
  - تفاصيل العقار/النشاط
- اعتماد نمط ارتفاع موحّد لورقة اختيار النوع: `maxHeight = 0.86` من الشاشة.

## D.4 ملفات أساسية تم تعديلها ضمن هذه الدفعة

- `lib/screens/personal_commitments_screen.dart`
- `lib/screens/shared_commitments_screen.dart`
- `lib/screens/people_management_screen.dart`
- `lib/screens/projects_activities_screen.dart`
- `lib/screens/raffle_screen.dart`
- `lib/screens/notifications_center_screen.dart`
- `lib/l10n/home_strings.dart`
- `test/widget_test.dart`

## D.5 ملاحظات حالة الاختبارات (Known Status)

- تم تمرير عدة اختبارات مركزة أثناء التعديلات.
- ما زالت توجد اختبارات Widget شاملة تحتاج مواءمة إضافية مع تغييرات سلوك واجهات التفاصيل (خصوصًا بعد توحيد أزرار/أوراق الإضافة والسلوك التفاعلي).
- المنطق الأساسي للتعديلات الأخيرة يعمل، لكن يلزم **تنظيف نهائي لحزمة اختبارات الواجهة** لضمان توافق كامل.

## D.6 Checklist الحالة الحالية

- [x] إصلاح خطأ الثلاث نقاط في تفاصيل الالتزام المشترك
- [x] ربط خيارات الثلاث نقاط بمنطق فعلي (تعديل/مشاركة/حذف/أرشيف)
- [x] توحيد زر الإضافة العائم في صفحات التفاصيل الأربع
- [x] توحيد ارتفاع/نمط ورقة اختيار النوع في صفحات التفاصيل الأربع
- [x] تحديث التوثيق داخل هذا الملف حتى آخر نقطة تنفيذ
- [ ] تمرير كامل `flutter test test/widget_test.dart` بعد مواءمة كل الاختبارات القديمة

## D.7 السرد الزمني التفصيلي من لحظة ظهور خطأ shared حتى آخر تعديل

> هذا هو الشرح التفصيلي المطلوب من نقطة: *"كان التطبيق في آخر اختبار بدون أخطاء، لماذا يظهر خطأ في shared؟"* وحتى آخر تنفيذ.

### D.7.1 نقطة بداية المشكلة

1. كانت الحالة العامة تبدو مستقرة في اختبارات/تشغيلات سابقة.
2. عند بدء تعديلات جديدة داخل `shared details` بدأ يظهر سلوك غير متوقع:
   - الانتقال الخاطئ من زر الثلاث نقاط إلى تبويب `الملاحظات` بدل قائمة إجراءات.
   - فروقات بين توقعات الاختبارات القديمة وسلوك الواجهة الجديد.
3. السبب الجذري هنا لم يكن خطأ واحدًا؛ بل **تراكم تغييرات سلوكية** (UI + flow + keys + draggability) جعل اختبارات قديمة تفشل رغم أن أجزاء من المنطق الجديد تعمل.

### D.7.2 المرحلة الأولى بعد ظهور مشكلة shared

1. تم تعديل تبويب `المالية` داخل الالتزام المشترك بإضافة مصنف مالي Dropdown (مصروف/إيراد/ميزانية إضافية/تحويل مالي).
2. تم تعديل ورقة `+ إضافة` داخل الالتزام المشترك لتطابق الهيكل المطلوب بالتسميات العربية المحددة.
3. تم تحديث منطق التطبيع (Normalization) لاختيارات `إضافة ...` حتى تعود لنفس قوالب الإدخال الداخلية.
4. ظهرت فروقات اختبار متوقعة بسبب تغيّر العناوين/الهيكل في الورقة.

### D.7.3 المرحلة الثانية: توحيد تصميم الإضافة في الالتزام الشخصي

1. تم تحويل ورقة الإضافة في تفاصيل الالتزام الشخصي إلى نفس الأسلوب البصري المستخدم في المشترك (قسم + خيارات داخل نفس الورقة).
2. تم توحيد أسلوب الافتتاح بحيث يصبح Bottom Sheet موحّدًا في الإحساس البصري.
3. الاختبارات التي كانت تعتمد على تدفق خطوتين (قسم ثم خيارات) تأثرت، وتمت مواءمتها مع التدفق الجديد.

### D.7.4 المرحلة الثالثة: طلب جعل زر الشخصي عائم وارتفاع الورقة متساوي

1. تم استبدال زر الإضافة الثابت في تفاصيل الالتزام الشخصي إلى `AddFab` (زر عائم قابل للسحب).
2. تم جعل Bottom Sheet في الشخصي `isScrollControlled` ليتطابق مع المشترك.
3. بدأت تظهر فشل اختبارات من نوع hit-test بسبب:
   - الزر أصبح قابلًا للسحب وموقعه محفوظ (persisted).
   - الاختبار كان يفترض موضعًا ثابتًا في الشاشة.
4. تم تخفيف/تعديل التوقعات الهشة في الاختبار كي لا تفشل بسبب تغيير موضع الزر العائم بين الجلسات.

### D.7.5 المرحلة الرابعة: طلب توحيد الأربع أماكن

1. تم تطبيق التوحيد على أربع صفحات تفاصيل:
   - الشخصي
   - المشترك
   - الأفراد/الجهات
   - العقار/الأنشطة
2. التوحيد شمل:
   - زر إضافة عائم بنفس النمط.
   - ورقة اختيار نوع إضافة بارتفاع موحّد (`0.86`) ونفس shell البصري.
3. أثناء تعديل صفحة تفاصيل العقار حدث **حقن كود غير مقصود داخل منطقة Header** بسبب patch متداخل.
4. ظهر فشل تجميعي (compile errors) كبيرة في ملف العقار.
5. تم عزل الجزء التالف ثم إصلاحه يدويًا باسترجاع البنية الصحيحة للـ Header وإبقاء التوحيد المطلوب فقط.

### D.7.6 لماذا ظهر أن shared به خطأ رغم أن التطبيق كان “سليمًا” قبلها؟

السبب الفعلي كان مزيجًا من 3 عوامل:

1. **تغيير سلوك فعلي في shared details**
   - الثلاث نقاط كانت مرتبطة بتحويل تبويب بدل قائمة إجراءات، وهو سلوك غير مطابق للمطلوب.

2. **تغييرات متزامنة في أكثر من شاشة**
   - التوحيد عبر أربع صفحات غيّر سلوك الأزرار والأوراق، فبعض الاختبارات القديمة أصبحت لا تعبّر عن الواقع الجديد.

3. **اختبارات UI هشة**
   - وجود assertions تعتمد على إحداثيات ثابتة لعناصر أصبحت draggable.
   - وجود توقعات نصية قديمة بعد تبديل عناوين/تصنيفات.

### D.7.7 المرحلة الخامسة: إصلاح الثلاث نقاط في shared (الطلب المباشر)

1. تم استبدال سلوك الثلاث نقاط في تفاصيل الالتزام المشترك:
   - من: `setState(() => _selectedTab = notes)`
   - إلى: `PopupMenuButton` بخيارات واضحة.
2. في البداية نُفذت كـ placeholder actions (إشعارات + logs) للتأكد من السلوك البصري الصحيح أولًا.
3. بعد طلب "اربط" تم نقلها إلى ربط فعلي بمنطق بيانات.

### D.7.8 المرحلة السادسة: الربط الفعلي (طلب "اربط")

1. تم تمرير callbacks من قائمة الالتزامات المشتركة إلى شاشة التفاصيل:
   - `onUpdate(updated)`
   - `onDelete()`
2. تم اعتماد `_currentCommitment` داخل شاشة التفاصيل بدل القراءة المباشرة من widget input فقط.
3. تم تنفيذ:
   - `تعديل`: نموذج تعديل + حفظ + تحديث فوري داخل التفاصيل + انعكاس في القائمة.
   - `مشاركة`: Share حقيقي عبر `share_plus`.
   - `حذف`: تأكيد + حذف من القائمة + إغلاق التفاصيل.
   - `أرشيف`: تحديث حالة/لون/lastUpdate + انعكاس في القائمة.
4. تم إضافة `copyWith` لنموذج `_SharedCommitment` لدعم التعديل الجزئي النظيف.

### D.7.9 تأثير هذه السلسلة على الاختبارات

1. تم حل مشاكل compile/errors في الملفات المعدلة.
2. بقيت اختبارات شاملة في `widget_test.dart` تحتاج مواءمة نهائية مع السلوك الجديد (خصوصًا اختبارات تعتمد على:
   - نصوص قديمة.
   - مواضع ثابتة لعناصر أصبحت draggable.
   - تدفقات قديمة لورقات الإضافة).
3. المنطق المطبق في shared details نفسه أصبح مربوطًا فعليًا.

### D.7.10 الحالة الحالية الدقيقة (بعد آخر تعديل)

1. مشكلة الثلاث نقاط في shared تم إصلاحها وظيفيًا.
2. خيارات الثلاث نقاط مربوطة بمنطق بيانات حقيقي (وليست مجرد رسائل).
3. التوحيد البصري/السلوكي الأساسي للإضافة في صفحات التفاصيل الأربع مطبق.
4. المتبقي: تنظيف/مواءمة كامل اختبارات الواجهة الشاملة مع الحالة الجديدة للتطبيق.
