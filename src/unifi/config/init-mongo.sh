#!/bin/bash
# Creates the Unifi application user in MongoDB.
# Runs only on first container initialization (when /data/db is empty).
# The root user is created automatically via MONGO_INITDB_ROOT_USERNAME/PASSWORD.

set -e

if command -v mongosh > /dev/null 2>&1; then
  mongo_init_bin='mongosh'
else
  mongo_init_bin='mongo'
fi

"${mongo_init_bin}" <<EOF
use ${MONGO_AUTHSOURCE}
db.auth("${MONGO_INITDB_ROOT_USERNAME}", "${MONGO_INITDB_ROOT_PASSWORD}")
db.createUser({
  user: "${MONGO_USER}",
  pwd: "${MONGO_PASS}",
  roles: [
    { db: "${MONGO_DBNAME}", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_stat", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_audit", role: "dbOwner" }
  ]
})
db.grantRolesToUser("${MONGO_USER}", [{ role: "clusterMonitor", db: "${MONGO_AUTHSOURCE}" }]);
EOF
