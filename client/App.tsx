import "./global.css";

import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import Shell from "@/components/admin/Shell";
import Login from "@/components/admin/Login";
import Index from "./pages/Index";
import Tables from "./pages/Tables";
import Delegations from "./pages/Delegations";
import Documents from "./pages/Documents";
import Health from "./pages/Health";
import Settings from "./pages/Settings";
import NotFound from "./pages/NotFound";

/**
 * بوابة الدخول: لا شيء يُعرض قبل التحقق من الجلسة، فلا تومض اللوحة
 * لحظة ثم تُستبدل بشاشة الدخول.
 */
function Gate() {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data } = supabase.auth.onAuthStateChange((_event, next) =>
      setSession(next),
    );
    return () => data.subscription.unsubscribe();
  }, []);

  if (!ready) {
    return (
      <div
        dir="rtl"
        className="flex min-h-screen items-center justify-center text-[13px] font-bold text-ink-muted"
      >
        جارٍ التحقق من الجلسة…
      </div>
    );
  }

  if (!session) return <Login />;

  return (
    <Shell user={session.user}>
      <Routes>
        <Route path="/" element={<Index />} />
        <Route path="/tables" element={<Tables />} />
        <Route path="/tables/:table" element={<Tables />} />
        <Route path="/delegations" element={<Delegations />} />
        <Route path="/documents" element={<Documents />} />
        <Route path="/health" element={<Health />} />
        <Route path="/settings" element={<Settings />} />
        <Route path="/404" element={<NotFound />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Shell>
  );
}

const App = () => (
  <BrowserRouter>
    <Gate />
  </BrowserRouter>
);

createRoot(document.getElementById("root")!).render(<App />);
