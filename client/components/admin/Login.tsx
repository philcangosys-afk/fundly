import { useState, type FormEvent } from "react";
import { supabase, readableError, configError, supabaseUrl } from "@/lib/supabase";

/**
 * الدخول بحساب Supabase حقيقي — لا مفتاح service_role في المتصفح، فالمفتاح
 * السرّي لا يوضع أبدًا في كود يصل إليه المستخدم.
 */
export default function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const result = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (result.error) setError(readableError(result.error));
  };

  return (
    <main dir="rtl" className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="w-full max-w-[380px]">
        <div className="mb-6 text-center">
          <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-brand text-[22px] font-black text-white">
            ف
          </div>
          <h1 className="text-[20px] font-black text-ink-title">لوحة تحكم فَندلي</h1>
          <p className="mt-1 text-[11.5px] font-semibold text-ink-muted">
            الدخول بحساب التطبيق نفسه
          </p>
        </div>

        <form onSubmit={submit} className="dashboard-card">
          {configError && (
            <p className="mb-4 rounded-xl bg-[#FBE7E4] px-3 py-2 text-[11.5px] font-extrabold leading-relaxed text-[#C4392E]">
              {configError}
            </p>
          )}

          <label className="mb-3 block">
            <span className="mb-1.5 block text-[11.5px] font-bold text-ink-muted">
              البريد الإلكتروني
            </span>
            <input
              type="email"
              dir="ltr"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="field text-left"
            />
          </label>

          <label className="mb-4 block">
            <span className="mb-1.5 block text-[11.5px] font-bold text-ink-muted">
              كلمة المرور
            </span>
            <input
              type="password"
              dir="ltr"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="field text-left"
            />
          </label>

          {error && (
            <p className="mb-3 rounded-xl bg-[#FBE7E4] px-3 py-2 text-[11.5px] font-extrabold text-[#C4392E]">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-xl bg-brand-deep px-4 py-3 text-[13px] font-black text-white transition-colors hover:bg-brand-dark disabled:opacity-60"
          >
            {busy ? "جارٍ الدخول…" : "دخول"}
          </button>

          <p dir="ltr" className="mt-4 text-center font-mono text-[10px] leading-relaxed text-ink-muted">
            {supabaseUrl.replace("https://", "")}
          </p>
        </form>
      </div>
    </main>
  );
}
