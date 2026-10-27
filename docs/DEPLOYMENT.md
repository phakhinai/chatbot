# VPS deployment runbook

## Current scope

The repository contains buildable production Dockerfiles, a separate Compose stack, Caddy reverse proxy, CI/CD, database/Redis backups and application rollback scripts. There is no provisioned VPS, configured GitHub remote, or real domain in this environment. No remote deployment, registry publication, or public TLS issuance has taken place. The application is a development skeleton; RAG, authentication, persistent queue workers and application migrations have not been implemented.

## Architecture

```text
Internet → Caddy :80/:443 → /api/* → NestJS :3001
                        → /*     → Next.js :3000
                                      ↓ internal HTTP to NestJS
                          NestJS → PostgreSQL + pgvector / Redis
```

Caddy strips `/api` before forwarding, so `/api/health` reaches NestJS `/health`. Only Caddy publishes host ports. Application containers run as the non-root Node user with a read-only root filesystem. Production database/cache volumes are separate from development. No Docker socket is mounted into an application. Logs rotate at 10 MB × 3 per service. Redis uses authentication, AOF and `noeviction`. Docker environment variables remain visible to administrators with Docker access; protect the VPS env file and Docker access accordingly.

Base images and production infrastructure images are pinned by digest. Update them deliberately with the lockfile/security maintenance process. CI publishes application images with a commit SHA tag and deploys the corresponding immutable digest; it never deploys `latest`. Docker builds exclude local env files and credentials.

## Local production rehearsal

From the repository root in an Ubuntu terminal with Docker access:

```bash
docker build -f apps/api/Dockerfile -t rag-chatbot-api:rehearsal .
docker build -f apps/web/Dockerfile -t rag-chatbot-web:rehearsal .
node scripts/prepare-rehearsal.mjs
docker compose --env-file .rehearsal/production.env -f infra/compose.prod.yml up -d --wait --wait-timeout 180
bash scripts/deploy/verify.sh .rehearsal/production.env
bash scripts/deploy/backup.sh .rehearsal/production.env
# Use the postgres.dump path printed by backup.sh:
bash scripts/deploy/restore-check.sh .rehearsal/production.env /absolute/path/to/postgres.dump
```

Browse http://localhost:8080 and http://localhost:8080/api/health. This is deliberately HTTP on loopback; it does not request a certificate. The normal dev applications remain on ports 3000/3001. `.rehearsal/production.env` is generated once with distinct random credentials and ignored by Git.

Stop the rehearsal with the following command; data is preserved:

```bash
docker compose --env-file .rehearsal/production.env -f infra/compose.prod.yml down
```

Do not use `down -v` on an environment containing data. Docker builds target Linux; the GitHub runner builds linux/amd64. An ARM VPS needs images built/tested for linux/arm64 before use.

## Repository and GitHub setup (when ready)

Use one private monorepo, branch `main`, feature branches and pull requests. Keep source, infrastructure, lockfile, workflow and documentation together. Commit `.env.example` and `.env.production.example`, never live env files, keys, backups or database files. No initial commit or remote has been created automatically in this session.

From your Ubuntu terminal after reviewing the files and creating an empty GitHub repository:

```bash
git add .
git diff --cached --check
git diff --cached --stat
git commit -m "Prepare RAG chatbot development and deployment environment"
git branch -M main
git remote add origin git@github.com:YOUR_ORG/YOUR_REPO.git
git push -u origin main
```

The first `main` workflow run tests and publishes images to GHCR. The workflow also tests PRs and `master`, but only `main` publishes/deploys. Ensure Actions are enabled and the repository's token can write its GHCR packages. Use branch protection requiring the verification job. Deploy remains disabled until repository variable `ENABLE_VPS_DEPLOY` is set to `true`.

Workflow sequence: frozen dependency install → TypeScript/shell checks → production image build → isolated integration test → backup/restore drill → publish tested images → optional VPS deploy. The production job uses the `production` GitHub environment; configure reviewers only if your operational policy needs them. A CI failure prevents publication and deployment. No CI run has yet executed on GitHub.

## Prepare a future VPS

Suggested starting point for this stack using an external AI API: Ubuntu LTS, 2–4 vCPU, at least 4 GB RAM and sufficient SSD for PostgreSQL, Docker images and backups. Size by actual corpus, vector dimensions and concurrency; local model hosting requires a separate capacity assessment.

Before deploying, provision Docker Engine with the Compose plugin using the official Ubuntu instructions. The host also needs Bash, curl, Python 3, tar, util-linux (`flock`) and SSH. Create a deployment user with explicitly authorized Docker access and ownership of `/opt/rag-chatbot`; Docker access is an administrative capability. No host packages, firewall rules or user permissions are changed by this repository's deployment script.

Prepare these directories as the deployment user after their ownership is configured:

```bash
mkdir -p /opt/rag-chatbot/releases /opt/rag-chatbot/backups
chmod 700 /opt/rag-chatbot/backups
```

Place a copy of `.env.production.example` at `/opt/rag-chatbot/.env.production` with permissions `600`. The production scripts accept plain, **unquoted** `KEY=value` values and never execute the env file as shell code. Generate two different passwords with `openssl rand -hex 24` and fill in the PostgreSQL and Redis values. Passwords must contain at least 32 hex characters so URLs do not need escaping. Keep `POSTGRES_USER` and `POSTGRES_DB` as lowercase SQL identifiers. Editing env credentials does not rotate passwords in an existing PostgreSQL volume.

