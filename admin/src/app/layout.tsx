import type { Metadata } from "next";
import { Cairo } from "next/font/google";
import { ThemeProvider, themeInitScript } from "@/components/theme-provider";
import "./globals.css";

const cairo = Cairo({
  variable: "--font-cairo",
  subsets: ["arabic", "latin"],
});

export const metadata: Metadata = {
  title: "بصوتك - Bisawtak",
  description: "حوّل الصوت إلى نص بدقة عالية مع دعم أكثر من 30 لغة",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ar" dir="rtl" className={`${cairo.variable} h-full antialiased`}>
      <head>
        {/* Sets `dark` class on <html> BEFORE first paint to avoid a flash
            of light theme. Inline-script-injection is required for this
            ordering — the value is a hardcoded constant (no user input),
            so the "no dangerouslySetInnerHTML" rule (admin CLAUDE.md) is
            intentionally relaxed here. */}
        {/* eslint-disable-next-line react/no-danger */}
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
      </head>
      <body className="min-h-full flex flex-col font-[family-name:var(--font-cairo)] bg-background text-foreground">
        <ThemeProvider>{children}</ThemeProvider>
      </body>
    </html>
  );
}
