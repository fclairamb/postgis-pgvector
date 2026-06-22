# postgis-pgvector

PostgreSQL **18** with both [PostGIS](https://postgis.net/) and
[pgvector](https://github.com/pgvector/pgvector) in a single image — the two
extensions the official images never ship together.

It's a thin layer on top of [`imresamu/postgis`](https://hub.docker.com/r/imresamu/postgis)
— the multi-arch (`amd64` + `arm64`) build of the official `docker-postgis`
image: pgvector is compiled from a pinned source tag, and that's it. Everything
else (PostgreSQL, PostGIS, the entrypoint, env vars, volume layout) is exactly
the upstream image, so all of its documentation applies.

```
ghcr.io/fclairamb/postgis-pgvector
```

## Quick start

```bash
docker run -d --name pg \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ghcr.io/fclairamb/postgis-pgvector:18
```

Both extensions are enabled in the default database out of the box:

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

## Tags & versioning

The release version mirrors **PostgreSQL's** version, and our own builds only
ever move the **patch** digit:

```
<PG_MAJOR>.<PG_MINOR>.<patch>
        18  .  0      .  3
        │       │         └─ our build counter — auto-incremented every release
        │       └─────────── PostgreSQL minor (e.g. 18.1), owned by upstream
        └─────────────────── PostgreSQL major, owned by upstream
```

PostgreSQL only uses two numbers (`18.0`, `18.1`, …), which leaves the third
free for us. When PostgreSQL releases a new version the first two digits follow
it and the patch resets to `0`.

| Tag         | Meaning                                              | Moves?     |
|-------------|------------------------------------------------------|------------|
| `18.0.3`    | One exact, immutable build                           | never      |
| `18.0`      | Latest patch for PostgreSQL 18.0                      | moving     |
| `18`        | Latest build for PostgreSQL 18.x                     | moving     |
| `latest`    | Latest build, period                                 | moving     |

Pin `18` (or `18.0`) in production for automatic security patches without
surprise major upgrades; pin `18.0.3` if you need a frozen, reproducible image.

## How it stays up to date

Two automated pieces, both hands-off:

### Renovate
[`renovate.json`](renovate.json) keeps the inputs current and **auto-merges**:

- the **base image** tag **and digest** — the digest pin is what pulls in new
  PostgreSQL/PostGIS patch builds (security fixes) automatically;
- the **pgvector** source tag pinned in the [`Dockerfile`](Dockerfile) (tracked
  via the `github-tags` datasource — pgvector ships tags, not GitHub Releases);
- the **GitHub Actions** used by CI.

Non-major updates auto-merge. **Major** bumps (PostgreSQL 18 → 19, PostGIS
3.x → 4.x, pgvector 0.x → 1.x) open a PR for you to review instead — flip the
relevant `matchUpdateTypes` in `renovate.json` if you'd rather those auto-merge
too.

### Release CI
[`.github/workflows/release.yml`](.github/workflows/release.yml) runs when an
image input changes on `main` (e.g. a Renovate merge), weekly on a schedule,
or on demand. Each run:

1. reads the actual PostgreSQL `MAJOR.MINOR` straight from the base image,
2. computes the next version (`MAJOR.MINOR.<previous patch + 1>`),
3. builds **multi-arch** (`linux/amd64` + `linux/arm64`) and pushes all four
   tags above to GHCR, and
4. cuts a matching GitHub release + git tag.

The weekly run exists so Debian/pgvector security updates land even when none of
our files changed — every rebuild becomes a fresh patch release.

## One-time repo setup

1. **Enable the [Renovate app](https://github.com/apps/renovate)** on this repo.
   It needs no secrets, and — unlike a self-hosted run using `GITHUB_TOKEN` —
   its auto-merges *do* trigger the release workflow, so upgrades flow straight
   through to a published image.
2. **Confirm the GHCR package is public.** It published as public automatically
   here (anonymous `docker pull` works), but if your account defaults differ,
   flip it at *package page → Package settings → Change visibility → Public*.

## What's inside

- **PostgreSQL 18** + **PostGIS 3.6** — from `imresamu/postgis:18-3.6`, the
  multi-arch build of the official PostGIS image
- **pgvector** — compiled from source, version pinned in the `Dockerfile`
  (JIT bitcode disabled; no effect on query results)
- **Architectures** — `linux/amd64` and `linux/arm64`

## Licensing

The packaging in this repo is [MIT](LICENSE). The image bundles PostgreSQL,
PostGIS, and pgvector, each under its own license.
