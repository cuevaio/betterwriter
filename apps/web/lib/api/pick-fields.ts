/**
 * Pick defined (non-undefined) fields from a source object, restricted to a set of allowed keys.
 * Returns a typed partial object suitable for Drizzle `.set()` calls.
 */
export function pickDefined<
  T extends Record<string, unknown>,
  K extends keyof T,
>(source: T, keys: readonly K[]): Partial<Pick<T, K>> {
  const result: Partial<Pick<T, K>> = {};
  for (const key of keys) {
    if (source[key] !== undefined) {
      result[key] = source[key];
    }
  }
  return result;
}
