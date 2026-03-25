import type { Metadata } from "next";
import { ThemeToggle } from "@/app/_components/theme-toggle";
import "./globals.css";

export const metadata: Metadata = {
  title: "Better Writer — Read. Remember. Write.",
  description:
    "A daily writing habit app. Read something short. Two days later, write about it from memory. That's it.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" data-theme="system" suppressHydrationWarning>
      <body>
        <ThemeToggle />
        {children}
      </body>
    </html>
  );
}
