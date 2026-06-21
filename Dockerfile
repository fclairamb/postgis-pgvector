# syntax=docker/dockerfile:1
#
# postgis-pgvector — PostgreSQL + PostGIS + pgvector in a single image.
#
# Base image: the official postgis/postgis image (PostgreSQL + PostGIS).
# pgvector is compiled from a pinned source tag on top of it.
#
# Versioning is handled by CI, not here: the released image version mirrors the
# PostgreSQL version (MAJOR.MINOR) with our own auto-incrementing patch — e.g.
# 18.0.0, 18.0.1, … — and the patch resets to 0 whenever PostgreSQL's version
# moves. See .github/workflows/release.yml and README.md.
#
# Renovate keeps everything current (see renovate.json):
#   * the base image tag + digest (the digest captures PostgreSQL patch releases)
#   * the pinned pgvector version below
#   * the GitHub Actions used by CI

FROM postgis/postgis:18-3.6

# pgvector release to build. Kept up to date by Renovate (see renovate.json).
# renovate: datasource=github-tags depName=pgvector/pgvector
ARG PGVECTOR_VERSION=0.8.3

# Compile and install pgvector against the image's PostgreSQL, then remove the
# build toolchain so it doesn't bloat the final image. JIT bitcode is disabled
# (with_llvm=no) to avoid LLVM/clang version-matching headaches — it has no
# effect on vector query correctness.
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        postgresql-server-dev-18 \
    ; \
    git clone --branch "v${PGVECTOR_VERSION}" --depth 1 \
        https://github.com/pgvector/pgvector.git /tmp/pgvector; \
    cd /tmp/pgvector; \
    make OPTFLAGS="" with_llvm=no; \
    make OPTFLAGS="" with_llvm=no install; \
    cd /; \
    rm -rf /tmp/pgvector; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# Auto-enable the `vector` extension in the default database on first
# initialisation, mirroring how the base image auto-enables PostGIS.
# (Any other database still needs its own `CREATE EXTENSION vector;`.)
COPY docker-entrypoint-initdb.d/20-pgvector.sh /docker-entrypoint-initdb.d/20-pgvector.sh
