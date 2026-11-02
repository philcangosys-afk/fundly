// fundly-push — يرسل إشعار كل طلب جديد في fundly_inbox لأجهزة المستلم
// عبر Firebase Cloud Messaging (HTTP v1).
//
// الأسرار المطلوبة (Edge Functions ← Secrets):
//   FCM_SERVICE_ACCOUNT = محتوى ملف مفتاح حساب الخدمة من Firebase كاملًا
// SUPABASE_URL و SUPABASE_SERVICE_ROLE_KEY متوفران تلقائيًا.
//
// لا يُوثق بما يصل في الطلب: يُقرأ الطلب من الجدول بمعرّفه، ولا يُرسل إلا
// ما أُنشئ خلال آخر 10 دقائق.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

function serviceAccount(): ServiceAccount {
  return JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
}

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : new Uint8Array(data);
  let text = "";
  for (const b of bytes) text += String.fromCharCode(b);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cached: { token: string; until: number } | null = null;

// رمز دخول Google من مفتاح حساب الخدمة (صالح ساعة، يُعاد استعماله).
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.until > now + 60) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(signature)}`,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`oauth: ${JSON.stringify(json)}`);
  cached = { token: json.access_token, until: now + 3500 };
  return json.access_token;
}

const FIELDS = [
  "id",
  "sender_name",
  "sender_fnd",
  "source",
  "entry_type",
  "title",
  "action",
  "note",
  "record_id",
  "created_at",
];

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const id = body?.id ?? body?.record?.id;
    if (!id) return new Response("missing id", { status: 400 });

    const { data: row } = await supabase
      .from("fundly_inbox")
      .select("*")
      .eq("id", id)
      .maybeSingle();
    if (!row) return new Response("not found", { status: 404 });
    if (Date.now() - new Date(row.created_at).getTime() > 10 * 60 * 1000) {
      return new Response("too old");
    }

    const { data: tokens } = await supabase
      .from("fundly_push_tokens")
      .select("token")
      .eq("user_id", row.recipient_id);
    if (!tokens?.length) return new Response("no devices");

    const sa = serviceAccount();
    const access = await accessToken(sa);
    // رسالة بيانات فقط: التطبيق يكتب الإشعار بلغة المستخدم ولا يكرّره.
    const data: Record<string, string> = {};
    for (const field of FIELDS) data[field] = String(row[field] ?? "");

    let sent = 0;
    for (const { token } of tokens) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${access}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: { token, data, android: { priority: "HIGH" } },
          }),
        },
      );
      if (res.ok) {
        sent++;
        continue;
      }
      const text = await res.text();
      // جهاز حُذف منه التطبيق أو تغيّر رمزه: يُحذف رمزه.
      if (text.includes("UNREGISTERED") || text.includes("NOT_FOUND")) {
        await supabase.from("fundly_push_tokens").delete().eq("token", token);
      } else {
        console.error("fcm", res.status, text);
      }
    }
    return new Response(`sent ${sent}`);
  } catch (error) {
    console.error(error);
    return new Response("error", { status: 500 });
  }
});
