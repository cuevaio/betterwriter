import { sqliteTable, text, integer, uniqueIndex } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: text("id").primaryKey(), // UUID from device Keychain
  createdAt: text("created_at").notNull(), // ISO date
  installDate: text("install_date").notNull(),

  currentStreak: integer("current_streak").default(0),
  longestStreak: integer("longest_streak").default(0),
  totalWordsWritten: integer("total_words_written").default(0),
  onboardingDay0Done: integer("onboarding_day0_done", { mode: "boolean" }).default(false),
  onboardingDay1Done: integer("onboarding_day1_done", { mode: "boolean" }).default(false),

  // Debug: when non-null, getCurrentDayIndex() returns this value instead of computing from entries.
  // Set via direct DB update: UPDATE users SET debug_day_override = 15 WHERE id = '...';
  // Clear with: UPDATE users SET debug_day_override = NULL WHERE id = '...';
  debugDayOverride: integer("debug_day_override"),
});

export const entries = sqliteTable(
  "entries",
  {
    id: text("id").primaryKey(), // UUID
    userId: text("user_id")
      .notNull()
      .references(() => users.id),
    dayIndex: integer("day_index").notNull(),
    calendarDate: text("calendar_date").notNull(), // ISO date

    // Reading — full markdown content (first line = **Title**, last line = source link)
    readingBody: text("reading_body"),
    readingCompleted: integer("reading_completed", { mode: "boolean" }).default(false),

    // Writing
    writingPrompt: text("writing_prompt"),
    writingText: text("writing_text"),
    writingWordCount: integer("writing_word_count").default(0),
    writingCompleted: integer("writing_completed", { mode: "boolean" }).default(false),

    // Metadata
    isBonusReading: integer("is_bonus_reading", { mode: "boolean" }).default(false),
    isFreeWrite: integer("is_free_write", { mode: "boolean" }).default(false),
    skipped: integer("skipped", { mode: "boolean" }).default(false),
  },
  (table) => [
    uniqueIndex("user_day_idx").on(table.userId, table.dayIndex),
  ]
);

// Type helpers
export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
export type Entry = typeof entries.$inferSelect;
export type NewEntry = typeof entries.$inferInsert;
