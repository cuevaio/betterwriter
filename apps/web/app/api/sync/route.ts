import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { users, entries } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { requireUserId } from "@/lib/auth";
import { errorResponse } from "@/lib/api/error-response";
import { pickDefined } from "@/lib/api/pick-fields";
import { syncPayloadSchema } from "@/lib/api/schemas";
import { getCurrentDayIndex } from "@/lib/day-index";

const UPDATABLE_USER_FIELDS = [
  "currentStreak",
  "longestStreak",
  "totalWordsWritten",
  "onboardingDay0Done",
  "onboardingDay1Done",
] as const;

const UPDATABLE_ENTRY_FIELDS = [
  "readingCompleted",
  "writingPrompt",
  "writingText",
  "writingWordCount",
  "writingCompleted",
  "isBonusReading",
  "isFreeWrite",
  "skipped",
] as const;

// POST /api/sync — Bulk sync from device
export async function POST(request: Request) {
  try {
    const userId = await requireUserId(request);

    const parsed = syncPayloadSchema.safeParse(await request.json());
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Invalid request", details: parsed.error.flatten() },
        { status: 400 },
      );
    }
    const body = parsed.data;

    // Sync user profile updates
    if (body.user) {
      const userUpdates = pickDefined(body.user, UPDATABLE_USER_FIELDS);

      if (Object.keys(userUpdates).length > 0) {
        await db.update(users).set(userUpdates).where(eq(users.id, userId));
      }
    }

    // Sync entries — upsert in parallel using onConflictDoUpdate
    if (body.entries && body.entries.length > 0) {
      await Promise.all(
        body.entries.map(async (entry) => {
          const syncFields = pickDefined(entry, UPDATABLE_ENTRY_FIELDS);

          await db
            .insert(entries)
            .values({
              id: crypto.randomUUID(),
              userId,
              dayIndex: entry.dayIndex,
              calendarDate: entry.calendarDate,
              ...syncFields,
            })
            .onConflictDoUpdate({
              target: [entries.userId, entries.dayIndex],
              set: syncFields,
            });
        }),
      );
    }

    // Return current server state
    const [user, allEntries] = await Promise.all([
      db
        .select()
        .from(users)
        .where(eq(users.id, userId))
        .limit(1),
      db
        .select()
        .from(entries)
        .where(eq(entries.userId, userId)),
    ]);

    const currentDayIndex = await getCurrentDayIndex(userId);

    return NextResponse.json({
      user: user[0] || null,
      entries: allEntries,
      currentDayIndex,
    });
  } catch (error) {
    return errorResponse(error, "POST /api/sync");
  }
}
