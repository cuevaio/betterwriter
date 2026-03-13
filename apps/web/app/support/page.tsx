import type { Metadata } from "next";
import { ProsePage } from "@/app/_components/prose-page";

export const metadata: Metadata = {
  title: "Support — Better Writer",
  description: "Get help with Better Writer or make a data request.",
};

export default function SupportPage() {
  return <ProsePage slug="support" />;
}
