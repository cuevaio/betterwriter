import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { requireUserId } from "@/lib/auth";
import { errorResponse } from "@/lib/api/error-response";
import { pickDefined } from "@/lib/api/pick-fields";

const UPDATABLE_USER_FIELDS = [
  "currentStreak",
  "longestStreak",
  "totalWordsWritten",
  "onboardingDay0Done",
  "onboardingDay1Done",
] as const;

// POST /api/users — Create user (first launch)
export async function POST(request: Request) {
  try {
    const userId = await requireUserId(request);
    const body = await request.json();

    // Try to insert; if already exists, return existing record
    const [created] = await db
      .insert(users)
      .values({
        id: userId,
        createdAt: new Date().toISOString(),
        installDate: body.installDate || new Date().toISOString(),
      })
      .onConflictDoNothing({ target: users.id })
      .returning();

    if (created) {
      return NextResponse.json(created, { status: 201 });
    }

    // Already existed — return current
    const [existing] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    return NextResponse.json(existing);
  } catch (error) {
    return errorResponse(error, "POST /api/users");
  }
}

// GET /api/users — Get user profile
export async function GET(request: Request) {
  try {
    const userId = await requireUserId(request);

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (!user) {
      return NextResponse.json({ error: "User not found" }, { status: 404 });
    }

    return NextResponse.json(user);
  } catch (error) {
    return errorResponse(error, "GET /api/users");
  }
}

// PUT /api/users — Update user profile
export async function PUT(request: Request) {
  try {
    const userId = await requireUserId(request);
    const body = await request.json();

    const allowedFields = pickDefined(body, UPDATABLE_USER_FIELDS);

    if (Object.keys(allowedFields).length === 0) {
      return NextResponse.json({ error: "No valid fields to update" }, { status: 400 });
    }

    await db.update(users).set(allowedFields).where(eq(users.id, userId));

    const [updated] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    return NextResponse.json(updated);
  } catch (error) {
    return errorResponse(error, "PUT /api/users");
  }
}
