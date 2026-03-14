import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

/**
 * Thin proxy for early rejection of unauthenticated API requests.
 * Full JWT verification happens in requireUserId() within each route handler.
 */
export function proxy(request: NextRequest) {
  const auth = request.headers.get("Authorization");
  const hasQstashSignature = Boolean(request.headers.get("upstash-signature"));

  // Allow requests with a valid Bearer token OR a QStash signature.
  // QStash signatures are verified cryptographically inside the workflow
  // handler — the proxy is just an early-rejection layer.
  if (!auth?.startsWith("Bearer ") && !hasQstashSignature) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  return NextResponse.next();
}

export const config = {
  matcher: [
    // Protect all API routes except /api/auth
    "/api/((?!auth).*)",
  ],
};
