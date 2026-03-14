import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

/**
 * Thin proxy for early rejection of unauthenticated API requests.
 * Full JWT verification happens in requireUserId() within each route handler.
 */
export function proxy(request: NextRequest) {
  const auth = request.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) {
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
