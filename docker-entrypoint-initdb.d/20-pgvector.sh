#!/bin/bash
# Auto-enable pgvector in the default database, the same way the base image
# auto-enables PostGIS. Runs only on first container initialisation (i.e. when
# the data directory is empty).
set -e

psql -v ON_ERROR_STOP=1 \
    --username "${POSTGRES_USER:-postgres}" \
    --dbname "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" <<-'EOSQL'
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
