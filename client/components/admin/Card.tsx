import type { ReactNode } from "react";

interface CardProps {
  title?: string;
  hint?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}

/** بطاقة القالب نفسها (dashboard-card) مع رأس اختياري. */
export default function Card({ title, hint, action, children, className = "" }: CardProps) {
  return (
    <section className={`dashboard-card ${className}`}>
      {(title || action) && (
        <header className="mb-4 flex items-start gap-3">
          <div className="min-w-0 flex-1">
            {title && <h3 className="section-title">{title}</h3>}
            {hint && <p className="section-subtitle leading-relaxed">{hint}</p>}
          </div>
          {action}
        </header>
      )}
      {children}
    </section>
  );
}
