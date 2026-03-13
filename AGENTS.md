# AGENTS.md

Operational guide for coding agents working in this repository.

## 1. Repository Overview

- Monorepo: Bun workspaces (`apps/*`) + Turborepo. Root package: `betterwriter`.
- `apps/web` -- Main app. Next.js 15, React 19, AI SDK v6, Drizzle + Turso, Upstash Workflow/Redis.
- `apps/ios/` -- Native iOS/Xcode project. Not a JS workspace; ignored by Turbo.
- No `packages/` directory. No shared JS packages.

## 2. Commands

Use package scripts; avoid inventing alternate commands.

### Root (run from repo root)

| Task | Command |
|---|---|
| Install deps | `bun install` |
| Dev (all) | `bun run dev` |
| Build (all) | `bun run build` |
| Lint (all) | `bun run lint` |
| DB push | `bun run db:push` |
| DB generate | `bun run db:generate` |

### Single-workspace via Turbo filter

```
bunx turbo dev --filter=web
bunx turbo build --filter=web
bunx turbo lint --filter=web
bunx turbo dev --filter=@upstash/realtime
bunx turbo build --filter=@upstash/realtime
```

### apps/web local scripts

`dev`, `dev:turbo`, `build`, `start`, `lint` (next lint), `db:generate`, `db:push`.

## 3. Tests

**No test framework is configured.** No vitest/jest, no `*.test.*` or `*.spec.*` files exist.

If you add Vitest later:
- Single file: `bunx vitest run path/to/file.test.ts`
- Single test: `bunx vitest run path/to/file.test.ts -t "test name"`

### Manual smoke test

Start local server first, then: `bash ./test-streams.sh`

Env overrides: `BASE_URL` (default `http://localhost:3000`), `DEVICE_ID` (default `dev-user-123`), `DAY_INDEX`, `ABOUT_DAY_INDEX`, `POST_MAX_TIME` (default `90`), `STREAM_WAIT_SECS` (default `120`).

## 4. Lint & Typecheck

- Both workspaces use `strict: true` in tsconfig.
- `apps/web` uses `next lint` with no custom eslint config (Next.js defaults).
- No Prettier, Biome, or other formatter configured.
- No root `typecheck` script. Ad-hoc:
  - `bunx tsc --noEmit -p apps/web/tsconfig.json`
- Prefer fixing type issues rather than suppressing them.

## 5. Code Style

### Formatting

- Follow existing file-local style. Do not mass-reformat unrelated files.
- `apps/web`: **uses semicolons**, explicit typing.

### Imports

- Path alias `@/` maps to `./` in `apps/web`.
- Import order: 1) framework (`next/*`, `react`), 2) external packages, 3) `@/` internal, 4) relative.
- Use `import type { ... }` for type-only imports.

### Naming

- Components: PascalCase (`RootLayout`, `Chat`).
- Functions/variables: camelCase (`generateReadingStream`, `dayIndex`).
- Route handler exports: uppercase (`GET`, `POST`, `PUT`).
- Constants: UPPER_SNAKE_CASE (`READING_CURATION_PROMPT`, `UPDATABLE_USER_FIELDS`).
- Prefer descriptive names; abbreviations only for small loop vars.

### Types

- Define explicit interfaces near API boundaries.
- Narrow unknown input with type guards (e.g., `isValidDayIndex`) before use.
- Use Drizzle inferred types (`$inferSelect`, `$inferInsert`) for DB entities.
- Avoid `any`; if unavoidable, keep scope narrow and add a comment.

### Error handling

- Route handlers: `try/catch` around logic, delegate to `errorResponse()` utility.
- `AuthError` -> 401; generic errors -> 500. Always return JSON payloads.
- Log with endpoint context: `"POST /api/sync error:"`.
- Fire-and-forget async: attach `.catch()` and log.

### API route patterns (Next.js App Router)

- Validate params/body early with Zod (schemas in `lib/api/schemas.ts`). Return 400 on failure.
- Protected routes: call `requireUserId(request)` (JWT-based auth).
- Middleware in `apps/web/middleware.ts` checks Bearer token on all `/api/*` except `/api/auth`.
- Responses: `NextResponse.json(...)` or `Response.json(...)`.
- SSE endpoints: use helpers in `lib/ai/streaming.ts` (`sseHeaders`, `writeSSE`, `writeSSEComment`).

### Database (Drizzle + Turso)

- Schema: `apps/web/lib/db/schema.ts`. Two tables: `users`, `entries`.
- Unique index: `user_day_idx` on `(userId, dayIndex)`.
- DB client: lazy-initializing Proxy in `lib/db/index.ts` (`drizzle-orm/libsql`).
- Drizzle config: `apps/web/drizzle.config.ts` (dialect: `turso`, migrations: `lib/db/migrations/`).
- Use existing query builder patterns (`eq`, `and`, `.limit(1)`).
- Preserve upsert-like update-or-insert logic. Scope writes to allowed fields only.

### Durable streaming (Redis-backed)

- Stream metadata/events stored in Upstash Redis.
- Maintain event ordering via sequence IDs.
- Emit terminal events (`complete`/`error`) exactly once per stream run.
- Preserve heartbeat and replay semantics for reconnecting clients.
- Shared handler: `lib/api/durable-sse.ts`.

## 6. Key Source Layout (apps/web)

```
lib/
  ai/         -- AI generation, prompts, streaming, Redis client, Mem0 memory
  api/        -- Shared route utilities (durable SSE, error response, Zod schemas)
  db/         -- Drizzle client, schema, migrations/
  auth.ts     -- JWT sign/verify via Web Crypto (edge-compatible, zero deps)
  day-index.ts, exa.ts, validation.ts
app/api/
  auth/       -- POST: exchange deviceId for JWT
  entries/    -- GET/PUT: entries CRUD
  prompts/generate/stream/  -- GET: SSE replay; POST: start prompt generation
  readings/generate/stream/ -- GET: SSE replay; POST: start reading generation
  sync/       -- POST: bulk device sync
  user-input/ -- POST: save writing text + Mem0
  users/      -- POST/GET/PUT: user profile
```

## 7. Environment & Security

- Never commit `.env` files or secrets.
- Template: `apps/web/.env.example`.
- Required env vars (not all in `.env.example`):
  - `AUTH_SECRET` -- JWT signing
  - `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN` -- Drizzle/Turso DB
  - `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` -- Redis
  - `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY` -- QStash/Workflow
  - `MEM0_API_KEY`, `MEM0_MODEL` (optional, defaults to `openai/gpt-oss-120b`) -- Mem0
  - `EXA_API_KEY` -- Exa search
  - `DURABLE_STREAM_TTL_SECONDS` (default `86400`)
- Local dev SQLite: `my.db` at repo root (gitignored).

## 8. Cursor/Copilot Rules

No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.

## 9. Agent Working Agreement

- Prefer minimal, focused diffs.
- Do not modify generated folders (`.next/`, `node_modules/`, `.turbo/`).
- Verify changes with available tools (lint, build, manual smoke test).
- When adding new tooling, update this file with the new commands.
