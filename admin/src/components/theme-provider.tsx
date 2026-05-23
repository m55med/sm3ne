"use client";
import { createContext, useContext, useEffect, useState } from "react";

type Theme = "light" | "dark";

interface ThemeContextValue {
  theme: Theme;
  setTheme: (t: Theme) => void;
  toggle: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);
const STORAGE_KEY = "admin-theme";

/// Wraps the app and keeps the `<html>` `dark` class in sync with the user's
/// preference. The class is also set by an inline script in `layout.tsx`
/// BEFORE hydration to avoid the FOUC where the first paint is light and
/// snaps to dark a frame later. Without that pre-script, dark-mode users
/// see a white flash on every page load.
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setThemeState] = useState<Theme>("light");

  useEffect(() => {
    // Pick up whatever the pre-hydration script set on <html>. We sync the
    // React state to the DOM, not the other way around — the script is the
    // source of truth on first paint.
    const fromDom: Theme = document.documentElement.classList.contains("dark")
      ? "dark"
      : "light";
    setThemeState(fromDom);
  }, []);

  const setTheme = (t: Theme) => {
    setThemeState(t);
    if (t === "dark") {
      document.documentElement.classList.add("dark");
      document.documentElement.style.colorScheme = "dark";
    } else {
      document.documentElement.classList.remove("dark");
      document.documentElement.style.colorScheme = "light";
    }
    try {
      localStorage.setItem(STORAGE_KEY, t);
    } catch {/* ignore persistence failures */}
  };

  const toggle = () => setTheme(theme === "dark" ? "light" : "dark");

  return (
    <ThemeContext.Provider value={{ theme, setTheme, toggle }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    // Defensive fallback so a misplaced consumer doesn't crash the whole
    // page — toggling a no-op is preferable to a white screen.
    return {
      theme: "light",
      setTheme: () => {},
      toggle: () => {},
    };
  }
  return ctx;
}

/// Inline script string injected into <head> BEFORE React hydrates so that
/// the very first paint matches the user's saved preference (or system pref
/// when none is saved). Keep this self-contained — it runs in vanilla JS.
export const themeInitScript = `
(function () {
  try {
    var k = '${STORAGE_KEY}';
    var saved = localStorage.getItem(k);
    var mql = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
    var prefersDark = !!(mql && mql.matches);
    var theme = saved === 'dark' || saved === 'light' ? saved : (prefersDark ? 'dark' : 'light');
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
      document.documentElement.style.colorScheme = 'dark';
    } else {
      document.documentElement.style.colorScheme = 'light';
    }
  } catch (_) { /* ignore */ }
})();
`;
