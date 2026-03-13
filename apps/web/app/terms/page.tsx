import type { Metadata } from "next";
import { ProsePage } from "@/app/_components/prose-page";

export const metadata: Metadata = {
  title: "Terms of Use — Better Writer",
  description:
    "The terms and conditions that govern your use of Better Writer.",
};

export default function TermsPage() {
  return <ProsePage slug="terms" />;
}
