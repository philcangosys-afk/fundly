import { useState } from "react";
import {
  Activity,
  ArrowDownLeft,
  ArrowUpLeft,
  BarChart3,
  Bell,
  BellRing,
  BookOpen,
  ChevronDown,
  CircleHelp,
  CreditCard,
  FileText,
  FolderOpen,
  LayoutDashboard,
  LifeBuoy,
  Menu,
  MoreHorizontal,
  Search,
  Settings2,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Users,
  X,
} from "lucide-react";

const navigation = [
  { label: "نبض المنتج", icon: LayoutDashboard },
  { label: "المستخدمون", icon: Users },
  { label: "الاشتراكات والفوترة", icon: CreditCard },
  { label: "محتوى النظام", icon: SlidersHorizontal },
  { label: "المستندات والتخزين", icon: FolderOpen },
  { label: "التنبيهات والرسائل", icon: BellRing },
  { label: "الدعم والبلاغات", icon: LifeBuoy },
  { label: "التقارير", icon: BarChart3 },
  { label: "الأمان وسجل التدقيق", icon: ShieldCheck },
];

const activityBars = [42, 54, 48, 68, 61, 75, 67, 80, 74, 91, 82, 96];
const modules = [
  { label: "الشخصية", value: 38, color: "bg-[#7067f0]" },
  { label: "المشتركة", value: 26, color: "bg-[#4cb8a5]" },
  { label: "العقارات", value: 16, color: "bg-[#f0b35b]" },
  { label: "الأنشطة", value: 11, color: "bg-[#e77c97]" },
  { label: "الآليات", value: 6, color: "bg-[#8b91a9]" },
  { label: "المحافظ", value: 3, color: "bg-[#d7d9e6]" },
];

function MetricCard({
  title,
  value,
  detail,
  positive = true,
  icon,
  iconClass,
}: {
  title: string;
  value: string;
  detail: string;
  positive?: boolean;
  icon: React.ReactNode;
  iconClass: string;
}) {
  return (
    <div className="metric-card">
      <div className="flex items-start justify-between gap-3">
        <div className={`metric-icon ${iconClass}`}>{icon}</div>
        <button className="text-[#a0a4b8] hover:text-[#64687d]" aria-label="المزيد">
          <MoreHorizontal className="h-5 w-5" />
        </button>
      </div>
      <p className="mt-4 text-[13px] font-medium text-[#777b91]">{title}</p>
      <div className="mt-1 flex items-end justify-between gap-2">
        <p className="text-[27px] font-extrabold tracking-tight text-[#24263b]">{value}</p>
        <span className={`flex items-center gap-1 text-xs font-bold ${positive ? "text-[#3ba58f]" : "text-[#e47485]"}`}>
          {positive ? <ArrowUpLeft className="h-3.5 w-3.5" /> : <ArrowDownLeft className="h-3.5 w-3.5" />}
          {detail}
        </span>
      </div>
      <p className="mt-1 text-[11px] text-[#a1a4b5]">مقارنة بالأسبوع الماضي</p>
    </div>
  );
}

