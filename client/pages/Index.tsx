import { useEffect, useMemo, useState } from "react";
import { NavLink } from "react-router-dom";
import {
  Activity,
  CreditCard,
  Database,
  FolderOpen,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import MetricCard from "@/components/admin/MetricCard";
import Status from "@/components/admin/Status";
import TrendChart from "@/components/admin/charts/TrendChart";
import BarList from "@/components/admin/charts/BarList";
import { TABLES } from "@/lib/schema";
import { countRows, useRows } from "@/lib/useRows";
import { groupCount, monthlySeries, sumColumn } from "@/lib/stats";
import { daysUntil, formatAmount, formatDate, relativeTime } from "@/lib/format";

/**
 * «نبض المنتج» — نفس تخطيط التصميم، لكن كل رقم فيه مقروء من Supabase.
 * كانت القيم ثابتة في الكود (24,892 مستخدمًا، 68.4% احتفاظ…) وهي أرقام لا
 * وجود لها في قاعدة البيانات أصلًا.
 */
export default function Index() {
  const [counts, setCounts] = useState<Record<string, number | null>>({});
  const [countsLoading, setCountsLoading] = useState(true);

  const personal = useRows("personal_entries", { orderBy: "created_at", limit: 1000 });
  const shared = useRows("shared_entries", { orderBy: "created_at", limit: 1000 });
  const delegations = useRows("delegations", { orderBy: "created_at", limit: 500 });
  const payments = useRows("property_unit_payments", { orderBy: "due_date", limit: 1000 });
  const wallets = useRows("wallets", { limit: 200 });

  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      const entries = await Promise.all(
        TABLES.map(async (table) => [table.key, await countRows(table.key)] as const),
      );
      if (cancelled) return;
      setCounts(Object.fromEntries(entries));
      setCountsLoading(false);
    };
    void run();
    return () => {
      cancelled = true;
    };
  }, []);

  const allEntries = useMemo(
    () => [...personal.rows, ...shared.rows],
    [personal.rows, shared.rows],
  );

  const trend = useMemo(() => monthlySeries(allEntries, "created_at", 12), [allEntries]);

  const byTable = useMemo(
    () =>
      TABLES.map((table) => ({ label: table.label, value: counts[table.key] ?? 0 }))
        .filter((row) => row.value > 0)
        .sort((a, b) => b.value - a.value),
    [counts],
  );

  const sharedTypes = useMemo(() => groupCount(shared.rows, "entry_type"), [shared.rows]);

  const totalRecords = useMemo(
    () => Object.values(counts).reduce((total, value) => total + (value ?? 0), 0),
    [counts],
  );

  const delegationAlerts = useMemo(
    () =>
      delegations.rows
        .map((row) => ({ row, days: daysUntil(row.end_date) }))
        .filter((item) => item.days !== null && item.days <= 30 && !item.row.is_paused)
        .sort((a, b) => (a.days ?? 0) - (b.days ?? 0))
        .slice(0, 6),
    [delegations.rows],
  );

  const latePayments = useMemo(
    () =>
      payments.rows
        .map((row) => ({ row, days: daysUntil(row.due_date) }))
        .filter(
          (item) =>
            item.days !== null &&
            item.days < 0 &&
            Number(item.row.amount_paid ?? 0) < Number(item.row.amount_due ?? 0),
        )
        .sort((a, b) => (a.days ?? 0) - (b.days ?? 0))
        .slice(0, 6),
    [payments.rows],
  );

  const recent = useMemo(
    () =>
      [...allEntries]
        .sort(
          (a, b) =>
            new Date(String(b.created_at ?? 0)).getTime() -
            new Date(String(a.created_at ?? 0)).getTime(),
        )
        .slice(0, 7),
    [allEntries],
  );

  const monthAdds = trend[trend.length - 1]?.value ?? 0;
  const personalTotal = useMemo(() => sumColumn(personal.rows, "amount"), [personal.rows]);
  const sharedTotal = useMemo(() => sumColumn(shared.rows, "amount"), [shared.rows]);

  const connectionError = personal.error ?? shared.error;

  return (
    <>
      <div className="mb-7">
        <div className="mb-2 flex items-center gap-2 text-xs font-bold text-brand">
          <Activity className="h-4 w-4" />
          لوحة فَندلي
        </div>
        <h2 className="text-[26px] font-extrabold tracking-tight text-ink-title">
          نظرة عامة
        </h2>
        <p className="mt-1.5 text-sm text-ink-body">
          كل ما في قاعدة بيانات فَندلي: حجمه، نموّه، وما يحتاج تدخّلًا الآن.
        </p>
      </div>

      {connectionError && (
        <div className="mb-5">
          <Status state="error" message={connectionError} onRetry={personal.reload} />
        </div>
      )}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard
          title="إجمالي السجلات"
          value={totalRecords}
          detail={`عبر ${TABLES.length} جدولًا`}
          loading={countsLoading}
          icon={<Database className="h-[19px] w-[19px]" />}
          iconClass="bg-brand-soft text-brand"
        />
        <MetricCard
          title="أُضيف هذا الشهر"
          value={monthAdds}
          detail="التزامات شخصية ومشتركة"
          loading={personal.loading || shared.loading}
          icon={<Sparkles className="h-[19px] w-[19px]" />}
          iconClass="bg-[#E2F6F1] text-[#2F8D79]"
        />
        <MetricCard
          title="تفويضات تحتاج متابعة"
          value={delegationAlerts.length}
          detail="تنتهي خلال 30 يومًا أو انتهت"
          loading={delegations.loading}
          icon={<ShieldCheck className="h-[19px] w-[19px]" />}
          iconClass="bg-gold-soft text-gold-dark"
        />
        <MetricCard
          title="قيمة الالتزامات"
          value={formatAmount(personalTotal + sharedTotal)}
          detail={`شخصية ${formatAmount(personalTotal)} · مشتركة ${formatAmount(sharedTotal)}`}
          loading={personal.loading || shared.loading}
          icon={<CreditCard className="h-[19px] w-[19px]" />}
          iconClass="bg-[#FBE7E4] text-[#C4392E]"
        />
      </div>

      <div className="mt-5 grid gap-5 xl:grid-cols-[1.45fr_1fr]">
        <section className="dashboard-card">
          <div className="mb-6">
            <h3 className="section-title">السجلات المُنشأة شهريًا</h3>
            <p className="section-subtitle">
              الالتزامات الشخصية والمشتركة معًا، آخر اثني عشر شهرًا
            </p>
          </div>
          {personal.loading || shared.loading ? (
            <Status state="loading" />
          ) : allEntries.length === 0 ? (
            <Status state="empty" message="لا توجد سجلات بتاريخ إنشاء بعد" />
          ) : (
            <TrendChart data={trend} measure="سجل" height={210} />
          )}
        </section>

        <section className="dashboard-card">
          <div className="mb-5">
            <h3 className="section-title">أكثر الوحدات استخدامًا</h3>
            <p className="section-subtitle">عدد السجلات في كل جدول</p>
          </div>
          {countsLoading ? <Status state="loading" /> : <BarList data={byTable} limit={7} />}
        </section>
      </div>

      <div className="mt-5 grid gap-5 xl:grid-cols-[1.15fr_1fr]">
        <section className="dashboard-card">
          <div className="mb-5 flex items-start justify-between gap-3">
            <div>
              <h3 className="section-title">مؤشرات الصحة</h3>
              <p className="section-subtitle">حالة الاتصال وحجم البيانات الآن</p>
            </div>
            <span
              className={`flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-bold ${
                connectionError ? "bg-[#FBE7E4] text-[#C4392E]" : "bg-brand-soft text-brand"
              }`}
            >
              <i
                className={`h-1.5 w-1.5 rounded-full ${
                  connectionError ? "bg-[#C4392E]" : "bg-brand-mid"
                }`}
              />
              {connectionError ? "تعذّر الاتصال" : "متصل بـ Supabase"}
            </span>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="health-item">
              <p>الجداول المقروءة</p>
              <strong>
                {Object.values(counts).filter((value) => value !== null).length} /{" "}
                {TABLES.length}
              </strong>
              <span className="text-ink-muted">الباقي محجوب أو غير موجود</span>
            </div>
            <div className="health-item">
              <p>المحافظ المسجّلة</p>
              <strong>{wallets.rows.length}</strong>
              <span className="text-ink-muted">
                {wallets.error ? "تعذّرت القراءة" : "قُرئت بنجاح"}
              </span>
            </div>
            <div className="health-item">
              <p>دفعات متأخرة</p>
              <strong>{latePayments.length}</strong>
              <span className={latePayments.length ? "text-[#C4392E]" : "text-brand"}>
                {latePayments.length ? "تحتاج تحصيلًا" : "لا شيء متأخر"}
              </span>
            </div>
          </div>
        </section>

        <section className="dashboard-card">
          <div className="mb-4">
            <h3 className="section-title">أنواع الالتزامات المشتركة</h3>
            <p className="section-subtitle">أي نوع يُستعمل فعلًا</p>
          </div>
          {shared.loading ? <Status state="loading" /> : <BarList data={sharedTypes} limit={5} />}
        </section>
      </div>

      <div className="mt-5 grid gap-5 xl:grid-cols-3">
        <section className="dashboard-card">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div>
              <h3 className="section-title">تفويضات تحتاج متابعة</h3>
              <p className="section-subtitle">قاربت الانتهاء أو انتهت</p>
            </div>
            <NavLink to="/delegations" className="pill-button shrink-0">
              الكل
            </NavLink>
          </div>
          {delegations.loading ? (
            <Status state="loading" />
          ) : delegationAlerts.length === 0 ? (
            <Status state="empty" message="لا يوجد تفويض يقارب الانتهاء" />
          ) : (
            <ul className="divide-y divide-hairline">
              {delegationAlerts.map((item, index) => (
                <li key={String(item.row.id ?? index)} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12.5px] font-extrabold text-ink-title">
                      {String(item.row.delegate_name ?? "—")}
                    </p>
                    <p className="mt-0.5 truncate text-[10.5px] font-bold text-ink-muted">
                      {String(item.row.scope ?? "—")}
                    </p>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-1 text-[10.5px] font-black ${
                      (item.days ?? 0) < 0
                        ? "bg-[#FBE7E4] text-[#C4392E]"
                        : "bg-gold-soft text-gold-dark"
                    }`}
                  >
                    {(item.days ?? 0) < 0 ? "منتهٍ" : `${item.days} يوم`}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="dashboard-card">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div>
              <h3 className="section-title">دفعات إيجار متأخرة</h3>
              <p className="section-subtitle">استحقّت ولم يكتمل سدادها</p>
            </div>
            <NavLink to="/tables/property_unit_payments" className="pill-button shrink-0">
              الكل
            </NavLink>
          </div>
          {payments.loading ? (
            <Status state="loading" />
          ) : latePayments.length === 0 ? (
            <Status state="empty" message="لا توجد دفعات متأخرة" />
          ) : (
            <ul className="divide-y divide-hairline">
              {latePayments.map((item, index) => (
                <li key={String(item.row.id ?? index)} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="text-[12.5px] font-extrabold text-ink-title">
                      {formatAmount(item.row.amount_due)}
                    </p>
                    <p className="mt-0.5 text-[10.5px] font-bold text-ink-muted">
                      استحقّت {formatDate(item.row.due_date)}
                    </p>
                  </div>
                  <span className="shrink-0 rounded-full bg-[#FBE7E4] px-2.5 py-1 text-[10.5px] font-black text-[#C4392E]">
                    {Math.abs(item.days ?? 0)} يوم
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="dashboard-card">
          <div className="mb-4 flex items-start justify-between gap-3">
            <div>
              <h3 className="section-title">أحدث ما أُضيف</h3>
              <p className="section-subtitle">من التطبيق مباشرة</p>
            </div>
            <NavLink to="/tables" className="pill-button shrink-0">
              الجداول
            </NavLink>
          </div>
          {recent.length === 0 ? (
            <Status state="empty" />
          ) : (
            <ul className="divide-y divide-hairline">
              {recent.map((row, index) => (
                <li key={String(row.id ?? index)} className="flex gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12.5px] font-extrabold text-ink-title">
                      {String(row.title ?? "بلا عنوان")}
                    </p>
                    <p className="mt-0.5 truncate text-[10.5px] font-bold text-ink-muted">
                      {String(row.entry_type ?? "—")}
                    </p>
                  </div>
                  <span className="shrink-0 text-[10.5px] font-bold text-ink-muted">
                    {relativeTime(row.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      <p className="mt-6 flex items-center gap-2 text-[11.5px] font-semibold text-ink-muted">
        <FolderOpen className="h-4 w-4 shrink-0" />
        الأفراد والجهات والتنبيهات محفوظة على جهاز المستخدم لا في Supabase، فلا
        تظهر هنا.
      </p>
    </>
  );
}
