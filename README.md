# Better Writer

Read. Remember. Write.

Better Writer is a daily writing habit app:
- Read a short curated passage today.
- Write about it from memory two days later.
- Build consistency over time.

## Screenshots

<p align="center">
  <img src="https://betterwriter.vercel.app/show/01-hero-1284x2778.png" width="180" alt="Hero" />
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

## License

Licensed under the GNU Affero General Public License v3.0.
See `LICENSE`.