Set `SITE_ADDRESS=chat.yourdomain.com`, `WEB_ORIGIN=https://chat.yourdomain.com`, a real `ACME_EMAIL`, image references and a private absolute `BACKUP_DIR`. Keep the project name `rag-chatbot-prod` stable across releases so volumes are reused. Restrict SSH access and allow inbound 80/tcp and 443/tcp (443/udp is optional HTTP/3). Do not publish PostgreSQL/Redis/API ports. Verify Docker port publishing alongside the provider firewall rather than relying only on UFW.

If GHCR packages are private, run `docker login ghcr.io` on the VPS as the deployment user with a separately managed read-only package credential. Do not store a registry token in the repo or send it in chat. Never reuse a GitHub Actions job token as a persistent VPS credential.

## DNS and HTTPS

Create an A record for the chosen hostname pointing to the VPS IPv4 address. Add AAAA only if the VPS really has working public IPv6. Check DNS resolution and reachability of ports 80/443 before first deploy. Avoid enabling CDN proxying during the first certificate test unless its validation behavior has been deliberately configured.

A bare domain in `SITE_ADDRESS` enables Caddy automatic certificate management and HTTP→HTTPS redirects. Persistent `caddy_data` stores certificates and keys; retain it across releases. Public HTTPS/certificate renewal cannot be verified until a real VPS/domain exists. After provisioning, check both HTTP redirect and HTTPS readiness:

```bash
curl -I http://chat.yourdomain.com
curl --fail https://chat.yourdomain.com/api/health
```

## Enable CI deployment

In the repository's `production` environment, configure these secrets:

| Secret | Value |
|---|---|
| `VPS_HOST` | Hostname or IPv4, no protocol |
| `VPS_USER` | Deployment user |
| `VPS_PORT` | SSH port, normally 22 |
| `VPS_SSH_KEY` | Dedicated deployment private key |
| `VPS_KNOWN_HOSTS` | Verified SSH known_hosts entry; use `[host]:port` for a nonstandard port |

Verify the host fingerprint through the VPS console/trusted channel before storing it; the workflow uses strict host-key verification. It does not run blind `ssh-keyscan`. Set repository variable `ENABLE_VPS_DEPLOY=true` only after the VPS/env/DNS/registry access are ready. Then push to `main` or dispatch the workflow on `main`.

The workflow sends only infrastructure and deployment scripts to `/opt/rag-chatbot/releases/<commit-sha>/`. App images are pulled by digest. Deployment checks the Compose config, pulls missing immutable images, backs up an existing stack, starts services and verifies public API/frontend routes. It saves image digests and the release's Compose path in `.deploy-state` next to the VPS env file. Retain release directories and images required for rollback.

This is a single-host rolling replacement, with possible brief downtime. It is not blue/green or high availability. There are no application migrations yet. Before adding schema changes, introduce versioned migrations with a tested compatibility policy; automatic image rollback must not attempt to reverse destructive migrations.

## Backups and recovery

```bash
bash /opt/rag-chatbot/releases/COMMIT/scripts/deploy/backup.sh /opt/rag-chatbot/.env.production
bash /opt/rag-chatbot/releases/COMMIT/scripts/deploy/restore-check.sh /opt/rag-chatbot/.env.production /absolute/path/to/postgres.dump
```

Backup creates a private timestamped directory containing a PostgreSQL custom-format dump (including vectors), a validated Redis RDB snapshot and `SHA256SUMS`. A failed backup prevents deployment; partial backup directories must not be treated as valid. Verify checksums from within a completed backup directory with `sha256sum -c SHA256SUMS`. Restore checking creates a new scratch database, restores with errors treated as fatal, checks pgvector and removes only that scratch database. It never restores over the live database.

PostgreSQL and Redis snapshots are taken sequentially, so they are not a single cross-service transaction. Future queue processing must be idempotent and recover interrupted jobs. Do not treat Redis as the sole source of durable business records.

Schedule a daily backup after the VPS exists, using absolute paths and a stable copy of the scripts or the current release path. Suggested retention: 7 daily and 4 weekly copies, plus an encrypted off-host copy. No cron jobs, off-host credentials or automatic backup deletion have been configured. Local copies alone do not protect against loss of the VPS. Select storage, retention and recovery targets before launch.

A live restore requires an explicit maintenance window and approval: stop application writers, verify the backup and target, preserve the current data, restore PostgreSQL and Redis to the intended volumes, then validate and resume. This repository deliberately provides a scratch restore drill rather than an automatic overwrite of production data.

## Rollback

After at least two successful deployments:

```bash
bash /opt/rag-chatbot/releases/CURRENT_COMMIT/scripts/deploy/release.sh /opt/rag-chatbot/.env.production rollback
```

Rollback uses the previous successful images **and Compose file path**, backs up the running database/cache first, and verifies readiness before updating saved state. Failed deploys automatically attempt the last successful configuration. Failure during image preflight leaves running services untouched. The first release has no predecessor; a failed first deploy reports the failure and preserves volumes for inspection. Failed automatic recovery exits with code 2 and requires operator investigation.

Rollback restores application/configuration, not database contents, host env values or secrets. Keep env/schema changes backward compatible. Never use volume deletion as rollback. Inspect service status and relevant logs if recovery fails; do not publish logs containing secrets or application data.

## Sources

- [Docker Compose in production](https://docs.docker.com/compose/how-tos/production/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https)
- [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [GitHub deployment environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments)

- [Official checkout action](https://github.com/actions/checkout)
- [Official setup-node action](https://github.com/actions/setup-node)
