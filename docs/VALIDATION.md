# Environment validation — 2026-10-27

## Completed locally

| Check | Result |
|---|---|
| TypeScript for Next.js and NestJS | PASS |
| API production Docker build, including final Redis recovery changes | PASS |
| Next.js standalone production Docker build | PASS |
| Separate development and production rehearsal Compose projects/volumes | PASS |
| Production app containers run as uid/gid 1000 | PASS |
| PostgreSQL connection and pgvector distance query | PASS |
| Production Redis authentication and PING | PASS |
| BullMQ job enqueue, processing and result | PASS in development and production rehearsal |
| Caddy configuration validation and HTTP reverse proxy | PASS |
| Frontend page calls internal API and renders Connected | PASS |
| PostgreSQL custom dump and validated Redis RDB backup | PASS |
| Backup SHA256 checksums | PASS |
| Restore latest PostgreSQL dump into new scratch database, pgvector query, scratch cleanup | PASS |
| Successful release state tracking and manual rollback | PASS |
| Deliberately broken web image rejected and automatic recovery to previous successful release | PASS |
| Redis outage produces API 503; reconnect returns 200 without restarting API | PASS |
| YAML structure, deployment Bash syntax and workflow embedded shell syntax | PASS |
| Git ignores live env/backup/rehearsal files; env permissions 600 | PASS |
| Generated private passwords absent from publishable files | PASS |
| Original development stack smoke test after deployment drills | PASS |

The rollback drill used two image labels for the same built application to test release/state/Compose recovery. It does not prove backward compatibility between future code versions, database migrations or changed credentials. A separate intentionally invalid web image tested the failure path. No live application data or production host was involved.

Caddy's warning that automatic HTTPS is disabled in the local HTTP rehearsal is expected. The rehearsal deliberately uses `http://localhost` and does not obtain a certificate.

## Remaining external checks

- No VPS has been provisioned (confirmed by the user).
- Git has no configured remote or initial commit. No GitHub repository was created or pushed.
- GitHub Actions configuration was checked locally; it has not run on GitHub, published images or connected to a VPS.
- Public DNS, SSH, VPS firewall, GHCR access, HTTPS issuance and renewal remain unverified.
- Daily backup scheduling, encrypted off-host backup storage, retention and a real disaster recovery drill remain to be configured once infrastructure exists.
- RAG functionality, authentication, business schema/migrations and persistent queue workers are outside this environment setup.

## Services left running

- Development frontend: http://localhost:3000
- Development API: http://localhost:3001/health
- Production rehearsal frontend: http://localhost:8080
- Production rehearsal API through Caddy: http://localhost:8080/api/health

Development and rehearsal infrastructure use separate named volumes. Database/cache/API ports for the rehearsal are not published on the host. Only the proxy publishes loopback ports 8080 and 8443. Credentials, backup contents and deployment state are private/ignored. Stop the rehearsal without deleting its data using the command in [DEPLOYMENT.md](DEPLOYMENT.md).
