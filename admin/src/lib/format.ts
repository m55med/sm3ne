// مساعدات تنسيق الأرقام والتواريخ بالعربية (Intl-based)

const arNumberFormatter = new Intl.NumberFormat("ar-EG");

const arDateFormatter = new Intl.DateTimeFormat("ar-EG", {
  calendar: "gregory",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

const arDateTimeFormatter = new Intl.DateTimeFormat("ar-EG", {
  calendar: "gregory",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
});

const arRelativeFormatter = new Intl.RelativeTimeFormat("ar-EG", { numeric: "auto" });

export function formatNumber(n: number | null | undefined): string {
  if (n == null || !Number.isFinite(n)) return "—";
  return arNumberFormatter.format(n);
}

function safeDate(iso: string | null | undefined): Date | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function formatDate(iso: string | null | undefined): string {
  const d = safeDate(iso);
  return d ? arDateFormatter.format(d) : "—";
}

export function formatDateTime(iso: string | null | undefined): string {
  const d = safeDate(iso);
  return d ? arDateTimeFormatter.format(d) : "—";
}

// صياغة نسبية (منذ كذا) — يقبل ISO ويرجع نصاً مثل "منذ ٥ دقائق"
export function formatRelative(iso: string | null | undefined): string {
  const d = safeDate(iso);
  if (!d) return "—";
  const diffMs = d.getTime() - Date.now();
  const absMs = Math.abs(diffMs);

  const units: Array<{ unit: Intl.RelativeTimeFormatUnit; ms: number }> = [
    { unit: "year", ms: 1000 * 60 * 60 * 24 * 365 },
    { unit: "month", ms: 1000 * 60 * 60 * 24 * 30 },
    { unit: "week", ms: 1000 * 60 * 60 * 24 * 7 },
    { unit: "day", ms: 1000 * 60 * 60 * 24 },
    { unit: "hour", ms: 1000 * 60 * 60 },
    { unit: "minute", ms: 1000 * 60 },
    { unit: "second", ms: 1000 },
  ];

  for (const { unit, ms } of units) {
    if (absMs >= ms || unit === "second") {
      const value = Math.round(diffMs / ms);
      return arRelativeFormatter.format(value, unit);
    }
  }
  return "—";
}
