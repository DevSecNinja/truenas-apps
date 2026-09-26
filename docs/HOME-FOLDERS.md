# Personal Home Folders

Operator setup for **TrueNAS 25.10 on `svlnas`**: a persistent SSH/login home
and a private SMB documents folder for each trusted personal user. This is
native TrueNAS configuration, not a Docker app, GitOps deployment, or automated
host provisioner. **Nothing in this guide has been configured or tested on the
live host; all verification below remains pending operator execution.**

## Layout and Access Boundary

Replace `<username>` throughout with the actual personal account name:

```text
vm-pool/homes                         One shared Multiprotocol dataset
  <username>/                        Ordinary home directory created by TrueNAS
    .ssh/                            SSH/local-only directory
    .config/                         SSH/local-only directory
    Files/                           Ordinary directory; the only SMB export
```

The home is `/mnt/vm-pool/homes/<username>`. Its `.ssh`, `.config`, and other
dotfiles stay outside the share rooted at
`/mnt/vm-pool/homes/<username>/Files`. `Files` is accessible both locally over
SSH and through an ordinary private SMB share named `<username>-files`.

Automatic home creation is chosen for simplicity: owner-only permissions and
TrueNAS user quotas do not require a dataset per user. Prepare the shared
dataset once, then repeat account setup with **Create Home Directory checked**
and the **parent** `/mnt/vm-pool/homes` selected. TrueNAS creates the user's
home directory when the account is saved; it does **not** create `Files` or an
SMB share. Complete those remaining steps separately for each personal user.
This is not global enrollment of all current or future accounts. Separate
datasets are only an advanced alternative for independent storage policies,
not part of this procedure.

Do not move `truenas_admin`, change `/home/truenas_admin/host-init`, or create
homes for app/service accounts. A home on a locked data pool is unavailable
until unlock and cannot replace the early-boot administrative home.

<!-- dprint-ignore -->
!!! warning "Trusted users only"
    SSH is a host shell, not a jail: users can read other host-readable data.
    Private home ACLs isolate homes from ordinary users, not from root or administrators.
    Sharing only `Files` prevents direct SMB writes to SSH keys and shell dotfiles,
    but do not source or execute untrusted files from `Files`.

## 1. Preflight and Identity

