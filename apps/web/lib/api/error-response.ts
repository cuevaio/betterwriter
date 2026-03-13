import { NextResponse } from "next/server";
import { AuthError } from "@/lib/auth";

/**
 * Consistent error response handler for API routes.
 * Detects AuthError for 401 status, otherwise returns 500.
 */
export function errorResponse(error: unknown, context: string) {
  console.error(`${context} error:`, error);

  if (error instanceof AuthError) {
    return NextResponse.json({ error: error.message }, { status: 401 });
  }

  return NextResponse.json(
    { error: error instanceof Error ? error.message : "Internal error" },
    { status: 500 },
  );
}
