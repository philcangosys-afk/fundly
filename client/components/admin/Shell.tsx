import { useState, type ReactNode } from "react";
import { NavLink, useLocation } from "react-router-dom";
import type { User } from "@supabase/supabase-js";
import {
  BarChart3,
  Bell,
  BellRing,
  ChevronDown,
  CreditCard,
  FolderOpen,
  LayoutDashboard,
  LifeBuoy,
  Menu,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Table2,
  Users,
  X,
} from "lucide-react";
import { supabase } from "@/lib/supabase";

/**
 * نفس هيكل اللوحة الذي وُلِّد في التصميم: قائمة جانبية على اليمين وشريط
 * علوي — لكن بروابط حقيقية بدل أزرار لا تنقل إلى شيء، وبهوية فَندلي.
 */
const mainNav = [
  { to: "/", label: "نظرة عامة", icon: LayoutDashboard, end: true },
  { to: "/delegations", label: "التفويضات", icon: ShieldCheck },
  { to: "/documents", label: "المستندات والتخزين", icon: FolderOpen },
  { to: "/tables", label: "الجداول", icon: Table2 },
  { to: "/health", label: "سلامة البيانات", icon: BarChart3 },
];

const soonNav = [
  { label: "المستخدمون", icon: Users },
  { label: "الاشتراكات والفوترة", icon: CreditCard },
  { label: "محتوى النظام", icon: SlidersHorizontal },
  { label: "التنبيهات والرسائل", icon: BellRing },
  { label: "الدعم والبلاغات", icon: LifeBuoy },
];

const todayLabel = () => {
  const date = new Date();
  const days = [
    "الأحد",
    "الاثنين",
    "الثلاثاء",
    "الأربعاء",
    "الخميس",
    "الجمعة",
    "السبت",
  ];
  const months = [
    "يناير",
    "فبراير",
    "مارس",
    "أبريل",
    "مايو",
    "يونيو",
    "يوليو",
    "أغسطس",
    "سبتمبر",
    "أكتوبر",
    "نوفمبر",
    "ديسمبر",
  ];
  return `${days[date.getDay()]}، ${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()}`;
};

interface ShellProps {
  user: User;
  children: ReactNode;
}

export default function Shell({ user, children }: ShellProps) {
  const [mobileNav, setMobileNav] = useState(false);
  const location = useLocation();
  const active =
    mainNav.find((item) =>
      item.end ? location.pathname === "/" : location.pathname.startsWith(item.to),
    )?.label ?? "لوحة التحكم";

  return (
    <div dir="rtl" className="min-h-screen bg-background text-ink-title">
      {mobileNav && (
        <button
          type="button"
          aria-label="إغلاق القائمة"
          onClick={() => setMobileNav(false)}
          className="fixed inset-0 z-30 bg-ink-title/25 lg:hidden"
        />
      )}

      <aside
        className={`fixed inset-y-0 right-0 z-40 flex w-[254px] flex-col overflow-y-auto border-l border-hairline bg-white px-4 py-6 transition-transform duration-300 lg:translate-x-0 ${
          mobileNav ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <div className="mb-8 flex items-center justify-between px-3">
          <div className="flex items-center gap-3">
            <div className="brand-mark text-[17px] font-black">ف</div>
            <div>
              <p className="text-[17px] font-extrabold leading-none text-ink-title">
                فَندلي
              </p>
              <p className="mt-1 text-[10px] font-medium tracking-wide text-ink-muted">
                لوحة التحكم
              </p>
            </div>
          </div>
          <button
            onClick={() => setMobileNav(false)}
            className="text-ink-muted lg:hidden"
            aria-label="إغلاق القائمة"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <p className="nav-group-title">القائمة الرئيسية</p>
        <nav className="space-y-1">
          {mainNav.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              onClick={() => setMobileNav(false)}
              className={({ isActive }) =>
                `nav-item ${isActive ? "nav-item-active" : ""}`
              }
            >
              <Icon className="h-[18px] w-[18px]" />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>

        <p className="nav-group-title mt-8">بانتظار فصل الحسابات</p>
        <nav className="space-y-1">
          {soonNav.map(({ label, icon: Icon }) => (
            <button
              key={label}
              type="button"
              disabled
              title="يحتاج حسابًا لكل مستخدم أولًا"
              className="nav-item nav-item-disabled"
            >
              <Icon className="h-[18px] w-[18px]" />
              <span>{label}</span>
            </button>
          ))}
        </nav>

        <div className="mt-auto rounded-2xl bg-brand-soft p-4">
          <p className="text-xs font-bold text-ink-title">لماذا الأقسام معطّلة؟</p>
          <p className="mt-1 text-[11px] leading-5 text-ink-body">
            التطبيق يدخل بحساب واحد مشترك، فلا يوجد «مستخدمون» بعد. راجع صفحة
            الإعدادات.
          </p>
          <NavLink
            to="/settings"
            onClick={() => setMobileNav(false)}
            className="mt-3 inline-block text-[11px] font-bold text-brand"
          >
            الإعدادات ←
          </NavLink>
        </div>
      </aside>

      <main className="min-h-screen lg:mr-[254px]">
        <header className="sticky top-0 z-20 flex h-[76px] items-center justify-between border-b border-hairline bg-background/90 px-5 backdrop-blur-md sm:px-8 lg:px-10">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setMobileNav(true)}
              className="rounded-lg p-2 text-ink-body hover:bg-white lg:hidden"
              aria-label="فتح القائمة"
            >
              <Menu className="h-5 w-5" />
            </button>
            <div>
              <p className="text-[11px] text-ink-muted">{todayLabel()}</p>
              <h1 className="mt-1 text-lg font-extrabold text-ink-title sm:text-xl">
                {active}
              </h1>
            </div>
          </div>

          <div className="flex items-center gap-2 sm:gap-4">
            <NavLink
              to="/tables"
              className="hidden h-10 items-center gap-2 rounded-xl border border-hairline bg-white px-3 text-right text-xs text-ink-muted sm:flex"
            >
              <Search className="h-4 w-4" />
              ابحث في الجداول
            </NavLink>
            <NavLink
              to="/health"
              className="relative rounded-xl p-2.5 text-ink-body hover:bg-white"
              aria-label="سلامة البيانات"
            >
              <Bell className="h-[19px] w-[19px]" />
            </NavLink>
            <div className="hidden h-8 w-px bg-hairline sm:block" />
            <div className="flex items-center gap-2">
              <div className="avatar">{(user.email ?? "؟").slice(0, 1)}</div>
              <span
                dir="ltr"
                className="hidden max-w-[170px] truncate text-xs font-bold text-ink-body sm:block"
              >
                {user.email}
              </span>
              <button
                type="button"
                onClick={() => void supabase.auth.signOut()}
                className="pill-button"
              >
                خروج
              </button>
              <ChevronDown className="hidden h-3.5 w-3.5 text-ink-muted sm:block" />
            </div>
          </div>
        </header>

        <div className="px-5 py-7 sm:px-8 lg:px-10 lg:py-9">{children}</div>
      </main>
    </div>
  );
}
