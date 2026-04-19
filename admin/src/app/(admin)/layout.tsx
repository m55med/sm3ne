"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { clearToken } from "@/lib/api";

const navItems = [
  { href: "/dashboard", label: "الإحصائيات", icon: "📊" },
  { href: "/users", label: "المستخدمين", icon: "👥" },
  { href: "/requests", label: "الطلبات", icon: "📋" },
  { href: "/tickets", label: "الرسائل", icon: "📨" },
  { href: "/subscriptions", label: "الاشتراكات", icon: "📜" },
  { href: "/coupons", label: "الكوبونات", icon: "🎟️" },
  { href: "/plans", label: "الباقات", icon: "💎" },
];

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { isAuthenticated, loading } = useAuth();

  // Don't apply admin layout to login page
  if (pathname === "/login") return <>{children}</>;

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center"><div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full" /></div>;
  }

  if (!isAuthenticated) return null;

  return (
    <div className="min-h-screen flex bg-gray-50">
      {/* Sidebar */}
      <aside className="w-64 bg-white border-l shadow-sm hidden md:flex flex-col">
        <div className="p-6 border-b">
          <Link href="/" className="text-2xl font-bold text-blue-600">بصوتك</Link>
          <p className="text-xs text-gray-400 mt-1">لوحة التحكم</p>
        </div>
        <nav className="flex-1 p-4 space-y-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg text-sm transition ${
                pathname === item.href || pathname.startsWith(item.href + "/")
                  ? "bg-blue-50 text-blue-700 font-semibold"
                  : "text-gray-600 hover:bg-gray-50"
              }`}
            >
              <span>{item.icon}</span>
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="p-4 border-t">
          <button
            onClick={() => { clearToken(); window.location.href = "/login"; }}
            className="flex items-center gap-3 px-4 py-3 rounded-lg text-sm text-red-600 hover:bg-red-50 w-full transition"
          >
            <span>🚪</span>
            تسجيل الخروج
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 p-6 overflow-auto">{children}</main>
    </div>
  );
}
