/**
 * Type guard to check that a value is a valid day index (non-negative integer).
 */
export function isValidDayIndex(dayIndex: unknown): dayIndex is number {
  return typeof dayIndex === "number" && Number.isInteger(dayIndex) && dayIndex >= 0;
}
