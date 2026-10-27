# AI RAG Chatbot — Local Development

pnpm monorepo: Next.js + TypeScript (`apps/web`), NestJS (`apps/api`), PostgreSQL + pgvector and Redis (`infra`). BullMQ is installed and verified by a temporary smoke-test worker; no persistent application worker or RAG feature exists yet.

## Requirements

Use Ubuntu inside WSL2, Node.js 24 (`.nvmrc`), pnpm 12.15.0, and Docker Desktop with working WSL integration. Keep this repository on the Linux filesystem. Run commands below from the repository root.

## First setup

```bash
corepack enable pnpm
pnpm install --frozen-lockfile
cp .env.example .env
chmod 600 .env
```

Skip copying if `.env` already exists. Set a local password in both `POSTGRES_PASSWORD` and `DATABASE_URL`. URL-encode special characters in the URL password. The initial setup performed by Codex already generated a random local password in the ignored `.env`.

```bash
pnpm infra:up
pnpm dev
```

Open http://localhost:3000. API health: http://localhost:3001/health. The frontend fetches API health on the server and displays the dependency status. Both apps read the root `.env`; restart them after changing environment variables.

Infrastructure ports bind only to 127.0.0.1. PostgreSQL and Redis retain data in project-specific named volumes. Redis uses AOF and `noeviction` for BullMQ. This Compose file is for local development only.

## Validation

With infrastructure and both apps running, use another Ubuntu terminal:

```bash
pnpm infra:status
pnpm typecheck
pnpm test:smoke
```

The smoke test checks a real pgvector distance operation, Redis PING, a BullMQ job processed by a temporary worker, NestJS health, and the Next.js page connected to the backend. It cleans only its own randomly named queue. The test expects default local Redis without authentication; extend it when introducing production Redis settings.

For a build check, stop `pnpm dev` with Ctrl+C before running `pnpm build` so Next.js does not share `.next` between dev and build. This validates compilation; production hosting is prepared in Step 3.

## Stop and resume

Stop app processes with Ctrl+C, then run `pnpm infra:down`. This preserves the database and Redis volumes. Resume with `pnpm infra:up` and `pnpm dev`. Do not add `-v` to the down command unless explicitly intending to delete local data.

## Configuration and troubleshooting

- `.env` is ignored by Git; `.env.example` is the committed template. Do not put credentials in `NEXT_PUBLIC_*` variables.
- Keep `API_PORT` and `API_INTERNAL_URL` aligned. Keep `POSTGRES_PORT` / `REDIS_PORT` aligned with the corresponding connection URLs. `WEB_ORIGIN` must match the frontend origin. Frontend dev defaults to port 3000.
- Database init SQL runs only on a fresh volume. Changing PostgreSQL credentials in `.env` does not change existing database credentials. Do not delete volumes to resolve this; inspect and update credentials deliberately.
- If pgvector is absent in an existing database, inspect it first, then explicitly apply `infra/postgres/001-vector.sql` to that database.
- If Docker is denied inside Codex Sandbox, use a normal Ubuntu terminal or an approved execution outside the Sandbox. Never change the Docker socket to mode 666.
- A Codex read-only PATH-alias warning inside the Sandbox does not require modifying system permissions when normal Ubuntu CLI checks pass.
- Package resolution waits 24 hours after publication (`minimumReleaseAge`). Commit `pnpm-lock.yaml` with dependency changes. Do not disable this setting just to install a newly released package.

## Layout

```text
apps/web/                 Next.js App Router
apps/api/                 NestJS API and dependency health check
packages/                 Reserved for future shared packages
infra/compose.dev.yml     Local PostgreSQL + Redis
infra/postgres/           Fresh-database initialization
scripts/smoke.mjs         End-to-end infrastructure and app smoke test
.env.example              Local environment template
pnpm-lock.yaml            Reproducible dependency resolution
```

Production Dockerfiles, Compose, Caddy HTTPS configuration, GitHub Actions and backup/rollback scripts are prepared. See [the VPS deployment runbook](docs/DEPLOYMENT.md) for the isolated local rehearsal and future VPS setup. No remote production deployment has been performed.

References: [Next.js installation](https://nextjs.org/docs/app/getting-started/installation), [NestJS first steps](https://docs.nestjs.com/first-steps), [pgvector](https://github.com/pgvector/pgvector).
