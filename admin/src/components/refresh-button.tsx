"use client";
import { useState, useCallback } from "react";
import { Button } from "@/components/ui/button";

type RefreshButtonProps = {
  onRefresh: () => void | Promise<void>;
  label?: string;
  size?: "default" | "sm" | "lg" | "icon";
  variant?: "default" | "outline" | "secondary" | "ghost" | "destructive" | "link";
  className?: string;
};

export function RefreshButton({
  onRefresh,
  label = "تحديث",
  size = "sm",
  variant = "outline",
  className,
}: RefreshButtonProps) {
  const [loading, setLoading] = useState(false);
  const [justRefreshed, setJustRefreshed] = useState(false);

  const handle = useCallback(async () => {
    if (loading) return;
    setLoading(true);
    try {
      await onRefresh();
      setJustRefreshed(true);
      setTimeout(() => setJustRefreshed(false), 1200);
    } finally {
      setLoading(false);
    }
  }, [onRefresh, loading]);

  return (
    <Button
      onClick={handle}
      disabled={loading}
      size={size}
      variant={variant}
      className={className}
      title="تحديث البيانات (بدون إعادة تحميل الصفحة)"
    >
      <span className={`inline-block ${loading ? "animate-spin" : ""}`}>↻</span>
      {justRefreshed ? "تم" : loading ? "..." : label}
    </Button>
  );
}
