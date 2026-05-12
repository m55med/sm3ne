type SkeletonTableProps = {
  rows?: number;
  cols?: number;
  className?: string;
};

export function SkeletonTable({
  rows = 5,
  cols = 4,
  className,
}: SkeletonTableProps) {
  return (
    <div
      className={`w-full ${className ?? ""}`}
      role="status"
      aria-live="polite"
      aria-busy="true"
    >
      <span className="sr-only">جاري التحميل…</span>
      <table className="w-full">
        <tbody>
          {Array.from({ length: rows }).map((_, r) => (
            <tr key={r} className="border-b last:border-0">
              {Array.from({ length: cols }).map((_, c) => (
                <td key={c} className="py-3 pe-3">
                  <div
                    className="h-4 rounded bg-gray-200 animate-pulse"
                    style={{ width: `${60 + ((r + c) % 4) * 10}%` }}
                  />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
