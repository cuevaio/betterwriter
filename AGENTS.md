# AGENTS.md

Operational guide for coding agents working in this repository.

## 1) Repository Snapshot

- Monorepo: Bun workspaces (`apps/*`) + Turborepo (`turbo.json`).
- Root package: `betterwriter` (package manager: `bun@1.2.18`).
- Apps:
  - `apps/web`: Next.js 16 + React 19 API-first backend/web app (pure API; web UI is a static marketing page).
  - `apps/ios`: native SwiftUI/SwiftData app (not a Bun workspace).
- No shared JS packages (`packages/` does not exist).
- AI generation uses Vercel AI SDK `^6` (`streamText`) with `@mem0/vercel-ai-provider` for memory-aware responses.
- Background jobs use QStash + `@upstash/workflow`; stream state lives in Upstash Redis.

## 2) Build / Lint / Test Commands

| Task | Command | Where |
|---|---|---|
| Install deps | `bun install` | root |
| Dev (all) | `bun run dev` | root |
| Dev w/ Turbopack | `bun run dev:turbo` | `apps/web` |
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

### Day index partitioning

- Normal days: `0–99,999` (completion-based, not calendar-based).
- Bonus readings: `100,000–199,999`.
- Free writes: `>= 200,000`.
- `debugDayOverride` on the user row overrides computed day (set via direct SQL only).

### Durable SSE streaming

- Shared utilities: `lib/api/durable-sse.ts`, `lib/ai/streaming.ts`, `lib/ai/durable-stream.ts`.
- Event lifecycle: `start` -> N x `delta` -> `complete` | `error`, plus `heartbeat` every 5s.
- POST starts generation (acquires entity lock in Redis via `SET NX`); GET replays + live-tails.
- Supports `Last-Event-ID` for reconnection. Emit terminal events exactly once.
- QStash posts back to the same route with `upstash-signature`; workflow runs inside
  `serve()` from `@upstash/workflow/nextjs`.
- Use `serializeEntry()` from `lib/api/durable-sse.ts` when emitting DB rows in SSE/JSON.

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

## 9) Agent Skills

Skills are pre-loaded instruction sets that give agents specialized knowledge for
specific tasks. Load a skill with the `skill` tool before starting work in that domain.

### Applicable skills for this project

| Skill | When to load it |
|---|---|
| `ai-sdk` | Any time you add or modify AI generation code in `apps/web/lib/ai/` — reading curation, prompt generation, streaming with `streamText`, tool calling, or `@mem0/vercel-ai-provider` memory integration. Also load when adding new AI-powered API routes. |
| `vercel-react-best-practices` | When writing or reviewing React/Next.js code in `apps/web/app/` — page components, layout, server vs. client component decisions, data fetching patterns, or bundle optimization. |
| `swiftui-expert-skill` | Any work in `apps/ios/betterwriter/` — new SwiftUI views, state management, SwiftData model changes, `@Observable` classes, or refactoring existing views. |
| `mobile-ios-design` | When designing new iOS screens or reviewing existing views for iOS Human Interface Guidelines compliance — spacing, typography, interaction patterns, and accessibility. |

### Skills that do NOT apply

- `tailwind-design-system` — The web app uses inline styles and CSS variables, not Tailwind.
- `react-useeffect` — The web has no client components with `useEffect`; it is fully server-rendered.
- `clerk` / `clerk-*` — Auth is a custom zero-dependency JWT implementation (`lib/auth.ts`).
- `trigger-*` — Background jobs use QStash + `@upstash/workflow`, not Trigger.dev.
- All other skills (`scaffold`, `create-element`, `threejs-animation`, etc.) are not relevant.

## 10) Agent Working Agreement

- Prefer minimal, surgical edits.
- Do not edit generated outputs (`.next/`, `.turbo/`, `node_modules/`).
- Run relevant verification after changes (lint, build, typecheck when applicable).
- If tooling or scripts change, update this `AGENTS.md` in the same PR.
- When creating a commit, stage and include the active OpenCode plan file (`.opencode/plan.md` or equivalent) so the plan that drove the change is recorded alongside the code.
