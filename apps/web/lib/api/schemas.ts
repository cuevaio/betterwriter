import { z } from "zod";

/** POST /api/sync payload — entries carry server-assigned dayIndex values */
export const syncPayloadSchema = z.object({
  user: z
    .object({
      currentStreak: z.number().int().optional(),
      longestStreak: z.number().int().optional(),
      totalWordsWritten: z.number().int().optional(),
      onboardingDay0Done: z.boolean().optional(),
      onboardingDay1Done: z.boolean().optional(),
    })
    .optional(),
  entries: z
    .array(
      z.object({
        dayIndex: z.number().int().min(0),
        calendarDate: z.string(),
        readingCompleted: z.boolean().optional(),
        writingPrompt: z.string().optional(),
        writingText: z.string().optional(),
        writingWordCount: z.number().int().optional(),
        writingCompleted: z.boolean().optional(),
        isBonusReading: z.boolean().optional(),
        isFreeWrite: z.boolean().optional(),
        skipped: z.boolean().optional(),
      })
    )
    .optional(),
});
export type SyncPayload = z.infer<typeof syncPayloadSchema>;

/** PUT /api/entries payload — optional dayIndex; server resolves from context when omitted */
export const entryUpdateSchema = z.object({
  dayIndex: z.number().int().min(0).optional(),
  readingCompleted: z.boolean().optional(),
  writingPrompt: z.string().optional(),
  writingText: z.string().optional(),
  writingWordCount: z.number().int().optional(),
  writingCompleted: z.boolean().optional(),
  isBonusReading: z.boolean().optional(),
  isFreeWrite: z.boolean().optional(),
  skipped: z.boolean().optional(),
});
export type EntryUpdate = z.infer<typeof entryUpdateSchema>;

/** POST /api/user-input payload */
export const userInputSchema = z.object({
  text: z.string().min(1),
});
export type UserInput = z.infer<typeof userInputSchema>;
