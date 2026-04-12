# Deploying a Debian VM on TrueNAS SCALE

This guide walks through creating a headless Debian virtual machine on TrueNAS SCALE using a cloud-init image — no VNC client or manual installer required. The VM is SSH-accessible immediately after first boot. After completing the steps here, continue with the [DevSecNinja/docker](https://github.com/DevSecNinja/docker) repository to install Docker and deploy services.

---

## Overview

Instead of booting a Debian ISO and clicking through an installer, this approach uses:

- **Debian's official generic cloud image** — a pre-installed, minimal Debian disk image in qcow2 format.
- **cloud-init** — a standard tool for first-boot VM configuration (users, SSH keys, hostname, packages). The configuration is passed to the VM as a small seed image mounted as a virtual CD-ROM.

The result: the VM boots, configures itself, and is reachable over SSH — all without a VNC console.

<!-- dprint-ignore -->
!!! info "Credit"
    The cloud-init approach used here is based on [Automating VM Setup with cloud-init on TrueNAS Scale](https://barelybuggy.blog/2023/12/19/truenas-automatic-vm-cloud-init/) and the linked [Roberto Rosario guide](https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/).

---

## Prerequisites

- TrueNAS SCALE installed and accessible over SSH (`ssh truenas_admin@truenas.local`).
- A storage pool already created (the examples below use `vm-pool`).
- On your **local machine**: a tool to build the cloud-init seed image.

  ```sh
  # Debian / Ubuntu
  sudo apt install cloud-image-utils   # provides cloud-localds
  # macOS — use hdiutil (built-in, no install needed)
  ```

- Your **SSH public key** (`~/.ssh/id_ed25519.pub` or similar) ready to embed in the cloud-init config.

---

## Step 1: Create ZFS Datasets

Create a parent dataset for VM disks, then a zvol for the VM's root disk.

### 1a. VM dataset

In the TrueNAS UI, go to **Datasets** and click **Add Dataset** on your pool:

| Setting        | Value                | Why                                                                     |
| -------------- | -------------------- | ----------------------------------------------------------------------- |
| Name           | `vms`                | Groups all VM zvols under one parent for easier administration          |
| Path           | `vm-pool/vms`        |                                                                         |
| Dataset Preset | Generic              | No special preset needed — zvols are children; this is just a container |
| Sync           | Standard             | Balances write durability and performance for general workloads         |
| Compression    | lz4                  | Fast, low-overhead compression; reclaims space on sparse VM images      |
| Enable Atime   | Off                  | Eliminates unnecessary write I/O caused by access-time tracking         |
| Encryption     | Inherit (or enabled) | Inherit pool-level encryption, or enable explicitly if standalone       |

### 1b. VM root disk (zvol)

Still in **Datasets**, click **Add Zvol** under `vm-pool/vms`:

| Setting       | Value                              | Why                                                                                                                                                       |
| ------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Zvol Name     | `svldev`                           | One zvol per VM for independent snapshots, rollbacks, and identification                                                                                  |
| Path          | `vm-pool/vms/svldev`               |                                                                                                                                                           |
| Size          | `50 GiB` (adjust to your workload) | Enough headroom for the OS, Docker images, and container volumes                                                                                          |
| Sync          | Standard                           | Matches the parent dataset; appropriate for a VM disk                                                                                                     |
| Compression   | lz4                                | VM filesystems compress well, especially blocks filled with zeros                                                                                         |
| Sparse        | ✓ (checked)                        | Only allocates space as it is written; the cloud image starts at ~2 GiB                                                                                   |
| Deduplication | Off                                | Do **not** enable dedup on VM zvols — it requires ~1 GB RAM per 1 TB of data, adds significant I/O overhead, and rarely yields savings for VM disk images |

---

## Step 2: Prepare the Cloud-Init Seed (local machine)

All the commands in this section run on your **local machine**, not on TrueNAS. They have been tested in **zsh** (macOS default shell); bash works too.

Start by creating a temporary working directory to keep the generated files together:

```sh
mkdir -p /tmp/cloud-init && cd /tmp/cloud-init
```

### 2a. Set variables

Set these once — all subsequent commands use them:

| Variable     | Example value                 | What to set                                                                |
| ------------ | ----------------------------- | -------------------------------------------------------------------------- |
| `VM_NAME`    | `svldev`                      | VM hostname — used for zvol, cloud-init, and DNS record                    |
| `VM_IP`      | `192.168.1.50`                | Free static IP on your LAN                                                 |
| `VM_GW`      | `192.168.1.1`                 | Your router / gateway IP                                                   |
| `VM_MAC`     | `52:54:00:a1:b2:c3`           | QEMU/KVM OUI (`52:54:00`) + 3 unique octets of your choice                 |
| `VM_USER`    | `your-user`                   | Non-root account cloud-init will create                                    |
| `VM_DOMAIN`  | `yourdomain.com`              | Internal domain resolved by AdGuard/Unbound — used for FQDN and DNS record |
| `SSH_KEY`    | `ssh-ed25519 AAAA...`         | Full contents of `~/.ssh/id_ed25519.pub`                                   |
| `TRUENAS`    | `truenas_admin@truenas.local` | SSH target for your TrueNAS host                                           |
| `IMAGE_PATH` | `/mnt/vm-pool/vms`            | Path on TrueNAS where images are stored                                    |

```sh
VM_NAME=svldev
VM_IP=192.168.1.50
VM_GW=192.168.1.1
VM_MAC=52:54:00:xx:xx:xx
VM_USER=your-user
VM_DOMAIN=yourdomain.com
SSH_KEY="ssh-ed25519 AAAA..."
TRUENAS=truenas_admin@truenas.local
IMAGE_PATH=/mnt/vm-pool/vms
```

<!-- dprint-ignore -->
!!! tip
    The `52:54:00` prefix is QEMU/KVM's standard OUI. UniFi recognises it and labels the device
    as a virtual machine. You can pre-register the device in UniFi with this MAC address before
    the VM even boots, giving it a reserved IP and a friendly name.

### 2b. Download the Debian generic cloud image

```sh
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

<!-- dprint-ignore -->
!!! warning "Use `generic`, not `genericcloud`"
    The `genericcloud` variant is missing the CD-ROM drivers that cloud-init needs to read the seed image when it is mounted as a virtual CD-ROM. Only the `generic` image works for this setup.

### 2c. Write your cloud-init config

Write the seed config using a heredoc so the variables from step 2a are substituted automatically:

```sh
cat > ${VM_NAME}-seed.yaml << EOF
#cloud-config
hostname: ${VM_NAME}
fqdn: ${VM_NAME}.${VM_DOMAIN}

users:
  - name: ${VM_USER}
    groups: [sudo]
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_KEY}
    sudo: ALL=(ALL) NOPASSWD:ALL  # passwordless sudo

ssh_pwauth: false  # disable SSH password authentication; key-only access

# Static network configuration — no DHCP, predictable address from first boot
network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: ${VM_MAC}
      set-name: eth0
      addresses:
        - ${VM_IP}/24
      routes:
        - to: default
          via: ${VM_GW}
      nameservers:
        addresses:
          - ${VM_GW}  # point to your gateway or AdGuard/Unbound for internal DNS

package_update: true
package_upgrade: true
packages:
  - curl
  - git
  - ca-certificates

power_state:
  mode: reboot
  condition: true
EOF
```

<!-- dprint-ignore -->
!!! note "On `sudo: ALL=(ALL) NOPASSWD:ALL`"
    This grants full passwordless root access. It is relatively safe here because `ssh_pwauth: false` ensures
    only SSH key holders can log in — an attacker without your private key cannot reach the machine
    at all, and requiring a sudo password at that point adds no meaningful protection. If you prefer
    to require a password for sudo, remove `NOPASSWD:` from the sudo line and omit the `NOPASSWD`
    field.

### 2d. Build the seed image

**Linux** (`cloud-image-utils`):

```sh
echo "instance-id: ${VM_NAME}" > meta-data
echo "local-hostname: ${VM_NAME}" >> meta-data
cloud-localds --verbose ${VM_NAME}-seed.iso ${VM_NAME}-seed.yaml meta-data
```

**macOS** (`hdiutil`, built-in — no extra tools needed):

```sh
echo "instance-id: ${VM_NAME}" > meta-data
echo "local-hostname: ${VM_NAME}" >> meta-data
hdiutil makehybrid -o ${VM_NAME}-seed -hfs -joliet -iso \
    -default-volume-name cidata .
mv ${VM_NAME}-seed.iso ${VM_NAME}-seed.img
```

<!-- dprint-ignore -->
!!! note
    The seed must have the volume label `cidata` — cloud-init identifies it by that label, not the file extension.

### 2e. Copy both images to TrueNAS

```sh
scp debian-12-generic-amd64.qcow2 ${TRUENAS}:${IMAGE_PATH}/
scp ${VM_NAME}-seed.img            ${TRUENAS}:${IMAGE_PATH}/
```

### 2f. Clean up the working directory

Once the images are on TrueNAS you no longer need the local copies. You can either delete the directory entirely:

```sh
cd ~ && rm -rf /tmp/cloud-init
```

Or keep the seed config for future reference (the qcow2 is large and can always be re-downloaded):

```sh
# Keep only the cloud-init config; remove the large images
rm /tmp/cloud-init/debian-12-generic-amd64.qcow2
rm /tmp/cloud-init/${VM_NAME}-seed.img
```

---

## Step 3: Write the Disk Image to the Zvol (TrueNAS SSH)

SSH into TrueNAS and write the Debian cloud image directly onto the zvol:

```sh
ssh "${TRUENAS}"
```

```sh
# Re-declare variables on the TrueNAS side
VM_NAME=svldev
VM_PATH=vm-pool/vms/${VM_NAME}
IMAGE_PATH=/mnt/vm-pool/vms

sudo qemu-img convert -O raw \
    ${IMAGE_PATH}/debian-12-generic-amd64.qcow2 \
    /dev/zvol/${VM_PATH}
```

This expands the qcow2 image and writes it raw onto the zvol. The zvol size (50 GiB) defines the maximum usable space — Debian's `growpart` service will automatically expand the root partition to fill it on first boot.

---

## Step 4: Create the Virtual Machine (TrueNAS SSH)

Still on TrueNAS via SSH, create the VM and its devices using `midclt` (the TrueNAS middleware client).

Re-declare the variables needed on the TrueNAS side — `VM_MEMORY` is in MiB, adjust upward for heavier workloads. `VM_MAC` must match exactly what you set in step 2a:

```sh
VM_NAME=svldev
VM_PATH=vm-pool/vms/${VM_NAME}
IMAGE_PATH=/mnt/vm-pool/vms
VM_MEMORY=$(( 4 * 1024 ))
VM_MAC=52:54:00:xx:xx:xx

# Create VM
RESULT=$(midclt call vm.create '{
    "name":        "'"${VM_NAME}"'",
    "cpu_mode":    "HOST-MODEL",
    "bootloader":  "UEFI",
    "cores":       2,
    "threads":     2,
    "memory":      '"${VM_MEMORY}"',
    "autostart":   true
}')
VM_ID=$(echo "${RESULT}" | jq '.id')

midclt call vm.device.create '{
    "vm": '"${VM_ID}"',
    "dtype": "DISK",
    "order": 1001,
    "attributes": {
        "path": "/dev/zvol/'"${VM_PATH}"'",
        "type": "VIRTIO"
    }
}'