1. Keep a working administrative session open and export the
   [TrueNAS configuration with its password secret seed](BACKUP.md#system-configuration-file).
   Inventory existing users, groups, home paths, datasets, shares, and permissions.
2. **For initial adoption, if the proposed parent or home already contains
   data, or per-user child datasets exist, stop.** Snapshot/back up first,
   preserve UID/GID, and plan
   a controlled migration separately. Creating a shared parent does not merge
   or migrate child datasets. Do not delete them, create datasets over
   directories, recursively reset homes, or change a populated dataset's ACL
   type using this new-home procedure. For another user on an already prepared
   and verified shared dataset, leave that dataset and existing homes intact;
   confirm the new target directory is absent and repeat only per-user setup.
3. Choose unused personal UID and private primary GID values **at least 3000**
   after checking the host and [repository allocations](INFRASTRUCTURE.md#id-ranges).
   Use available values below the reserved `3100–3199` app range; `3200+` is
   reserved for shared purpose groups. Record actual IDs, account name, home,
   dataset, and share in the secure operator inventory, not as example users
   in the app allocation tables.
4. For a **new** user, create its private primary group first; create the
   non-admin account in step 3 after preparing the dataset. For an existing
   personal user with no home data to migrate, retain its identity and review
   memberships rather than recreating it. Do not assign sudo commands,
   admin roles/groups, or app/shared-purpose groups.

## 2. Prepare the Shared Dataset Once

This is one-time preparation, not a step to reapply when adding users.
In **Datasets → vm-pool → Add Dataset**, create the new, empty `homes`
dataset, mounted at `/mnt/vm-pool/homes`:

| Setting                  | Required choice                                                          |
| ------------------------ | ------------------------------------------------------------------------ |
| Dataset / mount path     | `vm-pool/homes` / `/mnt/vm-pool/homes`                                   |
| Preset                   | **Multiprotocol**                                                        |
| Automatic shares         | **Uncheck both SMB and NFS share creation**                              |
| ACL Type / ACL Mode      | **NFSv4 / Passthrough**                                                  |
| Case Sensitivity / Atime | **Sensitive / Off**                                                      |
| Exec                     | **On**, for a useful shell home                                          |
| Quota                    | Shared dataset limit sized to free space, growth, and snapshot retention |
| Encryption               | Enable at creation, or verify the actual inherited encryption root       |

Verify these effective settings rather than relying on inheritance.
**Multiprotocol** keeps Windows-compatible NFSv4 ACL support for `Files` and
allows shell tools such as `chmod` through **Passthrough** mode on the same
filesystem. Do not inherit SMB-only **Restricted** mode or copy the historical
archives' case-insensitive or Exec Off settings.

`homes` is a sibling of `apps`, so it does **not** inherit `apps` encryption.
All home directories share the dataset properties, encryption root, snapshot
schedule, and replication policy; there are no per-user encryption keys or
independent dataset rollbacks. Record the chosen encryption root and unlock
method; back up recovery keys/passphrases independently of the NAS. Confirm
availability after reboot and unlock before relying on SSH, SMB, or backups.

### Administrative Parent

Before creating users' homes, review **Datasets → homes → Permissions →
Edit ACL** on the shared root `/mnt/vm-pool/homes`:

- Keep the root owned by root or the administrative account/group, not a
  personal user. Give ordinary users **traversal only**, without read/list,
  write/create, delete, or change-ACL rights: the equivalent of **0711** with
  a reviewed minimal NFSv4 ACL.
- Make the parent traversal ACE **non-inheriting**: no file or directory
  inheritance. Remove broad inherited/preset `builtin_users`, `group@`, or
  other named-group Modify/Full Control grants. The Multiprotocol preset is
  **not private**; `chmod 0711` alone is not proof that named grants are gone.
- Apply changes **nonrecursively to this new shared root only**. Never
  recursively change ownership or ACLs across personal homes. Users do not
  need create rights here: TrueNAS middleware creates homes administratively.

Users also need traversal through existing ancestors, including the pool
mountpoint. Inspect that access first; if missing, stop for a narrowly
reviewed change. Do not broadly open or recursively reset the pool or siblings.

### Shared and User Quotas

Set a shared dataset **quota** to bound live data and snapshot usage.
A dataset-only **refquota** limits referenced live data, not snapshot usage.
Size limits to actual capacity and retain pool reserve; no fixed size is assumed.

After provisioning each account, optionally select **Datasets → homes →
Manage User Quotas** and set its **User Data Quota** and/or **User Object
Quota**. These count storage/objects owned by that user across this dataset,
not the size of the username folder. They are **not a per-user
snapshot-retention space cap**; monitor shared snapshot growth separately.
Record dataset and user quotas with the identity inventory.

## 3. Create Each Home and Enable Key-Based SSH

Under **Credentials → Users**, create or edit the personal account using
its recorded UID and private primary group. Repeat for each approved user;
the target username directory must not already exist for this new-home flow.
**First save the account and home with SSH access off:**

| User setting                     | Value                                                            |
| -------------------------------- | ---------------------------------------------------------------- |
| Home Directory                   | **Parent** `/mnt/vm-pool/homes`                                  |
| Create Home Directory            | **Checked**                                                      |
| Home permissions                 | Explicit **0700**: User read/write/execute; Group and Other none |
| SMB Access                       | Enabled; set/retain a unique personal password                   |
| SSH Access                       | **Off** for this first save                                      |
| Public SSH Key                   | Not shown while SSH Access is off; do not add a key yet          |
| Allow SSH login with password    | **Off** for this user                                            |
| Administrative privileges / sudo | None                                                             |

Save, then, as administrator, verify the **automatically stored full home path** is
`/mnt/vm-pool/homes/<username>`, with the username appended exactly once.
Verify the home's personal owner/private primary group, **0700** mode, and
ACL with no additional grants to other users/groups before enabling SSH.
Do not supply the full future home path while creation is checked: TrueNAS
appends the username to the selected parent. It creates an ordinary directory,
not a dataset; do not separately `mkdir` the home or trust unspecified default
permissions.

**Existing/restored-home exception:** assign the **full existing path** with
**Create Home Directory unchecked**. Preserve identity and data; this attaches
a home rather than creating or migrating it.

### Private Home Permissions

TrueNAS 25.10 home creation sets the personal owner/private primary group
and requested mode, stripping the new home root's ACL nonrecursively. The
final home root therefore does not simply retain the parent's inherited ACL.
Saving account home-permission settings can also replace a custom home-root
ACL; do not blindly resave modes over it or reset existing ACLs.

**After the home review, edit the same user:** set **Create Home Directory
unchecked** and retain the **full existing path**
`/mnt/vm-pool/homes/<username>`, not the parent. Enable **SSH Access**, select
a supported interactive shell, and paste only the client's **public** key
into **Public SSH Key**, which appears when SSH Access is selected. Keep
**Allow SSH login with password off** and administrative privileges/sudo at
**None**, then save.

**After all saves**, review the home ownership, **0700** mode, and ACL again.
Now that the public key has been added, verify `.ssh` is personally owned
with **0700**, and `authorized_keys` with **0600**, both using the private
primary group. Neither the home nor these SSH paths may grant additional
access to other users/groups. Keep the client's private key on the client.

These are **folder/file permissions inside one dataset**, not per-user
entries in Datasets. Use the installed UI's advanced ACL path selection or
supported administrator permissions inspection to review the exact home and
`.ssh` paths; do not edit the shared dataset root as a substitute. Review
named entries as well as `group@`/`everyone@`. The **HOME** ACL preset grants
group modification and other-user traversal, so do not apply it blindly.
Keep corrections nonrecursive and limited to the affected new paths.

Enable the TrueNAS **SSH** service on the trusted LAN/VPN and configure
automatic startup if desired. Do not grant Full Admin just to permit SSH,
change global authentication for existing accounts, or close the
administrative session before successful tests. Do not disable the account
password globally to make SSH key-only: its SMB password must remain enabled.

From a local SSH client, replace the username placeholder and verify the host
key fingerprint against a trusted source:

| Variable   | Example                          | What to set                                   |
| ---------- | -------------------------------- | --------------------------------------------- |
| `NAS_HOST` | `svlnas`                         | Reachable NAS hostname on the trusted network |
| `NAS_USER` | `replace-with-personal-username` | Actual personal account name                  |

```sh
NAS_HOST='svlnas'
NAS_USER='replace-with-personal-username'
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no "${NAS_USER}@${NAS_HOST}"
```

In that **remote personal-user session**, check the path and ownership before
creating anything:

```sh
id
printf 'HOME=%s\n' "${HOME}"
pwd
stat -c '%a %U:%G %n' "${HOME}" "${HOME}/.ssh" "${HOME}/.ssh/authorized_keys"
```

Expect the full directory home, home and `.ssh` mode `700`, and key-file mode
`600`. Confirm effective ACLs in TrueNAS too; `stat` does not show named ACEs.
If these are wrong, stop and correct only the affected new home's permissions.

## 4. Share Only `Files`

Automatic home creation does not provision `Files` or SMB. In the **remote
personal-user session**, create **only the new** `Files` directory. `mkdir`
fails if the name already exists; inspect rather than replacing existing content:

```sh
umask 077
mkdir -m 700 -- "${HOME}/Files"
```

Review `Files`' owner and NFSv4 ACL inheritance: new files and subdirectories
must remain private to the owner. Shell `umask`/mode bits do not substitute
for this ACL check. Under **Shares → Windows (SMB)**, configure one ordinary
share per user, keeping access disabled until both ACL layers are reviewed:

| Setting                  | Value                                                                    |
| ------------------------ | ------------------------------------------------------------------------ |
| Name                     | `<username>-files`                                                       |
| Path                     | Exact existing directory `/mnt/vm-pool/homes/<username>/Files`           |
| Purpose                  | **Multi-protocol Share**, because SSH also accesses these files locally  |
| Guest access / read-only | Guest off; read-only off for personal read/write use                     |
| Share ACL                | Remove Everyone/general access; allow only this personal user **CHANGE** |

The dataset **Multiprotocol** preset and SMB **Multi-protocol Share** purpose
are separate settings. This setup requires neither NFS nor Active Directory.
Do not use the legacy Home Share option, or **Private Dataset Share**, which
automatically maps/creates username directories and does not set the SSH home.

The filesystem ACL controls local/SSH access; the share ACL only restricts
SMB. CHANGE is sufficient for SMB read/write without granting share-level
FULL/ACL control. Use the share's **Edit Filesystem ACL** for the exact
`/mnt/vm-pool/homes/<username>/Files` path if editing its ACL, not
**Datasets → homes**. Permit only owner access with private file/directory
inheritance; remove broad named/group grants and leave recursive application
off for this new folder. Audit both layers before enabling the share.

Do not export `vm-pool`, `homes`, or the whole personal home through any
overlapping share. Do not enable guest access, SMB1, wide links, or symlink
escapes. Hiding a share or disabling browsing is not authorization. Do not put
symlinks to SSH-only paths in `Files`.

Enable the SMB service and automatic startup. Require **per-share SMB3
encryption** where the installed UI and clients support it, without changing
unrelated shares. Permit SMB only on the trusted LAN/VPN, never on the WAN.

Connect using the personal SMB password, not an administrative account.
Replace `<username>` in these client examples; it is a placeholder:

- **Windows Explorer:** `\\svlnas\<username>-files`
- **macOS Finder → Go → Connect to Server:** `smb://svlnas/<username>-files`

## 5. Verify Before Use

As the personal user in the **remote SSH session**, create a harmless probe.
Noclobber prevents overwriting an existing file:

```sh
PROBE="${HOME}/Files/home-folder-check.txt"
(set -C; umask 077; printf 'Created over SSH\n' > "${PROBE}")
```

Read and update it through SMB, then read the SMB edit back over SSH:

```sh
PROBE="${HOME}/Files/home-folder-check.txt"
cat -- "${PROBE}"
```

- [ ] Public-key SSH succeeds with the correct `$HOME`, UID/GID, shell, and
      owner-only home/`.ssh`/key-file permissions; password SSH is denied for
      this user without disabling its SMB password.
- [ ] SMB and SSH can create/read/update the same `Files` probe and new
      subdirectories retain private ACLs. Remove only the test artifacts afterward.
- [ ] A different ordinary test user cannot connect to the private share or
      traverse this home locally. Test using separate credentials/sessions, not
      cached administrator SMB credentials.
- [ ] Ordinary users can traverse the shared parent but cannot list it,
      create/delete homes, or change its ACL. Parent traversal does not inherit
      into homes; inspect ACLs as well as mode bits.
- [ ] `.ssh`, `.config`, and shell dotfiles are unreachable through SMB;
      there are no overlapping exports or symlink routes to the home.
- [ ] Shared dataset and optional ownership-based user quotas, snapshot growth,
      and encryption/unlock behavior are recorded. During a planned
      reboot, verify locked-home unavailability, access after unlock, service
      startup, and continued availability of the original administrative account.
- [ ] Complete [home backup coverage and sample restores](BACKUP.md#personal-home-protection)
      before storing irreplaceable files; export the updated TrueNAS configuration.

## Backup and Recovery

Home configuration, SSH material, and personal documents are **critical
mutable file state**. Exclude caches only after proving those exact paths are
regeneratable. This design introduces no database and needs no database
backup sidecar; any future live database in a home needs a separately reviewed
application-consistent backup.

Verify recursive snapshots and replication include the **shared `homes`
dataset**, then inspect each user's ordinary directory inside its snapshots.
Verify encrypted off-site sync includes hidden files and `Files` for each
user. A pool-level task alone is not evidence of coverage. Follow
[Personal Home Protection](BACKUP.md#personal-home-protection) for schedules,
coverage checks, and isolated sample restores, and
[Personal Home Recovery](DISASTER-RECOVERY.md#personal-home-recovery) for a
rebuild. Preserve UID/GID and recheck ACLs before restoring access.
**Rolling back `vm-pool/homes` affects every user**, not just one home.
Copy selected files to an isolated restore path instead of rolling back the
shared dataset for one user's home or file.

## Sources

Official TrueNAS **25.10** references:

- [Datasets](https://www.truenas.com/docs/scale/25.10/scaletutorials/datasets/datasetsscale/) — presets, automatic shares, quotas, and encryption.
- [Permissions](https://www.truenas.com/docs/scale/25.10/scaletutorials/datasets/permissionsscale/) — NFSv4 ACLs, HOME preset, and recursive-change hazards.
- [Local users](https://www.truenas.com/docs/scale/25.10/scaletutorials/credentials/manageusers/) — automatic creation under a parent versus attaching an existing full home path, SMB passwords, and SSH access.
- [User quotas](https://www.truenas.com/docs/scale/25.10/scaletutorials/datasets/managequotas/) — ownership-based data and object quotas within a dataset.
- [25.10.0 account middleware](https://github.com/truenas/middleware/blob/release/25.10.0/src/middlewared/middlewared/plugins/account.py) — `setup_homedir(create=True)` joins parent and username, creates the directory, and sets owner/mode with nonrecursive ACL stripping.
- [SMB shares](https://www.truenas.com/docs/scale/25.10/scaletutorials/shares/smb/) — Multi-protocol Share and share/filesystem ACLs.
- [Private Dataset Share](https://www.truenas.com/docs/scale/25.10/scaletutorials/shares/smb/smbprivatedatasetshare/) — why automatic home-share mapping is not used here.
- [SSH service](https://www.truenas.com/docs/scale/25.10/scaletutorials/systemsettings/services/sshservicescale/) — service and shell-access requirements.
