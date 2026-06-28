#!/bin/bash
# Auto-enable pgvector on first initialisation, after PostGIS (10_postgis.sh).
# Loads `vector` into template_postgis and the default database, mirroring how
# the PostGIS init script seeds those two. Other databases still need their own
# `CREATE EXTENSION vector;`.
set -e

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"

for DB in template_postgis "$POSTGRES_DB"; do
	echo "Loading pgvector extension into $DB"
	psql -v ON_ERROR_STOP=1 --dbname="$DB" <<-'EOSQL'
		CREATE EXTENSION IF NOT EXISTS vector;
	EOSQL
done