midclt call vm.device.create '{
    "vm": '"${VM_ID}"',
    "dtype": "CDROM",
    "order": 1005,
    "attributes": {
        "path": "'"${IMAGE_PATH}/${VM_NAME}-seed.img"'"
    }
}'

midclt call vm.device.create '{
    "vm": '"${VM_ID}"',
    "dtype": "NIC",
    "order": 1010,
    "attributes": {
        "type":       "VIRTIO",
        "nic_attach": "br0",
        "mac":        "'"${VM_MAC}"'"
    }
}'
```

<!-- dprint-ignore -->
!!! note
    Replace `br0` with your actual bridge or NIC name. Run `ip link` on TrueNAS to find the right interface.

### Start the VM

```sh
midclt call vm.start "${VM_ID}"
```

---

## Step 5: Connect via SSH

Cloud-init runs on first boot and may take 1–2 minutes to complete (package upgrades can add more). Once done, the VM reboots automatically. Connect using the static IP configured in the cloud-init seed:

```sh
ssh ${VM_USER}@${VM_IP}
```

No VNC client needed — cloud-init already installed your SSH key, created your user, and rebooted the VM cleanly.

### Remove the CD-ROM after first boot

Once cloud-init has finished the seed image is no longer needed. Remove it to keep the VM config tidy:

```sh
# Find and delete the CDROM device
CDROM_ID=$(midclt call vm.device.query \
    '[["vm","=",'"${VM_ID}"'],["dtype","=","CDROM"]]' | jq '.[0].id')
