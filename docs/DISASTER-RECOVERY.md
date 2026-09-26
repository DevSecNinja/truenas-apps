# Disaster Recovery

This document walks through rebuilding the Docker Compose app stack from scratch on a fresh or reinstalled TrueNAS system. It assumes the git repo and SOPS Age key are available (either from a backup or from another machine). For the backup strategy that produces the snapshots, replicas, and off-site copies referenced below, see [Backup Strategy](BACKUP.md).

---

## Prerequisites

Before starting, ensure you have:

- A working TrueNAS installation with Docker support enabled
- Access to this git repository (GitHub)
- The **Age private key** (`age.key`) used for SOPS decryption — without this, secrets cannot be decrypted and no app will deploy. If the key is lost, every `secret.sops.env` must be re-encrypted with a new key
- (Optional) ZFS snapshots or replication backups of app datasets for data restoration
- For personal homes: the saved TrueNAS configuration with password secret
  seed, secure UID/GID, quota, and share/ACL inventory, shared home dataset unlock keys,
  SSH access recovery material, and backup decryption credentials

---

## Step 1: Create ZFS Datasets

Recreate the dataset hierarchy in the TrueNAS UI. Each app gets its own child dataset for independent snapshots and replication.

**Enable encryption on the `vm-pool/apps` dataset** when creating it. Use the TrueNAS encryption wizard to select a passphrase or key. Store the encryption passphrase/key in a secure, offline location (e.g., a password manager or printed copy) — without it, the dataset cannot be unlocked after a reboot or reinstall. Child datasets inherit encryption from the parent.

```text
vm-pool/apps              # root — holds the git repo
vm-pool/apps/services          # parent for all app datasets
vm-pool/apps/services/adguard
vm-pool/apps/services/echo-server
vm-pool/apps/services/gatus
vm-pool/apps/services/homepage
vm-pool/apps/services/immich
vm-pool/apps/services/metube
vm-pool/apps/services/plex
vm-pool/apps/services/traefik
vm-pool/apps/services/traefik-forward-auth
vm-pool/apps/services/unifi
vm-pool/homes             # One shared Multiprotocol dataset
  <username>/            # Ordinary personal home directory, not a dataset
```

