#!/usr/bin/env bash
set -euo pipefail

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "Bootstrapping passive PostgreSQL node from active node..."
  rm -rf "$PGDATA"/*

  until pg_isready -h postgres-active -p 5432 -U postgres >/dev/null 2>&1; do
    sleep 2
  done

  echo "postgres-active:5432:*:${REPLICATION_USER}:${REPLICATION_PASSWORD}" > /var/lib/postgresql/.pgpass
  chmod 600 /var/lib/postgresql/.pgpass
  chown postgres:postgres /var/lib/postgresql/.pgpass

  export PGPASSFILE=/var/lib/postgresql/.pgpass
  pg_basebackup \
    -h postgres-active \
    -p 5432 \
    -U "${REPLICATION_USER}" \
    -D "$PGDATA" \
    -R \
    -S passive_slot \
    -X stream \
    -v

  chown -R postgres:postgres "$PGDATA"
  chmod 700 "$PGDATA"
fi

exec docker-entrypoint.sh "$@"
