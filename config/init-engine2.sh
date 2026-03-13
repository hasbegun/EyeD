#!/bin/bash
# Create eyed2 database for iris-engine2 and apply the same schema.
# Runs as part of PostgreSQL's /docker-entrypoint-initdb.d/ on first startup.
set -e

PGUSER="${POSTGRES_USER:-eyed}"

echo "Creating eyed2 database..."
psql -v ON_ERROR_STOP=1 --username "$PGUSER" <<-EOSQL
    CREATE DATABASE eyed2;
EOSQL

echo "Applying schema to eyed2..."
psql -v ON_ERROR_STOP=1 --username "$PGUSER" -d eyed2 \
    -f /docker-entrypoint-initdb.d/01-init.sql

echo "eyed2 database ready."
