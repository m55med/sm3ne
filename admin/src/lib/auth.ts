"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

type JwtPayload = { sub: string; username?: string; role?: string; exp?: number };

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

export function getCurrentAdminId(): number | null {
  if (typeof window === "undefined") return null;
  const token = localStorage.getItem("admin_token");
  if (!token) return null;
  const payload = decodeJwt(token);
  if (!payload?.sub) return null;
  const n = Number(payload.sub);
  return Number.isFinite(n) ? n : null;
}

export function useAuth() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("admin_token");
    if (!token) {
      router.push("/login");
    } else {
      setIsAuthenticated(true);
    }
    setLoading(false);
  }, [router]);

  return { isAuthenticated, loading };
}
