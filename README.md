# Better Writer

Read. Remember. Write.

Better Writer is a daily writing habit app:
- Read a short curated passage today.
- Write about it from memory two days later.
- Build consistency over time.

## Screenshots

<p align="center">
  <img src="https://betterwriter.vercel.app/screenshots/done.png" width="180" alt="Hero" />
  <img src="https://betterwriter.vercel.app/show/02-method-1284x2778.png" width="180" alt="Method" />
  <img src="https://betterwriter.vercel.app/show/03-reading-1284x2778.png" width="180" alt="Reading" />
  <img src="https://betterwriter.vercel.app/show/04-writing-1284x2778.png" width="180" alt="Writing" />
  <img src="https://betterwriter.vercel.app/show/05-progress-1284x2778.png" width="180" alt="Progress" />
  <img src="https://betterwriter.vercel.app/show/06-closing-1284x2778.png" width="180" alt="Closing" />
</p>

This repository is a Bun + Turborepo monorepo.

## Apps

- `apps/web` - Next.js 15 backend + web landing pages
- `apps/ios` - Native iOS app (Xcode project)

## Requirements

- Bun (latest)
- Node.js (for Next.js tooling compatibility)
- Xcode (for iOS development)

## Getting Started

Install dependencies:

```bash
bun install
```

Run all dev targets:

```bash
bun run dev
```

Run only web app:

```bash
bunx turbo dev --filter=web
```

Build all targets:

```bash
bun run build
```

Lint all targets:

```bash
bun run lint
```

## Database Commands

```bash
bun run db:generate
bun run db:push
```

## Environment

Create env vars for `apps/web` before running locally.

Required variables include:
- `AUTH_SECRET`
- `TURSO_DATABASE_URL`
- `TURSO_AUTH_TOKEN`
- `UPSTASH_REDIS_REST_URL`
- `UPSTASH_REDIS_REST_TOKEN`
- `QSTASH_TOKEN`
- `QSTASH_CURRENT_SIGNING_KEY`
- `QSTASH_NEXT_SIGNING_KEY`
- `MEM0_API_KEY`
- `EXA_API_KEY`

See `apps/web/.env.example` for the template.

## Technologies

### Web (`apps/web`)

| Technology | Purpose |
|---|---|
| **Next.js 16** | Full-stack React framework. Handles API routes, server-side rendering for the marketing landing pages, and the proxy layer (edge request interception). |
| **React 19** | UI library for the web frontend. The app is mostly server-rendered; there are no client-side components with heavy state. |
| **TypeScript** | Static typing across the entire web codebase with `strict: true`. |
| **Drizzle ORM** | Type-safe SQL query builder and migration toolkit. Used to define the schema (`users`, `entries`) and interact with the database. |
| **Turso (libSQL)** | Serverless SQLite-compatible database. Stores user accounts and writing entries, partitioned by day index. |
| **Vercel AI SDK (`ai` v6)** | Core AI generation primitives (`streamText`). Manages streaming lifecycle, tool calling, and provider abstraction. |
| **`@mem0/vercel-ai-provider`** | Drop-in AI provider wrapper that adds long-term memory to AI responses. Each generation can recall previous interactions for the same user. |
| **Upstash Redis** | In-memory data store used for two things: durable SSE stream state (buffering delta events for reconnection) and distributed entity locking (`SET NX`) to prevent duplicate generation jobs. |
| **QStash (`@upstash/qstash`)** | HTTP-based durable message queue. Enqueues background AI generation jobs and delivers them with at-least-once guarantees and signature verification. |
| **`@upstash/workflow`** | Durable workflow engine built on QStash. Wraps multi-step AI generation inside a `serve()` handler so long-running jobs survive serverless cold starts and timeouts. |
| **Exa** | AI-native search API. Used to curate and discover high-quality reading passages for users. |
| **Zod** | Schema declaration and validation library. All API request bodies and parameters are validated with Zod `safeParse` before reaching business logic. |
| **Biome** | All-in-one linter and formatter (replaces ESLint + Prettier). Enforces code style on all JS/TS/JSON/CSS files. |

### iOS (`apps/ios`)

| Technology | Purpose |
|---|---|
| **SwiftUI** | Declarative UI framework for building the native iOS app. All screens are SwiftUI views driven by a phase-based state machine (`AppPhase`). |
| **SwiftData** | Apple's persistence framework. Stores the local user profile (`UserProfile`) and writing entries (`DayEntry`) on-device. |
| **Swift Concurrency (`async`/`await`, `actor`)** | Used throughout the networking layer. `APIClient` is an `actor` to serialize access and prevent data races. |

### Monorepo & Tooling

| Technology | Purpose |
|---|---|
| **Bun** | JavaScript runtime and package manager. Manages workspaces and runs all scripts significantly faster than npm/yarn. |
| **Turborepo** | Monorepo build orchestration. Caches build and lint outputs and runs tasks across workspaces in the correct dependency order. |
| **Husky + lint-staged** | Git hooks. `pre-commit` runs Biome on staged JS/TS files and `swift-format` on staged Swift files. `commit-msg` enforces Conventional Commits via `commitlint`. |

## License

Licensed under the GNU Affero General Public License v3.0.
See `LICENSE`.
