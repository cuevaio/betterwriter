import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { users, entries } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { requireUserId } from "@/lib/auth";
import { addUserInputMemory } from "@/lib/ai/mem0";
import { errorResponse } from "@/lib/api/error-response";
import { userInputSchema } from "@/lib/api/schemas";
import { getCurrentDayIndex } from "@/lib/day-index";

function countWords(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) return 0;
  return trimmed.split(/\s+/).length;
}

export async function POST(request: Request) {
  try {
    const userId = await requireUserId(request);

    const parsed = userInputSchema.safeParse(await request.json());
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Invalid request", details: parsed.error.flatten() },
        { status: 400 },
      );
    }
    const { text } = parsed.data;

    const [user] = await db
      .select()
      .from(users)
      .where(eq(users.id, userId))
      .limit(1);

    if (!user) {
      return NextResponse.json({ error: "User not found" }, { status: 404 });
    }

    // Server computes the current day from entries
    const dayIndex = await getCurrentDayIndex(userId);

    // Store writing as memories in Mem0 (fire-and-forget, don't block response)
    addUserInputMemory(userId, text).catch((err) => {
      console.error("Failed to add memory:", err);
    });

    const writingWordCount = countWords(text);

    // Upsert: insert or update entry in a single query
    const [row] = await db
      .insert(entries)
      .values({
        id: crypto.randomUUID(),
        userId,
        dayIndex,
        calendarDate: new Date().toISOString().split("T")[0],
        writingText: text,
        writingWordCount,
      })
      .onConflictDoUpdate({
        target: [entries.userId, entries.dayIndex],
        set: { writingText: text, writingWordCount },
      })
      .returning();

    return NextResponse.json({ entry: row ?? null });
  } catch (error) {
    return errorResponse(error, "POST /api/user-input");
  }
}
