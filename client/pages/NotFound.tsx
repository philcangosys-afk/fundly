import { NavLink } from "react-router-dom";

export default function NotFound() {
  return (
    <div dir="rtl" className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="text-center">
        <p className="text-[52px] font-black leading-none text-brand">404</p>
        <p className="mt-3 text-[14px] font-bold text-ink-title">
          لا توجد صفحة بهذا العنوان
        </p>
        <NavLink to="/" className="primary-button mt-5 inline-block">
          العودة إلى اللوحة
        </NavLink>
      </div>
    </div>
  );
}
