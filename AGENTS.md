# AGENTS.md

Operational guide for coding agents working in this repository.

## 1) Repository Snapshot

- Monorepo: Bun workspaces (`apps/*`) + Turborepo (`turbo.json`).
- Root package: `betterwriter` (package manager: `bun@1.2.18`).
- Apps:
  - `apps/web`: Next.js 15 + React 19 API-first backend/web app.
  - `apps/ios`: native SwiftUI/SwiftData app (not a Bun workspace).
- No shared JS packages (`packages/` does not exist).

## 2) Build / Lint / Test Commands

| Task | Command | Where |
|---|---|---|
| Install deps | `bun install` | root |
| Dev (all) | `bun run dev` | root |
| Build (all) | `bun run build` | root |
| Lint (all) | `bun run lint` | root |
| Format (Biome) | `bun run format` | root |
| Check (Biome) | `bun run check` | root |
| Check + fix (Biome) | `bun run check:fix` | root |
| DB generate | `bun run db:generate` | root |
| DB push | `bun run db:push` | root |
| Typecheck web | `bunx tsc --noEmit -p apps/web/tsconfig.json` | root |
| Filter to web | `bunx turbo build --filter=web` | root |
| iOS lint | `bundle exec fastlane lint` | `apps/ios` |
| iOS simulator build | `bundle exec fastlane build` | `apps/ios` |

### Tests

- No JS/TS test runner is configured; no `*.test.*` / `*.spec.*` files exist.
- No iOS XCTest target exists.
- Manual SSE smoke test: start dev server, then `bash ./test-streams.sh` from root.
  Env overrides: `BASE_URL`, `DEVICE_ID`, `DAY_INDEX`, `POST_MAX_TIME`, `STREAM_WAIT_SECS`.

If a test runner is added later, prefer single-test patterns:
- Vitest: `bunx vitest run path/to/file.test.ts -t "test name"`
- Jest: `bunx jest path/to/file.test.ts -t "test name"`

## 3) Commit Conventions

- **Conventional Commits** enforced by `commitlint` + `@commitlint/config-conventional`.
- Husky `commit-msg` hook runs: `bunx --no -- commitlint --edit "$1"`.
- Husky `pre-commit` hook runs: `bunx lint-staged`.
- lint-staged applies `biome check --write` to `*.{js,jsx,ts,tsx,json,css}` and
  `swift-format format --in-place` to `*.swift`.
- Use prefixes like `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, etc.

## 4) Formatting and Linting

### Biome (JS/TS)

Config: `biome.json`. Excludes `apps/ios`.
- 2-space indent, line width 80.
- Double quotes, trailing commas `es5`, semicolons always, arrow parens always.
- Organize imports enabled; recommended linter rules enabled.

### Next.js lint

`apps/web` uses `next lint` (run via `bun run lint` in that workspace).

### TypeScript

`apps/web/tsconfig.json`: `strict: true`, path alias `@/*` -> `./*`.

### Swift

`.swift-format` at repo root: 2-space indent, 100-char line width, ordered imports,
trailing commas, `AlwaysUseLowerCamelCase`, `TypeNamesShouldBeCapitalized`.
`NeverForceUnwrap` is disabled -- force unwrap is permitted where existing patterns use it.

## 5) Code Style -- TypeScript / Next.js (`apps/web`)

### General

- Keep diffs focused; do not reformat unrelated files.
- Avoid `any`; if unavoidable, keep scope narrow and justify.
- Use `import type { ... }` for type-only imports.

### Import order

1. Framework (`next/*`, `react`)
2. External packages (`drizzle-orm`, `zod`, `ai`, `@upstash/*`)
3. Internal `@/` modules (`@/lib/db`, `@/lib/auth`, `@/lib/api/*`, `@/lib/ai/*`)
4. Relative imports

### Naming

- Components: PascalCase (`RootLayout`, `ProsePage`).
- Functions/variables: camelCase (`getCurrentDayIndex`).
- Constants: UPPER_SNAKE_CASE (`UPDATABLE_USER_FIELDS`).
- Route handler exports: uppercase HTTP verb (`GET`, `POST`, `PUT`).

### API route pattern

Every protected route handler follows this structure:

```typescript
export async function METHOD(request: Request) {
  try {
    const userId = await requireUserId(request);
    // validate with Zod safeParse, return 400 on failure
    // business logic
    return NextResponse.json(data, { status: 200 });
  } catch (error) {
    return errorResponse(error, "METHOD /api/route-name");
  }
}
```

- Validate params/body early with Zod (`lib/api/schemas.ts`); use `safeParse`,
  return 400 with `parsed.error.flatten()` on failure.
- `errorResponse()` maps `AuthError` to 401, everything else to 500.
- Log errors with endpoint context (e.g. `"POST /api/sync error:"`).
- Fire-and-forget async work must attach `.catch(...)` and log failures.

### Database (Drizzle + Turso)

- Schema: `apps/web/lib/db/schema.ts`. Tables: `users`, `entries`.
- Unique index `user_day_idx` on `(userId, dayIndex)`.
- Use existing query helpers (`eq`, `and`, `.limit(1)`).
- Prefer inferred types: `User`, `NewUser`, `Entry`, `NewEntry` via `$inferSelect`/`$inferInsert`.
- Upserts use `.insert().values().onConflictDoUpdate()` with whitelist-filtered fields
  via `pickDefined(body, ALLOWED_FIELDS)`.

### Proxy (Edge request interception)

Next.js 16+ uses the `proxy` file convention instead of the deprecated `middleware`.
- File: `apps/web/proxy.ts` (not `middleware.ts`).
- Export a function named `proxy` (not `middleware`).
- Use `export const config = { matcher: [...] }` as before.

### Durable SSE streaming

- Shared utilities: `lib/api/durable-sse.ts`, `lib/ai/streaming.ts`, `lib/ai/durable-stream.ts`.
- Event lifecycle: `start` -> N x `delta` -> `complete` | `error`.
- POST starts generation (acquires entity lock in Redis); GET replays + live-tails.
- Supports `Last-Event-ID` for reconnection. Emit terminal events exactly once.

## 6) Code Style -- Swift (`apps/ios`)

- Architecture: phase-based state machine driven by `AppPhase` enum.
- Persistence: SwiftData (`@Model` classes: `UserProfile`, `DayEntry`).
- Networking: `APIClient` is an `actor` singleton. Handles JWT auth, REST, and SSE
  with automatic 401 retry (re-authenticates and replays once).
- Use `// MARK:` sections to organize large files.
- Use triple-slash `///` for doc comments on public API.
- Prefer lowerCamelCase for members, UpperCamelCase for types.

## 7) Environment and Security

- Never commit secrets or `.env` files.
- Env template: `apps/web/.env.example`.
- Required vars: `AUTH_SECRET`, `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`,
  `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`, `QSTASH_TOKEN`,
  `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`, `DURABLE_STREAM_TTL_SECONDS`.
- Optional: `MEM0_API_KEY`, `MEM0_MODEL`, `EXA_API_KEY`.
- Local SQLite files (`*.db`, `*.db-wal`, `*.db-shm`) are gitignored.

## 8) Cursor / Copilot Rules

No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.

## 9) Agent Working Agreement

- Prefer minimal, surgical edits.
- Do not edit generated outputs (`.next/`, `.turbo/`, `node_modules/`).
- Run relevant verification after changes (lint, build, typecheck when applicable).
- If tooling or scripts change, update this `AGENTS.md` in the same PR.
- When creating a commit, stage and include the active OpenCode plan file (`.opencode/plan.md` or equivalent) so the plan that drove the change is recorded alongside the code.
