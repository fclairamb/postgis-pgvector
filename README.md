# postgis-pgvector

PostgreSQL **18** with both [PostGIS](https://postgis.net/) and
[pgvector](https://github.com/pgvector/pgvector) in a single image — the two
extensions the official images never ship together — **built from a pinned
Debian snapshot** for reproducible, self-contained builds.

```
ghcr.io/fclairamb/postgis-pgvector
```

Multi-arch: `linux/amd64` + `linux/arm64`.

## Quick start

```bash
docker run -d --name pg \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ghcr.io/fclairamb/postgis-pgvector:18
```

PostGIS and pgvector are enabled in the default database (and in
`template_postgis`) out of the box:

```sql
SELECT postgis_full_version();
SELECT extversion FROM pg_extension WHERE extname IN ('postgis', 'vector');
```

For any **other** database, enable them yourself:

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS vector;
```

There's a [`docker-compose.yml`](docker-compose.yml) with a persistent volume
and a healthcheck.

> [!IMPORTANT]
> **PostgreSQL 18 changed the data directory.** The persistent volume now mounts
> at `/var/lib/postgresql` (it was `/var/lib/postgresql/data` on 17 and earlier).
> If you're migrating an existing setup, update your volume mount or Postgres
> will come up with an empty data directory.

## How it's built

Instead of layering on a prebuilt `postgres`/`postgis` image, the
[`Dockerfile`](Dockerfile) **reconstructs the stack on a pinned Debian
snapshot** (`debian:trixie-20260623-slim`):

1. the official [`postgres`](https://github.com/docker-library/postgres) image
   (18/trixie) — PostgreSQL from the PGDG apt repo, plus gosu, locale, the
   `postgres` user and the entrypoint — vendored verbatim (trimmed to the
   amd64/arm64 binary path);
2. PostGIS, the way [`docker-postgis`](https://github.com/postgis/docker-postgis)
   (18-3.6) does — `postgresql-18-postgis-3` from PGDG + its init/upgrade scripts;
3. pgvector, compiled from a pinned source tag.

The upstream entrypoint and init scripts are checked into this repo verbatim
(`docker-entrypoint.sh`, `docker-ensure-initdb.sh`, `initdb-postgis.sh`,
`update-postgis.sh`) so behaviour matches the official images exactly.

## Tags & versioning

The release version mirrors **PostgreSQL's** version, and our own builds only
ever move the **patch** digit:

```
<PG_MAJOR>.<PG_MINOR>.<patch>
        18  .  4      .  0
        │       │         └─ our build counter — incremented every release
        │       └─────────── PostgreSQL minor (e.g. 18.4), from PG_VERSION
        └─────────────────── PostgreSQL major
```

PostgreSQL only uses two numbers (`18.4`, `18.5`, …), which leaves the third
free for us. CI reads `PG_VERSION` from the Dockerfile, and the patch resets to
`0` whenever that MAJOR.MINOR changes.

| Tag         | Meaning                                   | Moves?  |
|-------------|-------------------------------------------|---------|
| `18.4.0`    | One exact, immutable build                | never   |
| `18.4`      | Latest patch for PostgreSQL 18.4          | moving  |
| `18`        | Latest build for PostgreSQL 18.x          | moving  |
| `latest`    | Latest build, period                      | moving  |

## Pinning & reproducibility

Every input is pinned in the Dockerfile:

| Input        | Pinned as                          | Updated by |
|--------------|------------------------------------|------------|
| Debian base  | `FROM debian:trixie-20260623-slim` | Renovate (digest + newer snapshots) |
| PostgreSQL   | `ENV PG_VERSION` (PGDG apt version)| **manual** bump |
| PostGIS      | `ENV POSTGIS_VERSION` (PGDG apt)   | **manual** bump |
| gosu         | `ENV GOSU_VERSION`                 | Renovate |
| pgvector     | `ARG PGVECTOR_VERSION` (source tag)| Renovate |
| GitHub Actions | workflow `uses:`                 | Renovate |

To move PostgreSQL or PostGIS, edit `PG_VERSION` / `POSTGIS_VERSION` to a
version available in the [PGDG `trixie-pgdg`](https://apt.postgresql.org/pub/repos/apt/dists/trixie-pgdg/)
repo and commit — CI cuts the matching release. (They're bumped by hand because
Renovate can't reliably track PGDG apt version strings.)

> Note: pinning the Debian *image* freezes the base layer, but `apt-get install`
> still resolves against the live Debian/PGDG mirrors at build time. For
> bit-for-bit reproducibility you'd additionally pin a `snapshot.debian.org`
> sources list — out of scope here.

## How it stays up to date

[`renovate.json`](renovate.json) auto-merges non-major updates to the Debian
base image (digest + newer dated snapshots), gosu, pgvector, and the GitHub
Actions. **Major** bumps (Debian release, pgvector `0.x → 1.x`, …) open a PR for
you to review. A Renovate merge → push to `main` → the release workflow
([`.github/workflows/release.yml`](.github/workflows/release.yml)) rebuilds
multi-arch, pushes all four tags to GHCR, and cuts a GitHub release. You can
also trigger it manually (`workflow_dispatch`).

## One-time repo setup

**Enable the [Renovate app](https://github.com/apps/renovate)** on this repo
(no secrets needed; its auto-merges trigger the release workflow). The GHCR
package is already public — anonymous `docker pull` works.

## What's inside

- **Debian** — `debian:trixie-20260623-slim` (pinned)
- **PostgreSQL 18** — `PG_VERSION` from PGDG
- **PostGIS 3.6** — `POSTGIS_VERSION` from PGDG
- **pgvector** — compiled from source (`PGVECTOR_VERSION`; JIT bitcode disabled,
  no effect on query results)

## Licensing

The packaging in this repo is [MIT](LICENSE). The image bundles Debian,
PostgreSQL, PostGIS, and pgvector, each under its own license.
