// عميل الـ API للوحة الأدمن.
// قاعدة المسار: تُقرأ من NEXT_PUBLIC_API_URL إن ضُبطت (مفيد للتطوير وأي بيئة منفصلة).
// وإلا فالواجهة الأمامية والـ backend على نفس النطاق (voice.neojeen.com) عبر /api/v1.
const API_BASE = process.env.NEXT_PUBLIC_API_URL || "/api/v1";

function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("admin_token");
}

export function setToken(token: string) {
  localStorage.setItem("admin_token", token);
}

export function clearToken() {
  localStorage.removeItem("admin_token");
}

// فك ترميز payload الـ JWT لقراءة exp قبل الإرسال
type JwtPayload = { exp?: number };
function decodeJwtExp(token: string): number | null {
  try {
    const [, payload] = token.split(".");
    if (!payload) return null;
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const pad = normalized.length % 4 ? 4 - (normalized.length % 4) : 0;
    const data = JSON.parse(atob(normalized + "=".repeat(pad))) as JwtPayload;
    return typeof data.exp === "number" ? data.exp : null;
  } catch {
    return null;
  }
}

function redirectToLogin() {
  if (typeof window === "undefined") return;
  // استخدم replace لتفادي العودة بزر الـ back إلى صفحة محمية
  window.location.replace("/login");
}

export type ApiOptions = RequestInit & {
  // إشارة لإلغاء الطلب (AbortController.signal)
  signal?: AbortSignal;
};

export async function api<T>(
  path: string,
  options: ApiOptions = {}
): Promise<T> {
  const token = getToken();

  // فحص انتهاء صلاحية الـ token قبل الإرسال — لا تُرسل طلباً ميؤوساً منه
  if (token) {
    const exp = decodeJwtExp(token);
    if (exp !== null && exp * 1000 <= Date.now()) {
      clearToken();
      redirectToLogin();
      throw new Error("Token expired");
    }
  }

  const headers: Record<string, string> = {
    ...(options.headers as Record<string, string>),
  };

  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  if (!(options.body instanceof FormData)) {
    headers["Content-Type"] = "application/json";
  }

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
    signal: options.signal,
  });

  // 401 = غير مصادق — امسح الـ token وحوّل لتسجيل الدخول
  if (res.status === 401) {
    clearToken();
    redirectToLogin();
    throw new Error("Unauthorized");
  }

  // 403 = ممنوع — لا تحوّل، فقط ارمِ خطأً (المستخدم مسجّل دخوله لكن بلا صلاحية)
  if (res.status === 403) {
    const error = await res.json().catch(() => ({}));
    throw new Error(error.detail || "Forbidden");
  }

  if (!res.ok) {
    const error = await res.json().catch(() => ({}));
    throw new Error(error.detail || `Error ${res.status}`);
  }

  // 204 No Content — لا يوجد محتوى لتحليله
  if (res.status === 204) {
    return null as T;
  }

  return res.json() as Promise<T>;
}
