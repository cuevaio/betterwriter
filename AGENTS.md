# AGENTS.md

Operational guide for coding agents working in this repository.

## 1) Repository Snapshot

- Monorepo: Bun workspaces (`apps/*`) + Turborepo (`turbo.json`).
- Root package: `betterwriter`.
- Apps:
  - `apps/web`: Next.js 15 + React 19 backend/web app.
  - `apps/ios`: native SwiftUI/Xcode app (not a Bun workspace).
- Shared JS packages: none (`packages/` does not exist).

## 2) Build / Lint / Test Commands

Use existing scripts first; do not invent alternatives when a script exists.

### Root commands (from repo root)

| Task | Command |
|---|---|
| Install deps | `bun install` |
| Dev (turbo) | `bun run dev` |
| Build (turbo) | `bun run build` |
| Lint (turbo) | `bun run lint` |
| DB generate | `bun run db:generate` |
| DB push | `bun run db:push` |
| Format all (Biome) | `bun run format` |
| Check all (Biome) | `bun run check` |
| Check + auto-fix (Biome) | `bun run check:fix` |

### Target one workspace via Turbo filter

```bash
bunx turbo dev --filter=web
bunx turbo build --filter=web
bunx turbo lint --filter=web
```

### `apps/web` commands

```bash
bun run dev
bun run dev:turbo
bun run build
bun run start
bun run lint
bun run db:generate
bun run db:push
```

### `apps/ios` commands

- Lint Swift files: `bundle exec fastlane lint` (run from `apps/ios`).
- Build iOS simulator artifact: `bundle exec fastlane build`.
- TestFlight lane: `bundle exec fastlane beta` (CI/release only).

## 3) Tests (Current State + Single-Test Guidance)

- JS/TS tests: no test runner is currently configured; no `*.test.*` / `*.spec.*` files found.
- iOS XCTest targets: no test target detected in current Xcode project.
- Manual web smoke test for durable SSE:
  1. Start web app (`bunx turbo dev --filter=web` or `bun run dev` in `apps/web`).
  2. Run `bash ./test-streams.sh` from repo root.
- Smoke test env overrides:
  - `BASE_URL` (default `http://localhost:3000`)
  - `DEVICE_ID` (default `dev-user-123`)
  - `DAY_INDEX`, `ABOUT_DAY_INDEX`
  - `POST_MAX_TIME` (default `90`)
  - `STREAM_WAIT_SECS` (default `120`)

If tests are added later, prefer these single-test patterns:

- Vitest single file: `bunx vitest run path/to/file.test.ts`
- Vitest single test: `bunx vitest run path/to/file.test.ts -t "test name"`
- Jest single file: `bunx jest path/to/file.test.ts`
- Jest single test: `bunx jest path/to/file.test.ts -t "test name"`
- XCTest single test (if target exists):
  `xcodebuild test -project apps/ios/betterwriter/betterwriter.xcodeproj -scheme betterwriter -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TargetName/TestClass/testMethod`

## 4) Linting, Formatting, and Typechecking

- Root formatting/linting uses Biome (`biome.json`).
- Biome defaults in this repo:
  - 2-space indentation, line width 80.
  - Double quotes, trailing commas `es5`, semicolons always.
  - Organize imports enabled.
- `apps/web` lint command is `next lint`.
- TypeScript in `apps/web` has `strict: true`.
- Ad-hoc typecheck command:
  - `bunx tsc --noEmit -p apps/web/tsconfig.json`
- Swift formatting/linting is driven by `.swift-format` + fastlane lane.

## 5) Code Style and Conventions

### General

- Keep diffs focused; do not reformat unrelated files.
- Preserve existing architecture and naming patterns.
- Avoid `any`; if unavoidable, keep scope narrow and justify.

### TypeScript / Next.js (`apps/web`)

- Use semicolons and explicit types at boundaries.
- Use path alias `@/*` for internal imports.
- Import grouping order:
  1. framework (`next/*`, `react`)
  2. external packages
  3. internal `@/` modules
  4. relative imports
- Use `import type { ... }` for type-only imports.
- Naming:
  - Components: PascalCase (`RootLayout`).
  - Functions/variables: camelCase (`getCurrentDayIndex`).
  - Constants: UPPER_SNAKE_CASE (`UPDATABLE_USER_FIELDS`).
  - Route handler exports: uppercase HTTP names (`GET`, `POST`, `PUT`).

### Validation and API routes

- Validate params/body early with Zod (`apps/web/lib/api/schemas.ts`).
- For protected API routes, call `requireUserId(request)`.
- Return JSON responses via `NextResponse.json(...)` / `Response.json(...)`.
- Keep route handlers wrapped in `try/catch` and use `errorResponse(...)`.

### Error handling patterns

- `AuthError` maps to HTTP 401.
- Other errors map to HTTP 500.
- Log errors with endpoint context (example: `"POST /api/sync error:"`).
- For fire-and-forget async work, attach `.catch(...)` and log failures.

### Database and persistence

- Drizzle schema is in `apps/web/lib/db/schema.ts`.
- Use existing query style (`eq`, `and`, `.limit(1)`).
- Prefer inferred Drizzle types (`$inferSelect`, `$inferInsert`).
- Keep upsert/update logic scoped to allowlisted fields.

### Durable streaming (SSE)

- Reuse shared stream utilities under `apps/web/lib/api/durable-sse.ts` and `apps/web/lib/ai/streaming.ts`.
- Preserve event ordering and replay semantics.
- Emit terminal events (`complete`/`error`) exactly once per stream run.

### Swift (`apps/ios`)

- Follow `.swift-format` rules (2 spaces, width 100, ordered imports).
- Prefer lowerCamelCase for members, UpperCamelCase for types.
- Keep `// MARK:` sections to organize large files.
- Avoid force unwrap unless existing patterns clearly permit it.

## 6) Environment and Security

- Never commit secrets or `.env` files.
- Web env template: `apps/web/.env.example`.
- Common required vars include:
  - `AUTH_SECRET`
  - `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`
  - `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`
  - `QSTASH_TOKEN`, `QSTASH_CURRENT_SIGNING_KEY`, `QSTASH_NEXT_SIGNING_KEY`
  - `MEM0_API_KEY` (and optional `MEM0_MODEL`)
  - `EXA_API_KEY`
  - `DURABLE_STREAM_TTL_SECONDS`
- Local SQLite file `my.db` is gitignored.

## 7) Cursor / Copilot Rules

- No `.cursor/rules/` directory found.
- No `.cursorrules` file found.
- No `.github/copilot-instructions.md` file found.

## 8) Agent Working Agreement

- Prefer minimal, surgical edits.
- Do not edit generated outputs (`.next/`, `.turbo/`, `node_modules/`).
- Run relevant verification after changes (lint/build/smoke test when applicable).
- If tooling or scripts change, update this `AGENTS.md` in the same PR.
