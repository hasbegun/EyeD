#!/bin/bash
# Create per-mode iris-engine2 databases and apply schema.
# eyed (prod) is already created by POSTGRES_DB / 01-init.sql.
# This script adds eyed_dev and eyed_test.
# Runs as part of PostgreSQL's /docker-entrypoint-initdb.d/ on first startup.
set -e

PGUSER="${POSTGRES_USER:-eyed}"

for DB in eyed_dev eyed_test; do
    echo "Creating $DB database..."
    psql -v ON_ERROR_STOP=1 --username "$PGUSER" <<-EOSQL
        CREATE DATABASE $DB;
EOSQL
    echo "Applying schema to $DB..."
    psql -v ON_ERROR_STOP=1 --username "$PGUSER" -d "$DB" \
        -f /docker-entrypoint-initdb.d/01-init.sql
    echo "$DB database ready."
done
