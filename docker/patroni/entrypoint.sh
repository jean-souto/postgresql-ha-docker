#!/bin/sh
set -e

# Ensure data directory has correct permissions (run as root)
DATA_DIR="/var/lib/postgresql/data"
mkdir -p "$DATA_DIR"
chown -R postgres:postgres "$DATA_DIR"
chmod 700 "$DATA_DIR"

# Create a temporary directory for the configuration
CONFIG_DIR=$(mktemp -d)
chown postgres:postgres "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/patroni.yml"

# Define the variables to be substituted
VARS_TO_SUBST='${PATRONI_NAME} ${REPLICATION_PASSWORD} ${POSTGRES_PASSWORD} ${PATRONI_SCOPE} ${PATRONI_ETCD_HOSTS}'

# Generate patroni.yml by piping a here-document with variable placeholders to envsubst
# Using 'EOF' prevents the shell from expanding variables in the here-document itself.
envsubst "$VARS_TO_SUBST" > "$CONFIG_FILE" <<'EOF'
bootstrap:
  dcs:
    postgresql:
      use_pg_rewind: true
      use_slots: true
  initdb:
  - auth-host: md5
  - auth-local: trust
  - encoding: UTF8
  - locale: en_US.UTF-8
  - data-checksums
  pg_hba:
  - host all all 0.0.0.0/0 md5
  - host replication all 0.0.0.0/0 md5

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${PATRONI_NAME}:8008

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${PATRONI_NAME}:5432
  data_dir: /var/lib/postgresql/data
  authentication:
    replication:
      username: replicator
      password: ${REPLICATION_PASSWORD}
    superuser:
      username: postgres
      password: ${POSTGRES_PASSWORD}
  parameters:
    hot_standby: "on"
    wal_level: replica
    wal_log_hints: 'on'
    max_wal_senders: 10
    max_replication_slots: 10
    wal_keep_size: 2048

scope: ${PATRONI_SCOPE}
name: ${PATRONI_NAME}

etcd3:
  hosts: ${PATRONI_ETCD_HOSTS}
  protocol: http
EOF

# Ensure config file is owned by postgres
chown postgres:postgres "$CONFIG_FILE"

# Start Patroni as postgres user
exec su-exec postgres patroni "$CONFIG_FILE"