midclt call vm.device.delete "${CDROM_ID}"
# Optionally remove the seed image from disk
rm ${IMAGE_PATH}/${VM_NAME}-seed.img
```

Or remove it manually via **Virtualization → svldev → Devices** in the TrueNAS UI.

---

## Step 6: Register the VM in Unbound

Add an A record for the VM so it is reachable by hostname on your LAN. In `services/adguard/config/unbound/conf.d/a-records.conf`, add:

```text
local-data: "${VM_NAME}.${DOMAINNAME} A ${VM_IP}"
```

Then add the corresponding variable to `services/adguard/secret.sops.env` (use the actual IP, not the shell variable):

```sh
IP_SVLDEV=192.168.1.50
```

Deploy AdGuard to pick up the change. Once active, `${VM_NAME}.${VM_DOMAIN}` will resolve on your LAN and the cloud-init `fqdn` will be fully functional.

---

## Step 7: Deploy Docker

Continue with the [DevSecNinja/docker](https://github.com/DevSecNinja/docker) repository, which handles:

- Docker Engine installation
- Docker Compose plugin
- User and group configuration
- Any additional bootstrapping steps

Follow the instructions in that repository's README from this point forward.

---

## Snapshot strategy (recommended)

Take ZFS snapshots of the zvol at key milestones so you can roll back cleanly:

```sh
# On TrueNAS
zfs snapshot vm-pool/vms/svldev@post-cloud-init
zfs snapshot vm-pool/vms/svldev@post-docker-install
```

You can also configure periodic auto-snapshots in the TrueNAS UI under **Data Protection → Periodic Snapshot Tasks**.
