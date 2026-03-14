import { and, desc, eq, gte, lt } from "drizzle-orm";
import { NextResponse } from "next/server";
import { getActiveStreamId, releaseEntityLock } from "@/lib/ai/durable-stream";
import { addUserInputMemory } from "@/lib/ai/mem0";
import { errorResponse } from "@/lib/api/error-response";
import { pickDefined } from "@/lib/api/pick-fields";
import { type EntryUpdate, entryUpdateSchema } from "@/lib/api/schemas";
import { requireUserId } from "@/lib/auth";
import {
  getCurrentDayIndex,
  getNextBonusDayIndex,
  getNextFreeWriteDayIndex,
} from "@/lib/day-index";
import { db } from "@/lib/db";
import { entries, users } from "@/lib/db/schema";

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

/**
 * Determine which entry to target based on the update context:
 * - isBonusReading: find in-progress bonus entry, or allocate next bonus index
 * - isFreeWrite: find in-progress free write entry, or allocate next free write index
 * - otherwise: use the computed current day
 */
async function resolveTargetDayIndex(
  userId: string,
  updates: EntryUpdate
): Promise<number> {
  if (updates.isBonusReading) {
    // Find in-progress bonus reading (isBonusReading && !readingCompleted)
    const inProgress = await db
      .select({ dayIndex: entries.dayIndex })
      .from(entries)
      .where(
        and(
          eq(entries.userId, userId),
          eq(entries.isBonusReading, true),
          eq(entries.readingCompleted, false),
          gte(entries.dayIndex, 100_000),
          lt(entries.dayIndex, 200_000)
        )
      )
      .orderBy(desc(entries.dayIndex))
      .limit(1);

    if (inProgress.length > 0) return inProgress[0].dayIndex;
    return getNextBonusDayIndex(userId);
  }

  if (updates.isFreeWrite) {
    // Find in-progress free write (isFreeWrite && !writingCompleted)
    const inProgress = await db
      .select({ dayIndex: entries.dayIndex })
      .from(entries)
      .where(
        and(
          eq(entries.userId, userId),
          eq(entries.isFreeWrite, true),
          eq(entries.writingCompleted, false),
          gte(entries.dayIndex, 200_000)
        )
      )
      .orderBy(desc(entries.dayIndex))
      .limit(1);

    if (inProgress.length > 0) return inProgress[0].dayIndex;
    return getNextFreeWriteDayIndex(userId);
  }

  return getCurrentDayIndex(userId);
}

// GET /api/entries?dayIndex=5 — Get entry for a specific day
export async function GET(request: Request) {
  try {
    const userId = await requireUserId(request);
    const { searchParams } = new URL(request.url);
    const dayIndexStr = searchParams.get("dayIndex");

    if (dayIndexStr === null) {
      // Return all entries for the user
      const allEntries = await db
        .select()
        .from(entries)
        .where(eq(entries.userId, userId));

      return NextResponse.json(allEntries);
    }

    // Support "current" to let the server compute the active day
    let dayIndex: number;
    if (dayIndexStr === "current") {
      dayIndex = await getCurrentDayIndex(userId);
    } else {
      dayIndex = parseInt(dayIndexStr, 10);
      if (!Number.isFinite(dayIndex) || dayIndex < 0) {
        return NextResponse.json(
          { error: "Invalid dayIndex" },
          { status: 400 }
        );
      }
    }

    const entry = await db
      .select()
      .from(entries)
      .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
      .limit(1);

    if (entry.length === 0) {
      // Return the computed dayIndex even when no entry exists yet
      return NextResponse.json({ dayIndex, entry: null });
    }

    return NextResponse.json(entry[0]);
  } catch (error) {
    return errorResponse(error, "GET /api/entries");
  }
}

// PUT /api/entries — Update an entry (server resolves target from context)
export async function PUT(request: Request) {
  try {
    const userId = await requireUserId(request);

    // Verify the user exists in the DB before attempting entry upsert.
    // The JWT may reference a deleted user (e.g. after DB wipe with
    // Keychain-persisted credentials), which would cause an FK violation.
    const userExists = await db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (userExists.length === 0) {
      // Return 401 so the iOS client's automatic retry re-authenticates
      // (creating the user via POST /api/auth) then replays this request.
      return NextResponse.json({ error: "User not found" }, { status: 401 });
    }

    const parsed = entryUpdateSchema.safeParse(await request.json());
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Invalid request", details: parsed.error.flatten() },
        { status: 400 }
      );
    }
    const updates = parsed.data;

    // Server determines which entry to target
    const dayIndex = await resolveTargetDayIndex(userId, updates);

    const allowedFields = pickDefined(updates, UPDATABLE_ENTRY_FIELDS);

    // Check if entry exists to determine status code
    const existing = await db
      .select({ id: entries.id })
      .from(entries)
      .where(and(eq(entries.userId, userId), eq(entries.dayIndex, dayIndex)))
      .limit(1);

    const isNew = existing.length === 0;

    const [row] = await db
      .insert(entries)
      .values({
        id: isNew ? crypto.randomUUID() : existing[0].id,
        userId,
        dayIndex,
        calendarDate: new Date().toISOString().split("T")[0],
        ...allowedFields,
      })
      .onConflictDoUpdate({
        target: [entries.userId, entries.dayIndex],
        set: allowedFields,
      })
      .returning();

    // If this update marks a reading as completed, release the entity lock
    // so the next POST /api/readings/generate/stream can start fresh.
    if (allowedFields.readingCompleted === true) {
      const activeStreamId = await getActiveStreamId(userId, "reading");
      if (activeStreamId) {
        await releaseEntityLock(userId, "reading", activeStreamId);
      }
    }

    // Store free write text as memories in Mem0 (fire-and-forget)
    if (
      allowedFields.isFreeWrite === true &&
      allowedFields.writingCompleted === true &&
      allowedFields.writingText &&
      allowedFields.writingText.trim()
    ) {
      addUserInputMemory(userId, allowedFields.writingText).catch((err) => {
        console.error("Failed to add free write memory:", err);
      });
    }

    return NextResponse.json(row, { status: isNew ? 201 : 200 });
  } catch (error) {
    return errorResponse(error, "PUT /api/entries");
  }
}
