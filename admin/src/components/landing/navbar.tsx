"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { isAdminTokenValid } from "@/lib/auth";
import { ThemeToggle } from "@/components/theme-toggle";

export function Navbar() {
  // افتراضياً /login — يُحدّث بعد الـ mount لو وُجدت جلسة أدمن صالحة
  const [ctaHref, setCtaHref] = useState("/login");

  useEffect(() => {
    if (isAdminTokenValid()) setCtaHref("/dashboard");
  }, []);

  return (
    <nav className="sticky top-0 z-50 bg-white/80 dark:bg-background/80 backdrop-blur-md border-b border-border">
      <div className="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
        <Link href="/" className="text-2xl font-bold text-blue-600 dark:text-blue-400">
          بصوتك
        </Link>
        <div className="flex items-center gap-4">
          <Link href="#features" className="text-sm text-gray-600 dark:text-muted-foreground hover:text-gray-900 dark:hover:text-foreground hidden sm:block">المميزات</Link>
          <Link href="#plans" className="text-sm text-gray-600 dark:text-muted-foreground hover:text-gray-900 dark:hover:text-foreground hidden sm:block">الباقات</Link>
          <Link href="#faq" className="text-sm text-gray-600 dark:text-muted-foreground hover:text-gray-900 dark:hover:text-foreground hidden sm:block">الأسئلة</Link>
          <ThemeToggle />
          <Link href={ctaHref} className="text-sm bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition">
            لوحة التحكم
          </Link>
        </div>
      </div>
    </nav>
  );
}
