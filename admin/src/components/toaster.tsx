"use client";

import * as React from "react";

// نظام Toast بسيط داخلي (custom) — لأن sonner غير مثبت في package.json

type ToastFlavor = "success" | "error" | "info";

export type ToastItem = {
  id: number;
  message: string;
  flavor: ToastFlavor;
};

type Listener = (toasts: ToastItem[]) => void;

const listeners = new Set<Listener>();
let queue: ToastItem[] = [];
let counter = 0;

function notify() {
  for (const l of listeners) l(queue);
}

function push(message: string, flavor: ToastFlavor) {
  if (typeof window === "undefined") return;
  const id = ++counter;
  const item: ToastItem = { id, message, flavor };
  queue = [...queue, item];
  notify();
  // إزالة تلقائية بعد ٤ ثوانٍ
  window.setTimeout(() => {
    queue = queue.filter((t) => t.id !== id);
    notify();
  }, 4000);
}

function dismiss(id: number) {
  queue = queue.filter((t) => t.id !== id);
  notify();
}

export const toast = {
  success(message: string) {
    push(message, "success");
  },
  error(message: string) {
    push(message, "error");
  },
  info(message: string) {
    push(message, "info");
  },
};

const FLAVOR_CLASS: Record<ToastFlavor, string> = {
  success: "bg-emerald-600 text-white",
  error: "bg-red-600 text-white",
  info: "bg-blue-600 text-white",
};

const FLAVOR_ICON: Record<ToastFlavor, string> = {
  success: "✓",
  error: "✕",
  info: "ℹ",
};

export function Toaster() {
  const [toasts, setToasts] = React.useState<ToastItem[]>([]);

  React.useEffect(() => {
    const l: Listener = (next) => setToasts(next);
    listeners.add(l);
    // مزامنة أولية
    setToasts(queue);
    return () => {
      listeners.delete(l);
    };
  }, []);

  if (toasts.length === 0) return null;

  return (
    <div
      role="region"
      aria-label="الإشعارات"
      className="fixed top-4 left-1/2 -translate-x-1/2 z-[100] flex flex-col gap-2 max-w-sm w-[calc(100%-2rem)] pointer-events-none"
    >
      {toasts.map((t) => (
        <div
          key={t.id}
          role={t.flavor === "error" ? "alert" : "status"}
          className={`pointer-events-auto flex items-start gap-3 rounded-lg shadow-lg px-4 py-3 text-sm ${FLAVOR_CLASS[t.flavor]} animate-in fade-in slide-in-from-top-2 duration-150`}
        >
          <span className="font-bold leading-tight">{FLAVOR_ICON[t.flavor]}</span>
          <span className="flex-1 whitespace-pre-wrap leading-relaxed">{t.message}</span>
          <button
            type="button"
            onClick={() => dismiss(t.id)}
            className="opacity-80 hover:opacity-100 text-xs"
            aria-label="إغلاق"
          >
            ✕
          </button>
        </div>
      ))}
    </div>
  );
}