export default function Index() {
  const [activeNav, setActiveNav] = useState("نبض المنتج");
  const [period, setPeriod] = useState("شهري");
  const [mobileNav, setMobileNav] = useState(false);

  return (
    <div dir="rtl" className="min-h-screen bg-[#f7f8fc] text-[#24263b]">
      <aside className={`fixed inset-y-0 right-0 z-40 flex w-[254px] flex-col border-l border-[#ececf3] bg-white px-4 py-6 transition-transform duration-300 lg:translate-x-0 ${mobileNav ? "translate-x-0" : "translate-x-full"}`}>
        <div className="mb-10 flex items-center justify-between px-3">
          <div className="flex items-center gap-3">
            <div className="brand-mark"><Sparkles className="h-5 w-5" /></div>
            <div><p className="text-[17px] font-extrabold leading-none text-[#282a40]">أثر</p><p className="mt-1 text-[10px] font-medium tracking-wide text-[#999caf]">لوحة التحكم</p></div>
          </div>
          <button onClick={() => setMobileNav(false)} className="text-[#9da1b5] lg:hidden" aria-label="إغلاق القائمة"><X className="h-5 w-5" /></button>
        </div>
        <p className="mb-3 px-3 text-[10px] font-bold tracking-[.13em] text-[#b0b2c0]">القائمة الرئيسية</p>
        <nav className="space-y-1">
          {navigation.slice(0, 7).map(({ label, icon: Icon }) => (
            <button key={label} onClick={() => setActiveNav(label)} className={`nav-item ${activeNav === label ? "nav-item-active" : ""}`}>
              <Icon className="h-[18px] w-[18px]" /><span>{label}</span>
              {label === "الدعم والبلاغات" && <span className="mr-auto rounded-full bg-[#fce4e8] px-2 py-0.5 text-[10px] font-bold text-[#d9687d]">12</span>}
            </button>
          ))}
        </nav>
        <p className="mb-3 mt-8 px-3 text-[10px] font-bold tracking-[.13em] text-[#b0b2c0]">الإدارة</p>
        <nav className="space-y-1">
          {navigation.slice(7).map(({ label, icon: Icon }) => <button key={label} onClick={() => setActiveNav(label)} className={`nav-item ${activeNav === label ? "nav-item-active" : ""}`}><Icon className="h-[18px] w-[18px]" /><span>{label}</span></button>)}
        </nav>
        <div className="mt-auto rounded-2xl bg-[#f4f3ff] p-4">
          <div className="mb-3 flex h-8 w-8 items-center justify-center rounded-lg bg-[#e4e1ff] text-[#7067f0]"><CircleHelp className="h-4 w-4" /></div>
          <p className="text-xs font-bold text-[#383952]">هل تحتاج إلى مساعدة؟</p><p className="mt-1 text-[11px] leading-5 text-[#85879c]">تواصل مع فريق الدعم لدينا</p>
          <button className="mt-3 text-[11px] font-bold text-[#7067f0]">مركز المساعدة ←</button>
        </div>
      </aside>

      <main className="min-h-screen lg:mr-[254px]">
        <header className="sticky top-0 z-30 flex h-[76px] items-center justify-between border-b border-[#ececf3] bg-[#f7f8fc]/90 px-5 backdrop-blur-md sm:px-8 lg:px-10">
          <div className="flex items-center gap-3"><button onClick={() => setMobileNav(true)} className="rounded-lg p-2 text-[#65697e] hover:bg-white lg:hidden" aria-label="فتح القائمة"><Menu className="h-5 w-5" /></button><div><p className="text-[11px] text-[#9b9eb0]">الاثنين، ٢٤ يونيو ٢٠٢٤</p><h1 className="mt-1 text-lg font-extrabold text-[#292b40] sm:text-xl">صباح الخير، أحمد <span className="mr-1">👋</span></h1></div></div>
          <div className="flex items-center gap-2 sm:gap-5"><button className="hidden h-10 w-56 items-center gap-2 rounded-xl border border-[#e7e8f0] bg-white px-3 text-right text-xs text-[#afb1bf] sm:flex"><Search className="h-4 w-4" />ابحث في لوحة التحكم</button><button className="relative rounded-xl p-2.5 text-[#73778c] hover:bg-white" aria-label="الإشعارات"><Bell className="h-[19px] w-[19px]" /><span className="absolute right-1.5 top-1.5 h-2 w-2 rounded-full border-2 border-[#f7f8fc] bg-[#e97d91]" /></button><div className="hidden h-8 w-px bg-[#e3e4eb] sm:block" /><button className="flex items-center gap-2"><div className="avatar">أ</div><span className="hidden text-xs font-bold text-[#45485d] sm:block">أحمد العتيبي</span><ChevronDown className="hidden h-3.5 w-3.5 text-[#aaaebe] sm:block" /></button></div>
        </header>

        <div className="px-5 py-7 sm:px-8 lg:px-10 lg:py-9">
          <div className="mb-7 flex flex-col justify-between gap-4 sm:flex-row sm:items-end"><div><div className="mb-2 flex items-center gap-2 text-xs font-bold text-[#7067f0]"><Activity className="h-4 w-4" />نظرة عامة</div><h2 className="text-[26px] font-extrabold tracking-tight text-[#292b40]">نبض المنتج</h2><p className="mt-1.5 text-sm text-[#85899e]">تابع أداء تطبيقك ونموه من مكان واحد.</p></div><div className="flex items-center gap-2"><button className="flex items-center gap-2 rounded-xl border border-[#e5e6ee] bg-white px-3.5 py-2.5 text-xs font-bold text-[#65697d]"><FileText className="h-4 w-4 text-[#888da2]" />تصدير التقرير</button><button className="flex items-center gap-2 rounded-xl bg-[#7067f0] px-3.5 py-2.5 text-xs font-bold text-white shadow-[0_5px_14px_rgba(112,103,240,.22)]"><Settings2 className="h-4 w-4" />إعدادات اللوحة</button></div></div>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard title="المستخدمون النشطون" value="24,892" detail="12.8%" icon={<Users className="h-[19px] w-[19px]" />} iconClass="bg-[#eae8ff] text-[#7067f0]" /><MetricCard title="تسجيلات جديدة" value="1,284" detail="8.4%" icon={<Sparkles className="h-[19px] w-[19px]" />} iconClass="bg-[#e2f6f1] text-[#43aa95]" /><MetricCard title="معدل الاحتفاظ" value="68.4%" detail="5.2%" icon={<Activity className="h-[19px] w-[19px]" />} iconClass="bg-[#fff1db] text-[#e9a846]" /><MetricCard title="الإيراد الشهري المتكرر" value="١٢٨,٤٠٠ ر.س" detail="3.7%" icon={<CreditCard className="h-[19px] w-[19px]" />} iconClass="bg-[#fce6eb] text-[#db7186]" /></div>

          <div className="mt-5 grid gap-5 xl:grid-cols-[1.45fr_1fr]">
            <section className="dashboard-card min-h-[350px]"><div className="mb-7 flex flex-wrap items-start justify-between gap-3"><div><h3 className="section-title">المستخدمون النشطون</h3><p className="section-subtitle">حركة المستخدمين خلال آخر ١٢ شهرًا</p></div><div className="flex rounded-lg bg-[#f5f5fa] p-1">{["يومي", "أسبوعي", "شهري"].map(item => <button key={item} onClick={() => setPeriod(item)} className={`rounded-md px-3 py-1.5 text-[11px] font-bold ${period === item ? "bg-white text-[#7067f0] shadow-sm" : "text-[#999caf]"}`}>{item}</button>)}</div></div><div className="mb-3 flex items-baseline gap-3"><span className="text-2xl font-extrabold">24,892</span><span className="text-xs font-bold text-[#3ca58f]">+12.8%</span></div><div className="relative h-[190px] w-full"><div className="chart-grid absolute inset-0" /><svg viewBox="0 0 700 190" preserveAspectRatio="none" className="absolute inset-0 h-full w-full overflow-visible"><defs><linearGradient id="area" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="#7067f0" stopOpacity=".2" /><stop offset="1" stopColor="#7067f0" stopOpacity="0" /></linearGradient></defs><path d="M0,153 C42,150 47,126 91,135 S132,122 171,129 S213,91 257,108 S299,75 342,90 S386,42 428,70 S471,51 513,65 S552,25 598,43 S649,27 700,20 L700,190 L0,190Z" fill="url(#area)" /><path d="M0,153 C42,150 47,126 91,135 S132,122 171,129 S213,91 257,108 S299,75 342,90 S386,42 428,70 S471,51 513,65 S552,25 598,43 S649,27 700,20" fill="none" stroke="#7067f0" strokeLinecap="round" strokeWidth="3" /></svg><div className="absolute bottom-[-24px] right-0 left-0 flex justify-between text-[10px] text-[#b1b3c1]"><span>يوليو</span><span>أغسطس</span><span>سبتمبر</span><span>أكتوبر</span><span>نوفمبر</span><span>ديسمبر</span></div></div></section>
            <section className="dashboard-card"><div className="mb-5 flex items-start justify-between"><div><h3 className="section-title">أكثر الوحدات استخدامًا</h3><p className="section-subtitle">توزيع الاستخدام حسب الوحدة</p></div><button className="text-[#a0a4b8]"><MoreHorizontal className="h-5 w-5" /></button></div><div className="flex items-center gap-6"><div className="donut-chart"><div className="donut-hole"><strong>100%</strong><span>الإجمالي</span></div></div><div className="flex-1 space-y-2.5">{modules.map(module => <div key={module.label} className="flex items-center justify-between text-xs"><span className="flex items-center gap-2 text-[#676b80]"><i className={`h-2 w-2 rounded-full ${module.color}`} />{module.label}</span><strong className="text-[#34374c]">{module.value}%</strong></div>)}</div></div></section>
          </div>

          <div className="mt-5 grid gap-5 xl:grid-cols-[1.15fr_1fr]">
            <section className="dashboard-card"><div className="mb-5 flex items-start justify-between"><div><h3 className="section-title">مؤشرات الصحة</h3><p className="section-subtitle">حالة الخدمات الأساسية الآن</p></div><span className="flex items-center gap-1.5 rounded-full bg-[#e4f7f1] px-2.5 py-1 text-[10px] font-bold text-[#36a48d]"><i className="h-1.5 w-1.5 rounded-full bg-[#40b397]" />كل الأنظمة تعمل</span></div><div className="grid gap-3 sm:grid-cols-3"><div className="health-item"><p>الطلبات الفاشلة</p><strong>0.24%</strong><span className="text-[#3ca58f]">أقل من الحد المسموح</span></div><div className="health-item"><p>متوسط زمن الاستجابة</p><strong>184ms</strong><span className="text-[#3ca58f]">ممتاز</span></div><div className="health-item"><p>حالة Supabase</p><strong className="flex items-center gap-1.5 text-[15px]"><i className="h-2 w-2 rounded-full bg-[#3ca58f]" />متصل</strong><span className="text-[#9c9faf]">آخر فحص منذ دقيقة</span></div></div></section>
            <section className="dashboard-card"><div className="mb-4 flex items-start justify-between"><div><h3 className="section-title">التسجيلات الجديدة</h3><p className="section-subtitle">مقارنة التسجيلات اليومية</p></div><button className="text-[#a0a4b8]"><MoreHorizontal className="h-5 w-5" /></button></div><div className="flex h-[118px] items-end gap-2 px-1">{activityBars.map((height, i) => <div key={i} className="group flex h-full flex-1 flex-col items-center justify-end gap-2"><div className={`w-full rounded-t-md transition-all ${i === 11 ? "bg-[#7067f0]" : "bg-[#e8e7ff] group-hover:bg-[#c8c5fb]"}`} style={{ height: `${height}%` }} /></div>)}</div><div className="mt-2 flex justify-between text-[10px] text-[#b1b3c1]"><span>١٢ يونيو</span><span>اليوم</span></div></section>
          </div>

          <div className="mt-6 flex flex-col items-center justify-between gap-3 border-t border-[#e7e8ef] pt-5 text-[11px] text-[#a3a6b7] sm:flex-row"><span>آخر تحديث منذ ٣ دقائق</span><span className="flex items-center gap-1.5"><BookOpen className="h-3.5 w-3.5" /> بيانات حية من بيئة الإنتاج</span></div>
        </div>
      </main>
    </div>
  );
}
