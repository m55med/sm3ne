"use client";
import { useState, useCallback } from "react";
import { Button } from "@/components/ui/button";

type RefreshButtonProps = {
  onRefresh: () => void | Promise<void>;
  label?: string;
  size?: "default" | "sm" | "lg" | "icon";
  variant?: "default" | "outline" | "secondary" | "ghost" | "destructive" | "link";
  className?: string;
  /** When true, render a small "آخر تحديث" timestamp next to the button. */
  showLastRefresh?: boolean;
};

export function RefreshButton({
  onRefresh,
  label = "تحديث",
  size = "sm",
  variant = "outline",
  className,
  showLastRefresh = false,
}: RefreshButtonProps) {
  const [loading, setLoading] = useState(false);
  const [justRefreshed, setJustRefreshed] = useState(false);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);

  const handle = useCallback(async () => {
    if (loading) return;
    setLoading(true);
    try {
      await onRefresh();
      setLastRefresh(new Date());
      setJustRefreshed(true);
      setTimeout(() => setJustRefreshed(false), 1200);
    } finally {
      setLoading(false);
    }
  }, [onRefresh, loading]);

  return (
    <div className="inline-flex items-center gap-2">
      {showLastRefresh && lastRefresh && (
        <span className="text-xs text-gray-400" dir="ltr">
          {lastRefresh.toLocaleTimeString("ar")}
        </span>
      )}
      <Button
        onClick={handle}
        disabled={loading}
        size={size}
        variant={variant}
        className={className}
        aria-label="تحديث البيانات بدون إعادة تحميل الصفحة"
      >
        <span className={`inline-block ${loading ? "animate-spin" : ""}`}>↻</span>
        {justRefreshed ? "تم" : loading ? "..." : label}
      </Button>
    </div>
  );
}
