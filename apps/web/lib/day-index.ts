import { db } from "@/lib/db";
import { users, entries } from "@/lib/db/schema";
import { eq, and, lt, gte, desc } from "drizzle-orm";

/**
 * Derive the user's current day index from DB state.
 *
 * Completion-based model:
 * - Find all normal entries (dayIndex < 100_000) where both reading and writing
 *   are completed.
 * - Current day = max(completed dayIndex) + 1.
 * - If no completed entries exist, returns 0.
 *
 * A non-null `debugDayOverride` on the user record takes absolute precedence.
 */
export async function getCurrentDayIndex(userId: string): Promise<number> {
  // 1. Check debug override
  const [user] = await db
    .select({ debugDayOverride: users.debugDayOverride })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);

  if (user?.debugDayOverride !== null && user?.debugDayOverride !== undefined) {
    return user.debugDayOverride;
  }

  // 2. Find highest completed normal entry
  const completedEntries = await db
    .select({ dayIndex: entries.dayIndex })
    .from(entries)
    .where(
      and(
        eq(entries.userId, userId),
        eq(entries.readingCompleted, true),
        eq(entries.writingCompleted, true),
        lt(entries.dayIndex, 100_000), // exclude bonus readings & free writes
      ),
    );

  if (completedEntries.length === 0) {
    return 0;
  }

  const maxCompleted = Math.max(...completedEntries.map((e) => e.dayIndex));
  return maxCompleted + 1;
}

/**
 * Next available bonus reading dayIndex (>= 100_000, < 200_000).
 * Finds the highest existing bonus entry and returns +1, or 100_000 if none exist.
 */
export async function getNextBonusDayIndex(userId: string): Promise<number> {
  const result = await db
    .select({ dayIndex: entries.dayIndex })
    .from(entries)
    .where(
      and(
        eq(entries.userId, userId),
        gte(entries.dayIndex, 100_000),
        lt(entries.dayIndex, 200_000),
      ),
    )
    .orderBy(desc(entries.dayIndex))
    .limit(1);

  return result.length > 0 ? result[0].dayIndex + 1 : 100_000;
}

/**
 * Next available free-write dayIndex (>= 200_000).
 * Finds the highest existing free-write entry and returns +1, or 200_000 if none exist.
 */
export async function getNextFreeWriteDayIndex(userId: string): Promise<number> {
  const result = await db
    .select({ dayIndex: entries.dayIndex })
    .from(entries)
    .where(
      and(
        eq(entries.userId, userId),
        gte(entries.dayIndex, 200_000),
      ),
    )
    .orderBy(desc(entries.dayIndex))
    .limit(1);

  return result.length > 0 ? result[0].dayIndex + 1 : 200_000;
}
