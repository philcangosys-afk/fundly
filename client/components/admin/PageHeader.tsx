import type { ReactNode } from "react";

interface PageHeaderProps {
  title: string;
  hint?: string;
  right?: ReactNode;
}

export default function PageHeader({ title, hint, right }: PageHeaderProps) {
  return (
    <header className="mb-7 flex flex-wrap items-start gap-3">
      <div className="min-w-0 flex-1">
        <h2 className="text-[26px] font-extrabold tracking-tight text-ink-title">{title}</h2>
        {hint && (
          <p className="mt-1.5 max-w-[680px] text-sm leading-relaxed text-ink-body">{hint}</p>
        )}
      </div>
      {right}
    </header>
  );
}
