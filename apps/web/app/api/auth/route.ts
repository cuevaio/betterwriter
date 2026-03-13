import { NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { signJWT } from "@/lib/auth";

const authRequestSchema = z.object({
  deviceId: z.string().min(1, "deviceId is required"),
  installDate: z.string().optional(),
});

// POST /api/auth — Exchange device ID for a signed JWT
export async function POST(request: Request) {
  try {
    const parsed = authRequestSchema.safeParse(await request.json());
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Invalid request", details: parsed.error.flatten() },
        { status: 400 },
      );
    }

    const { deviceId, installDate } = parsed.data;

    // Try to insert; if already exists, fetch existing record
    const [created] = await db
      .insert(users)
      .values({
        id: deviceId,
        createdAt: new Date().toISOString(),
        installDate: installDate || new Date().toISOString(),
      })
      .onConflictDoNothing({ target: users.id })
      .returning();

    const user = created
      ?? (await db.select().from(users).where(eq(users.id, deviceId)).limit(1))[0];

    if (!user) {
      return NextResponse.json({ error: "Failed to create user" }, { status: 500 });
    }

    const { token, expiresAt } = await signJWT(user.id);

    return NextResponse.json({ token, expiresAt, user }, { status: 200 });
  } catch (error) {
    console.error("POST /api/auth error:", error);
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Internal error" },
      { status: 500 },
    );
  }
}
