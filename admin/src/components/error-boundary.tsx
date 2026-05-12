"use client";
import { Component, type ReactNode } from "react";
import { Button } from "@/components/ui/button";

type ErrorBoundaryProps = {
  children: ReactNode;
  fallback?: ReactNode;
};

type ErrorBoundaryState = {
  hasError: boolean;
  error: Error | null;
};

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: unknown) {
    // eslint-disable-next-line no-console
    console.error("[ErrorBoundary]", error, info);
  }

  reset = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;
      const message = this.state.error?.message || "حدث خطأ غير متوقع";
      return (
        <div
          role="alert"
          className="flex flex-col items-center justify-center rounded-xl border border-red-200 bg-red-50 px-6 py-10 text-center"
        >
          <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-red-100">
            <svg
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-7 w-7 text-red-600"
            >
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
          </div>
          <h2 className="text-lg font-bold text-red-900">حدث خطأ ما</h2>
          <p className="mt-1 max-w-md text-sm text-red-700">
            تعذّر عرض هذا الجزء من الصفحة. يمكنك المحاولة مجدداً.
          </p>
          <p
            className="mt-2 max-w-md text-xs text-red-500 font-mono break-all"
            dir="ltr"
          >
            {message.slice(0, 200)}
          </p>
          <Button
            onClick={this.reset}
            size="sm"
            variant="outline"
            className="mt-4"
          >
            إعادة المحاولة
          </Button>
        </div>
      );
    }
    return this.props.children;
  }
}
