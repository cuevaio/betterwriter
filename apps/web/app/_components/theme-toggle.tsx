"use client";

import { useEffect, useState } from "react";

type Theme = "light" | "dark" | "system";

const THEME_STORAGE_KEY = "betterwriter-theme";

const THEMES: Theme[] = ["system", "light", "dark"];

export function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>("system");

  useEffect(() => {
    const saved = window.localStorage.getItem(THEME_STORAGE_KEY);
    const initialTheme: Theme = isTheme(saved) ? saved : "system";
    applyTheme(initialTheme);
    setTheme(initialTheme);
  }, []);

  const handleThemeChange = (nextTheme: Theme) => {
    setTheme(nextTheme);
    applyTheme(nextTheme);

    if (nextTheme === "system") {
      window.localStorage.removeItem(THEME_STORAGE_KEY);
      return;
    }

    window.localStorage.setItem(THEME_STORAGE_KEY, nextTheme);
  };

  return (
    <div className="theme-toggle" role="group" aria-label="Theme">
      {THEMES.map((option) => (
        <button
          key={option}
          type="button"
          className="theme-toggle-button"
          data-active={theme === option}
          onClick={() => handleThemeChange(option)}
          aria-pressed={theme === option}
        >
          {labelForTheme(option)}
        </button>
      ))}
    </div>
  );
}

function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
}

function isTheme(value: string | null): value is Theme {
  return value === "light" || value === "dark" || value === "system";
}

function labelForTheme(theme: Theme) {
  if (theme === "light") {
    return "Light";
  }

  if (theme === "dark") {
    return "Dark";
  }

  return "System";
}
