# Database Upgrades

This document explains how major version upgrades are handled for databases
running in this repo, and what to expect when new versions are released.

---

## PostgreSQL

### Strategy

PostgreSQL upgrades use [pgautoupgrade](https://github.com/pgautoupgrade/docker-pgautoupgrade),
a wrapper around `pg_upgrade` that runs automatically as a one-shot container
before the main database starts.

Each stack that uses Postgres follows this service dependency chain:

```text
gatus-db-upgrade  (pgautoupgrade, restart: "no")
       ↓ service_completed_successfully
gatus-db          (postgres, restart: always)
       ↓ service_healthy
gatus / gatus-db-backup
```

The upgrade container detects the existing data directory version, upgrades in
place using `--link` (hardlinks, not a full copy), then exits. The main Postgres
container only starts after the upgrade has completed successfully.

Because `PGAUTO_ONESHOT=yes` is set, the upgrade container exits immediately
after finishing. It is idempotent — if the data is already at the target version,
it exits cleanly without doing anything.

### Volume mount layout (Postgres 18+)

Starting with Postgres 18, the official image changed the expected data
directory from `/var/lib/postgresql/data` to `/var/lib/postgresql/<MAJOR>/docker`.
A symlink from `/var/lib/postgresql/data` to `/var/lib/postgresql` was added by
the image, which causes a conflict when mounting a directory directly to
`/var/lib/postgresql/data`.

**All Postgres stacks in this repo therefore mount the data directory at
`/var/lib/postgresql`** (the parent), not at `.../data`. This allows:

- The Postgres image to create the correct major-version subdirectory.
- pgautoupgrade to auto-discover the existing installation and upgrade it
  to a new subdirectory (e.g., `18/docker` → `19/docker`).
- Future upgrades to be fully automatic with no manual intervention.

Example compose excerpt:

```yaml
gatus-db:
  image: docker.io/library/postgres:18.x-alpine@sha256:...
  volumes:
    - ./data/db:/var/lib/postgresql   # Parent mount, not .../data

gatus-db-upgrade:
  image: pgautoupgrade/pgautoupgrade:18.x-alpine@sha256:...
  environment:
    - PGAUTO_ONESHOT=yes
    # PGDATA is intentionally omitted — pgautoupgrade auto-discovers
    # the installation by scanning /var/lib/postgresql/
  volumes:
    - ./data/db:/var/lib/postgresql
```

### Routine upgrade (e.g., 18.x → 19.x)

1. Merge the Renovate PR that bumps both image tags:
   - `postgres:<NEW>-alpine` in the main DB service
   - `pgautoupgrade/pgautoupgrade:<NEW>-alpine` in the upgrade service
   - Both must use the **same major version**.
2. Redeploy — the upgrade runs automatically on startup.

No manual steps are required.

### One-time migration: pre-18 flat layout to 18+ subdirectory layout

If a stack was originally created on Postgres 17 or earlier (data stored flat in
`/var/lib/postgresql/data`) and is being upgraded to 18+ for the first time,
a one-time manual restructure is needed **after** pgautoupgrade runs but
**before** the Postgres 18 container is started. Run the following on the host:

```bash
docker run --rm -v ${BASE_DIR}/src/<stack>/data/db:/pgvol alpine sh -c \
  'mkdir -p /pgvol/<NEW_MAJOR>/docker && cd /pgvol && \
   mv $(ls -A | grep -v "^<NEW_MAJOR>$") <NEW_MAJOR>/docker/'
```

For example, for `gatus` upgrading to 18:

```bash
docker run --rm -v /mnt/vm-pool/apps/src/gatus/data/db:/pgvol alpine sh -c \
  'mkdir -p /pgvol/18/docker && cd /pgvol && mv $(ls -A | grep -v "^18$") 18/docker/'
```

Then update the compose file to mount at `/var/lib/postgresql` instead of
`/var/lib/postgresql/data` (and remove any explicit `PGDATA` from the upgrade
container). This is a one-time operation — all subsequent upgrades are automatic.

### Deployment timeout

Because pgautoupgrade can take 30+ seconds on a major version upgrade, the
`dccd.sh` script `WAIT_TIMEOUT` is set to 120s. The `gatus-db` healthcheck uses
a `start_period` of 30s to give Postgres time to complete post-upgrade recovery
before health checks start counting.
