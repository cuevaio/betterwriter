import type { Metadata } from "next";
import { ProsePage } from "@/app/_components/prose-page";

export const metadata: Metadata = {
  title: "Privacy Policy — Better Writer",
  description: "How Better Writer collects, uses, and protects your data.",
};

export default function PrivacyPage() {
  return <ProsePage slug="privacy" />;
}