`<username>` is a placeholder, not an account to create. Follow
[Personal Home Recovery](#personal-home-recovery) for native SSH/SMB homes:
restore the shared `homes` dataset from replication where available, or
recreate that one empty dataset with the **Multiprotocol** preset,
NFSv4/Passthrough ACLs, Sensitive case, Atime Off, Exec On, and automatic
SMB/NFS shares disabled before restoring all home directories. Do not create
datasets over populated directories. Existing per-user datasets need a separate
controlled migration, not deletion or an assumed merge into the shared parent.
`homes` does not inherit encryption from its `apps` sibling; recover its actual
shared encryption root and unlock keys separately.

### apps Dataset Permissions

**Wait until all child datasets have been created** before setting permissions. Even though `vm-pool/apps` inherits `truenas_admin` ownership when created, TrueNAS creates child datasets as `root:root` regardless of the parent's permissions.

After all datasets exist, set Unix permissions on `vm-pool/apps` using the TrueNAS **Unix Permissions Editor**:

| Setting | Value                    |
| ------- | ------------------------ |
| User    | `truenas_admin`          |
| Group   | `truenas_admin`          |
| User    | Read ✓ Write ✓ Execute ✓ |
| Group   | Read ✓ Write ✓ Execute ✓ |
| Other   | No permissions           |

Enable both **Apply permissions recursively** and **Apply permissions to child datasets**.

This ensures `truenas_admin` can manage the repo while decrypted `.env` files remain inaccessible to other users. Root does not need explicit permissions — it bypasses all permission checks.

---

## Step 2: Create Users and Groups

Every service runs as a dedicated non-root user. **Create groups first, then users** — if you rely on TrueNAS's "auto-create primary group" checkbox, it may assign a GID that does not match the UID.

### Shared Purpose Groups

Create these groups first since some service accounts reference them as their primary group:

> See the **Shared Purpose Groups** table in [INFRASTRUCTURE.md](INFRASTRUCTURE.md#shared-purpose-groups) for the full list of GIDs and their purpose.

For each shared group: create it in the TrueNAS UI with the designated GID. Add `truenas_admin` as an auxiliary member if admin access to those datasets is needed.

### App Service Accounts

For each app, follow this order:

1. Create group `svc-app-<name>` with the designated GID
2. Create user `svc-app-<name>` with the matching UID, primary group set to the group from step 1
3. Add `truenas_admin` to the group (grants group-write access to config files for `git pull`)

> See the **App Service Accounts** table in [INFRASTRUCTURE.md](INFRASTRUCTURE.md#app-service-accounts) for the full UID/GID allocation, user names, and which services each account covers.

### Group Memberships for Media and Private Access

Some service accounts need specific primary or auxiliary group memberships for media and private dataset access. See the [Shared Purpose Groups](INFRASTRUCTURE.md#shared-purpose-groups) and [Media Access](INFRASTRUCTURE.md#media-access) sections in INFRASTRUCTURE.md for the full membership configuration.

### Personal Home Identities

Restore personal users and their private primary groups with the **same
recorded UID/GID**, preferably from the saved TrueNAS configuration and
password secret seed. Keep their shares/logins disabled until data and
permissions have been checked. If recreating settings manually, use
[Personal Home Folders](HOME-FOLDERS.md), not the app service-account table;
retain SMB passwords and public-key-only SSH without sudo/admin privileges.
Do not move `truenas_admin` or its `/home/truenas_admin/host-init` mirror,
and do not give app/service accounts homes.

---

## Step 3: Clone the Repository

Because the ZFS datasets from Step 1 already created the directory tree, a normal `git clone` will refuse to run ("destination path already exists"). Instead, initialise the repo inside the existing directory and check out `main`:

```sh
cd /mnt/vm-pool/apps
git init -b main
git remote add origin git@github.com:DevSecNinja/truenas-apps.git
git pull origin main
```

This overlays the repo contents onto the existing dataset mount points without conflicting with them.

---

## Step 4: Restore the Age Key

Place the Age private key on the TrueNAS host at the expected path:

```sh
# Copy from backup or another machine
cp /path/to/backup/age.key /mnt/vm-pool/apps/age.key
chmod 600 /mnt/vm-pool/apps/age.key
chown truenas_admin:truenas_admin /mnt/vm-pool/apps/age.key
```

Verify decryption works by testing one file:

```sh
sops -d /mnt/vm-pool/apps/services/echo-server/secret.sops.env
```

---

## Step 5: Create Microsoft Entra ID App Registrations

Traefik Forward Auth uses Microsoft Entra ID (Azure AD) for SSO. Each server gets its **own app registration** for credential isolation — a compromised secret on one server cannot be used to authenticate against another.

Two registrations are needed:

| Server   | Auth Subdomain | App Registration Name (suggested) |
| -------- | -------------- | --------------------------------- |
| svlnas   | `auth`         | `traefik-forward-auth-svlnas`     |
| svlazext | `auth-ext`     | `traefik-forward-auth-svlazext`   |

### Create Each App Registration

Repeat these steps for each of the two servers:

1. Go to **[Azure Portal → Microsoft Entra ID → App registrations → New registration](https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps)**
2. **Name:** Use the suggested name from the table above
3. **Supported account types:** "Accounts in this organizational directory only (Single tenant)"
4. **Redirect URI:**
   - Platform: **Web**
   - URI: `https://<auth-subdomain>.<DOMAINNAME>/oauth2/callback`
     - svlnas: `https://auth.<DOMAINNAME>/oauth2/callback`
     - svlazext: `https://auth-ext.<DOMAINNAME>/oauth2/callback`
5. Click **Register**

### Generate Client Secrets

For each app registration:

1. Go to **Certificates & secrets → Client secrets → New client secret**
2. **Description:** e.g. `traefik-forward-auth`
3. **Expires:** Choose the maximum allowed (24 months), and set a calendar reminder to rotate before expiry
4. Copy the secret **Value** (not the Secret ID) — it is only shown once

### Collect the Values

For each registration, note these values (found on the **Overview** page):

| Variable              | Where to Find                                                |
| --------------------- | ------------------------------------------------------------ |
| `AZURE_TENANT_ID`     | Overview → Directory (tenant) ID — same for both             |
| `AZURE_CLIENT_ID`     | Overview → Application (client) ID — unique per registration |
| `AZURE_CLIENT_SECRET` | Certificates & secrets → the Value you just copied           |

### Store in SOPS Secret Files

Each server's credentials go into its own SOPS-encrypted file:

- svlnas → `services/traefik-forward-auth/secret.sops.env`
- svlazext → `services/traefik-forward-auth/secret.svlazext.sops.env`

Each file must contain (at minimum):

```env
DOMAINNAME=<your-domain>
MEM_LIMIT=300m
TRAEFIK_FORWARD_AUTH_SECRET=<random-64-char-hex-string>
AZURE_TENANT_ID=<your-tenant-id>
AZURE_CLIENT_ID=<per-server-client-id>
AZURE_CLIENT_SECRET=<per-server-client-secret>
```

Generate a unique `TRAEFIK_FORWARD_AUTH_SECRET` per server (used to sign session tokens):

```sh
openssl rand -hex 32
```

Encrypt new per-server files (the `.sops.yaml` rules will scope the Age keys automatically):

```sh
sops -e -i services/traefik-forward-auth/secret.svlazext.sops.env
```

### Add DNS Records

Create DNS A/CNAME records for each auth subdomain pointing to the correct server:

- `auth.<DOMAINNAME>` → svlnas IP
- `auth-ext.<DOMAINNAME>` → svlazext IP

---

## Step 6: Restore Data (Optional)

If you have ZFS snapshots or replication backups, restore them **before** deploying apps. See [Backup Strategy](BACKUP.md) for the full backup topology and restore procedures.

- **Cross-pool replica** — if the vm-pool SSD failed, restore from the archive-pool replica. See [Backup Strategy § Restore from Replica](BACKUP.md#restore-from-replica)
- **Per-app datasets** — restore snapshots for `vm-pool/apps/services/<app>` to recover `data/` directories (databases, state files, certificates)
- **App `data/` directories** — these are bind-mounted from `services/<app>/data/` within the `vm-pool/apps` dataset, so they are restored automatically when a ZFS snapshot of that dataset is restored alongside the compose files. No separate restoration step is needed
- **Database backups** — restore from `tiredofit/db-backup` dump files in each app's `backups/` directory. See [Backup Strategy § Restore a Database Dump](BACKUP.md#restore-a-database-dump)
- **Azure Blob off-site** — if both local pools are lost, pull encrypted backups from Azure. See [Backup Strategy § Restore from Azure Blob](BACKUP.md#restore-from-azure-blob)

If no backups are available, apps will start fresh — databases will be initialised empty and ACME certificates will be re-requested from Let's Encrypt.

### Personal Home Recovery

Personal files cannot be regenerated like app caches. If no home backup is
available, record the loss rather than treating a newly empty home as restored.

1. Preserve the early-boot administrative account and access. Import/unlock
   the required pool and actual shared home encryption root with the saved keys.
   A locked data-pool home cannot replace the administrative boot-time home.
2. Restore the **one `vm-pool/homes` dataset** from
   [replication](BACKUP.md#restore-from-replica), or recreate it empty following
   [Home Folders](HOME-FOLDERS.md#2-prepare-the-shared-dataset-once) before
   restoring files. Restore shared dataset properties, encryption, dataset
   quota, and recorded ownership-based user data/object quotas. Verify the
   root/admin-owned shared root's ACL: ordinary-user traversal only, no
   inheritance, no listing/create/delete/change-ACL rights or broad named
   grants. Inspect ancestor traversal without broad pool changes.
3. Recover all users' **ordinary directories**, including `Files` **and hidden
   SSH/configuration files**, initially with personal access disabled. For a
   cloud/file-copy restore, use an isolated target and the
   [home restore procedure](BACKUP.md#restore-home-files).
   Such copies might not preserve numeric owners or NFSv4 ACLs. For a single
   user's home or file, copy out selected files; **rollback of the shared
   dataset affects every user**.
4. Restore/edit each account's full existing home path with **Create Home
   Directory unchecked**: attaching a restored home is the exception to
   automatic new-home creation. Verify the saved path is exactly
   `/mnt/vm-pool/homes/<username>`, then perform the final folder/file
   ownership/ACL review after account saves. Preserve personal UID/GID;
   enforce owner-only home and `.ssh` `0700`, `authorized_keys` `0600`,
   and no broad/inherited access.
   Restore only approved public login keys; the client's private key stays
   on the client. Do not edit the dataset root as a substitute for each
   home's ACL or blanket-recursively chown/reset all homes.
5. Restore each ordinary private **Multi-protocol Share**, pointing only to
   that user's `Files` directory. Review that path through the share's
   **Edit Filesystem ACL**, verifying owner-only filesystem inheritance
   and a share ACL allowing only the personal user CHANGE, without
   overlapping home/parent exports.
6. Enable access only after the checks above. Run the
   [SSH/SMB positive and negative tests](HOME-FOLDERS.md#5-verify-before-use),
   verify service startup and post-reboot/unlock availability, and confirm
   cross-user denial locally and over SMB. Confirm renewed snapshots and
   replication of the shared dataset contain all home directories, plus
   off-site sync and sample restores for each user. Export a fresh system
   configuration with its password secret seed.

---

## Step 7: Configure Media and Private Dataset Permissions (If Applicable)

If the archive pool was also lost or reformatted, recreate the media and private dataset permissions. See [INFRASTRUCTURE.md § Media Access](INFRASTRUCTURE.md#media-access) for the Unix permissions setup for media datasets (`media` group, setgid dirs, UMASK=002) and [Private Storage](INFRASTRUCTURE.md#private-storage-access-model) for private datasets.

---

## Step 8: Decrypt Secrets

After cloning and restoring the Age key, run the CD script to decrypt all `secret.sops.env` files to `.env`. Apps will fail to start without their decrypted secrets:

```sh
bash /mnt/vm-pool/apps/scripts/dccd.sh \
  -d /mnt/vm-pool/apps \
  -x shared \
  -t -f \
  -k /mnt/vm-pool/apps/age.key
```

This also installs SOPS if not already present. At this stage no apps are created in TrueNAS yet, so the script will decrypt secrets and exit without deploying anything.

---

## Step 9: Create TrueNAS Custom Apps

In the TrueNAS UI, create a Custom App (YAML) for each service. Create
`_bootstrap` first: it owns shared external networks, including the internal
`dawarich-backend` network that Alloy and Dawarich require on a fresh
deployment. Each entry uses the `include` directive to point at the compose
file:

```yaml
include:
  - /mnt/vm-pool/apps/services/<app-name>/compose.yaml
services: {}
```

**Create `_bootstrap` first and Traefik last.** TrueNAS deploys each app
immediately when you create it. `_bootstrap` creates shared backend networks
before their consumers. Each app's compose file creates its own frontend
network (e.g., `echo-server-frontend`), and Traefik's compose file references
all of these as `external: true` — so those networks must already exist before
Traefik is created.

---

## Step 10: Validate

After all apps are deployed via the TrueNAS UI, run the CD script once to redeploy and verify everything is healthy:

```sh
bash /mnt/vm-pool/apps/scripts/dccd.sh \
  -d /mnt/vm-pool/apps \
  -x shared \
  -t -f \
  -k /mnt/vm-pool/apps/age.key
```

Then check that all containers are healthy:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}"
```

---

## Step 11: Re-enable the Cron Job

Add a TrueNAS cron job for continuous deployment:

- **Command:**
  ```sh
  bash /mnt/vm-pool/apps/scripts/dccd.sh -d /mnt/vm-pool/apps -x shared -t -f -k /mnt/vm-pool/apps/age.key
  ```
- **Run As User:** `root`
- **Schedule:** Every 15 minutes
- Unselect **Hide Standard Output** and **Hide Standard Error** for troubleshooting

Because this command includes `-f`, each run is a forced full deployment and
may start every one-shot database backup job. Backup cadence therefore follows
this 15-minute dccd schedule; each job's 48-hour retention bounds its stored
backup count.

---

## Recovery Checklist

Use this as a quick reference:

- [ ] Create ZFS datasets (`vm-pool/apps` hierarchy) with encryption enabled
- [ ] Recover one shared `vm-pool/homes` dataset and all ordinary home directories, with encryption/unlock settings and dataset/user quotas
- [ ] Restore personal identities with the same UID/GID; attach full restored home paths with creation unchecked, then review shared-root and personal ACLs, SSH keys, and `Files`-only SMB shares
- [ ] Verify personal SSH/SMB isolation, reboot/unlock behavior, and home backup/restore coverage; keep the admin home/mirror unchanged
- [ ] Unlock the encrypted apps dataset (if not auto-unlocked on boot)
- [ ] Set permissions on the apps dataset
- [ ] Create shared purpose groups (GIDs 3200–3202)
- [ ] Create app service accounts (UIDs 3100–3108, plus Plex at 911)
- [ ] Add `truenas_admin` to each app group
- [ ] Configure cross-group memberships (see ARCHITECTURE.md)
- [ ] Clone the git repository via SSH (as `truenas_admin`)
- [ ] Restore the Age private key
- [ ] Create Entra ID app registrations (2 × traefik-forward-auth) and store credentials in SOPS
- [ ] Add DNS records for auth subdomains (`auth`, `auth-ext`)
- [ ] Decrypt secrets by running `dccd.sh`
- [ ] Restore data from backups (if available)
- [ ] Recreate media/private dataset permissions (if applicable)
- [ ] Create TrueNAS Custom App entries in the UI (`_bootstrap` first, Traefik last)
- [ ] Run the CD script to validate
- [ ] Verify all containers are healthy
- [ ] Re-enable the cron job for continuous deployment
