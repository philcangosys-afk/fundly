import { useMemo, useState } from "react";
import { NavLink, useParams } from "react-router-dom";
import { Table2 } from "lucide-react";
import DataTable from "@/components/admin/DataTable";
import RecordDrawer from "@/components/admin/RecordDrawer";
import Status from "@/components/admin/Status";
import Toolbar from "@/components/admin/Toolbar";
import { TABLES, TABLE_GROUPS, orderColumns, tableByKey } from "@/lib/schema";
import { useRows } from "@/lib/useRows";
import { formatAmount } from "@/lib/format";
import { sumColumn } from "@/lib/stats";

function toCsv(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return "";
  const keys = [...new Set(rows.flatMap((row) => Object.keys(row)))];
  const escape = (value: unknown) => {
    if (value === null || value === undefined) return "";
    const text = typeof value === "object" ? JSON.stringify(value) : String(value);
    return `"${text.replace(/"/g, '""')}"`;
  };
  return [keys.join(","), ...rows.map((row) => keys.map((key) => escape(row[key])).join(","))].join(
    "\n",
  );
}

/** فهرس الجداول حين لا يُختار جدول بعينه. */
function TableIndex() {
  return (
    <>
      <div className="mb-7">
        <div className="mb-2 flex items-center gap-2 text-xs font-bold text-brand">
          <Table2 className="h-4 w-4" />
          البيانات الخام
        </div>
        <h2 className="text-[26px] font-extrabold tracking-tight text-ink-title">الجداول</h2>
        <p className="mt-1.5 text-sm text-ink-body">
          كل جدول يكتب فيه التطبيق — اقرأه، ابحث فيه، صدّره، أو افتح أي سجل كاملًا.
        </p>
      </div>

      {TABLE_GROUPS.map((group) => (
        <section key={group} className="mb-6">
          <h3 className="mb-3 text-[11px] font-bold tracking-[.13em] text-ink-muted">{group}</h3>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {TABLES.filter((table) => table.group === group).map((table) => (
              <NavLink
                key={table.key}
                to={`/tables/${table.key}`}
                className="dashboard-card transition-shadow hover:shadow-[0_6px_18px_rgba(15,31,28,.07)]"
              >
                <h4 className="section-title">{table.label}</h4>
                <p className="section-subtitle leading-relaxed">{table.hint}</p>
                <p dir="ltr" className="mt-3 font-mono text-[10px] text-ink-muted">
                  {table.key}
                </p>
              </NavLink>
            ))}
          </div>
        </section>
      ))}
    </>
  );
}

export default function Tables() {
  const { table: tableKey } = useParams();
  if (!tableKey) return <TableIndex />;
  return <SingleTable tableKey={tableKey} />;
}

function SingleTable({ tableKey }: { tableKey: string }) {
  const definition = tableByKey(tableKey);
  const { rows, loading, error, reload } = useRows(tableKey, {
    orderBy: definition?.orderBy,
    limit: 1000,
  });

  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("الكل");
  const [selected, setSelected] = useState<Record<string, unknown> | null>(null);

  const columns = useMemo(() => orderColumns(definition, rows), [definition, rows]);

  const statusValues = useMemo(() => {
    if (!rows.some((row) => "status" in row)) return null;
    const values = new Set<string>();
    rows.forEach((row) => {
      const value = row.status;
      if (value !== null && value !== undefined && value !== "") values.add(String(value));
    });
    return ["الكل", ...[...values].sort()];
  }, [rows]);

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase();
    return rows.filter((row) => {
      if (statusValues && statusFilter !== "الكل" && String(row.status ?? "") !== statusFilter) {
        return false;
      }
      if (!term) return true;
      const fields = definition?.search ?? Object.keys(row);
      return fields.some((key) => String(row[key] ?? "").toLowerCase().includes(term));
    });
  }, [rows, query, statusFilter, statusValues, definition]);

  const amountColumn = definition?.amountColumn;
  const total = amountColumn ? sumColumn(filtered, amountColumn) : null;
  const amountLabel =
    definition?.columns.find((column) => column.key === amountColumn)?.label ?? "الإجمالي";

  const download = () => {
    const csv = toCsv(filtered);
    if (!csv) return;
    const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${tableKey}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  };

  return (
    <>
      <div className="mb-7 flex flex-wrap items-end justify-between gap-3">
        <div>
          <NavLink to="/tables" className="mb-2 inline-block text-xs font-bold text-brand">
            ← كل الجداول
          </NavLink>
          <h2 className="text-[26px] font-extrabold tracking-tight text-ink-title">
            {definition?.label ?? tableKey}
          </h2>
          <p className="mt-1.5 max-w-[640px] text-sm leading-relaxed text-ink-body">
            {definition?.hint}
          </p>
        </div>
        <div className="flex gap-2">
          <button type="button" onClick={reload} className="pill-button">
            تحديث
          </button>
          <button
            type="button"
            onClick={download}
            disabled={filtered.length === 0}
            className="primary-button"
          >
            تصدير CSV
          </button>
        </div>
      </div>

      <div className="mb-5 grid gap-4 sm:grid-cols-3">
        <div className="metric-card">
          <p className="text-[12px] font-medium text-ink-body">السجلات</p>
          <p className="mt-1 text-[24px] font-extrabold text-ink-title">{rows.length}</p>
        </div>
        <div className="metric-card">
          <p className="text-[12px] font-medium text-ink-body">المعروضة بعد الفلترة</p>
          <p className="mt-1 text-[24px] font-extrabold text-ink-title">{filtered.length}</p>
        </div>
        {total !== null && (
          <div className="metric-card">
            <p className="text-[12px] font-medium text-ink-body">{amountLabel}</p>
            <p className="mt-1 text-[24px] font-extrabold text-ink-title">{formatAmount(total)}</p>
          </div>
        )}
      </div>

      <section className="dashboard-card">
        <Toolbar
          query={query}
          onQuery={setQuery}
          filterLabel="الحالة"
          filterValue={statusFilter}
          filterOptions={statusValues ?? undefined}
          onFilter={statusValues ? setStatusFilter : undefined}
        />

        {loading ? (
          <Status state="loading" />
        ) : error ? (
          <Status state="error" message={error} onRetry={reload} />
        ) : filtered.length === 0 ? (
          <Status state="empty" message="لا توجد سجلات مطابقة" />
        ) : (
          <DataTable columns={columns} rows={filtered} onOpen={setSelected} />
        )}
      </section>

      <RecordDrawer
        table={tableKey}
        columns={columns}
        row={selected}
        onClose={() => setSelected(null)}
        onChanged={reload}
      />
    </>
  );
}
