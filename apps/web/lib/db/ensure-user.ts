import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import type { User } from "@/lib/db/schema";
import { users } from "@/lib/db/schema";

/**
 * Ensure a user row exists for the given ID.
 * If missing, creates a minimal row (id, createdAt, installDate).
 * Uses INSERT ON CONFLICT DO NOTHING to handle concurrent calls safely.
 * Returns the user row (never null).
 */
export async function ensureUser(userId: string): Promise<User> {
  const [existing] = await db
    .select()
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);

  if (existing) return existing;

  // User missing — auto-create with minimal required fields
  const now = new Date().toISOString();
  const [created] = await db
    .insert(users)
    .values({
      id: userId,
      createdAt: now,
      installDate: now,
    })
    .onConflictDoNothing({ target: users.id })
    .returning();

  // If onConflictDoNothing returned nothing, a concurrent insert won the race
  if (created) return created;

  const [raced] = await db
    .select()
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);

  if (!raced) {
    throw new Error(`Failed to ensure user row for ${userId}`);
  }

  return raced;
}
