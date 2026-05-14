"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { setToken } from "@/lib/api";
import { isAdminTokenValid } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "/api/v1";

export default function LoginPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  // جلسة صالحة بالفعل — حوّل مباشرة للوحة التحكم بدلاً من إظهار نموذج الدخول
  useEffect(() => {
    if (isAdminTokenValid()) {
      router.replace("/dashboard");
    }
  }, [router]);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      const res = await fetch(`${API_BASE}/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(typeof data.detail === "string" ? data.detail : "فشل تسجيل الدخول");
        return;
      }
      setToken(data.access_token);
      router.replace("/dashboard");
    } catch (err) {
      // طباعة الخطأ فقط في بيئة التطوير
      if (process.env.NODE_ENV !== "production") {
        console.error("Login error:", err);
      }
      setError("فشل الاتصال بالسيرفر");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <Card className="w-full max-w-sm p-8">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-blue-600 mb-2">بصوتك</h1>
          <p className="text-gray-500 text-sm">لوحة التحكم</p>
        </div>
        <form onSubmit={handleLogin} className="space-y-4">
          <Input
            id="username"
            name="username"
            autoComplete="username"
            placeholder="اسم المستخدم"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
          <Input
            id="password"
            name="password"
            autoComplete="current-password"
            placeholder="كلمة السر"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          {error && <p className="text-red-500 text-sm">{error}</p>}
          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "جاري الدخول..." : "دخول"}
          </Button>
        </form>
      </Card>
    </div>
  );
}
