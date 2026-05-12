"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { clearToken } from "@/lib/api";

type JwtPayload = { sub?: string; username?: string; role?: string; exp?: number };

function decodeJwt(token: string): JwtPayload | null {
  try {
    const [, payload] = token.split(".");
    if (!payload) return null;
    const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
    const pad = normalized.length % 4 ? 4 - (normalized.length % 4) : 0;
    return JSON.parse(atob(normalized + "=".repeat(pad))) as JwtPayload;
  } catch {
    return null;
  }
}

// قراءة الـ token من localStorage بأمان (يعمل أيضاً على الـ SSR)
function readToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("admin_token");
}

// إرجاع payload الـ JWT الحالي إن وُجد وإلا null
export function getDecodedToken(): JwtPayload | null {
  const token = readToken();
  if (!token) return null;
  return decodeJwt(token);
}

// تحقق صحة الـ token: موجود + دور أدمن + لم تنتهِ صلاحيته
export function isAdminTokenValid(): boolean {
  const payload = getDecodedToken();
  if (!payload) return false;
  if (payload.role !== "admin") return false;
  if (typeof payload.exp !== "number") return false;
  return payload.exp * 1000 > Date.now();
}

// معرف الأدمن الحالي (null-safe)
export function getCurrentAdminId(): number | null {
  const payload = getDecodedToken();
  if (!payload || !payload.sub) return null;
  const n = Number(payload.sub);
  return Number.isFinite(n) ? n : null;
}

export function useAuth() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    if (isAdminTokenValid()) {
      setIsAuthenticated(true);
    } else {
      // الـ token غير موجود أو منتهي أو ليس أدمن — نظّف وحوِّل لصفحة الدخول
      clearToken();
      setIsAuthenticated(false);
      router.replace("/login");
    }
    setLoading(false);
  }, [router]);

  return { isAuthenticated, loading };
}
