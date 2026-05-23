"use client";
import Link from "next/link";
import { useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { clearToken } from "@/lib/api";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { ThemeToggle } from "@/components/theme-toggle";
import { Toaster } from "@/components/toaster";

const navItems = [
  { href: "/dashboard", label: "الإحصائيات", icon: "📊" },
  { href: "/users", label: "المستخدمين", icon: "👥" },
  { href: "/analyze", label: "تحليل صوتي", icon: "🎤" },
  { href: "/telegram", label: "تيليجرام", icon: "💬" },
  { href: "/requests", label: "الطلبات", icon: "📋" },
  { href: "/tickets", label: "الرسائل", icon: "📨" },
  { href: "/devices", label: "الأجهزة والإشعارات", icon: "📱" },
  { href: "/subscriptions", label: "الاشتراكات", icon: "📜" },
  { href: "/coupons", label: "الكوبونات", icon: "🎟️" },
  { href: "/plans", label: "الباقات", icon: "💎" },
  { href: "/settings", label: "الإعدادات", icon: "⚙️" },
];

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { isAuthenticated, loading } = useAuth();
  const [logoutOpen, setLogoutOpen] = useState(false);

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center"><div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full" /></div>;
  }

  if (!isAuthenticated) return null;

  function doLogout() {
    clearToken();
    router.replace("/login");
  }

  return (
    <div className="min-h-screen flex bg-background text-foreground">
      {/* الشريط الجانبي — استخدمنا border-s (logical) بدلاً من border-l لدعم RTL */}
      <aside className="w-64 bg-card border-s border-border shadow-sm hidden md:flex flex-col">
        <div className="p-6 border-b border-border flex items-center justify-between gap-2">
          <div>
            <Link href="/" className="text-2xl font-bold text-blue-600 dark:text-blue-400">بصوتك</Link>
            <p className="text-xs text-muted-foreground mt-1">لوحة التحكم</p>
          </div>
          <ThemeToggle />
        </div>
        <nav className="flex-1 p-4 space-y-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg text-sm transition ${
                pathname === item.href || pathname.startsWith(item.href + "/")
                  ? "bg-blue-50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 font-semibold"
                  : "text-muted-foreground hover:bg-muted hover:text-foreground"
              }`}
            >
              <span>{item.icon}</span>
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="p-4 border-t border-border">
          <button
            onClick={() => setLogoutOpen(true)}
            className="flex items-center gap-3 px-4 py-3 rounded-lg text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-950/40 w-full transition"
          >
            <span>🚪</span>
            تسجيل الخروج
          </button>
        </div>
      </aside>

      {/* المحتوى الرئيسي */}
      <main className="flex-1 p-6 overflow-auto">{children}</main>

      {/* تأكيد تسجيل الخروج */}
      <ConfirmDialog
        open={logoutOpen}
        onOpenChange={setLogoutOpen}
        title="تسجيل الخروج؟"
        description="هل تريد فعلاً تسجيل الخروج من لوحة التحكم؟"
        confirmLabel="تسجيل الخروج"
        destructive
        onConfirm={doLogout}
      />

      {/* الإشعارات */}
      <Toaster />
    </div>
  );
}
