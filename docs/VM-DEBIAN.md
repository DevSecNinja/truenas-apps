# Deploying a Debian VM on TrueNAS SCALE

This guide walks through creating a headless Debian virtual machine on TrueNAS SCALE using a cloud-init image — no VNC client or manual installer required. The VM is SSH-accessible immediately after first boot. After completing the steps here, continue with the [DevSecNinja/docker](https://github.com/DevSecNinja/docker) repository to install Docker and deploy services.

---

## Overview

Instead of booting a Debian ISO and clicking through an installer, this approach uses:

- **Debian's official generic cloud image** — a pre-installed, minimal Debian disk image in qcow2 format.
- **cloud-init** — a standard tool for first-boot VM configuration (users, SSH keys, hostname, packages). The configuration is passed to the VM as a small seed image mounted as a virtual CD-ROM.

The result: the VM boots, configures itself, and is reachable over SSH — all without a VNC console.

!!! info "Credit"
The cloud-init approach used here is based on [Automating VM Setup with cloud-init on TrueNAS Scale](https://barelybuggy.blog/2023/12/19/truenas-automatic-vm-cloud-init/) and the linked [Roberto Rosario guide](https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/).

---

## Prerequisites

- TrueNAS SCALE installed and accessible over SSH (`ssh truenas_admin@truenas.local`).
- A storage pool already created (the examples below use `vm-pool`).
- On your **local machine**: `cloud-image-utils` installed to generate the seed image.

  ```sh
  # Debian / Ubuntu
  sudo apt install cloud-image-utils
  # macOS (Homebrew)
  brew install cloud-image-utils
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

| Setting     | Value                              | Why                                                                      |
| ----------- | ---------------------------------- | ------------------------------------------------------------------------ |
| Zvol Name   | `debian-docker`                    | One zvol per VM for independent snapshots, rollbacks, and identification |
| Path        | `vm-pool/vms/debian-docker`        |                                                                          |
| Size        | `50 GiB` (adjust to your workload) | Enough headroom for the OS, Docker images, and container volumes         |
| Sync        | Standard                           | Matches the parent dataset; appropriate for a VM disk                    |
| Compression | lz4                                | VM filesystems compress well, especially blocks filled with zeros        |
| Sparse      | Enabled (thin provisioning)        | Only allocates space as it is written; the cloud image starts at ~2 GiB  |

---

## Step 2: Prepare the Cloud-Init Seed (local machine)

All the commands in this section run on your **local machine**, not on TrueNAS.

### 2a. Set variables

```sh
VM_NAME=debian-docker
TRUENAS=truenas_admin@truenas.local
IMAGE_PATH=/mnt/vm-pool/vms
```

### 2b. Download the Debian generic cloud image

```sh
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

!!! warning "Use `generic`, not `genericcloud`"
The `genericcloud` variant is missing the CD-ROM drivers that cloud-init needs to read the seed image when it is mounted as a virtual CD-ROM. Only the `generic` image works for this setup.

### 2c. Write your cloud-init config

Create a file named `${VM_NAME}-seed.yaml`:

```yaml
#cloud-config
hostname: debian-docker
fqdn: debian-docker.home.arpa

users:
  - name: your-user
    groups: [sudo]
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... your-key-comment  # paste your ~/.ssh/id_ed25519.pub here
    sudo: ALL=(ALL) NOPASSWD:ALL

package_update: true
package_upgrade: true
packages:
  - curl
  - git
  - ca-certificates

power_state:
  mode: reboot
  condition: true
```

Replace `your-user` and the `ssh_authorized_keys` value with your own. The `power_state` reboot at the end ensures the VM restarts cleanly after cloud-init finishes, so you will always connect to a fully configured machine.

### 2d. Build the seed image

```sh
cloud-localds --verbose ${VM_NAME}-seed.qcow2 ${VM_NAME}-seed.yaml
```

### 2e. Copy both images to TrueNAS

```sh
scp debian-12-generic-amd64.qcow2 ${TRUENAS}:${IMAGE_PATH}/
scp ${VM_NAME}-seed.qcow2          ${TRUENAS}:${IMAGE_PATH}/
```

---

## Step 3: Write the Disk Image to the Zvol (TrueNAS SSH)

SSH into TrueNAS and write the Debian cloud image directly onto the zvol:

```sh
ssh truenas_admin@truenas.local
```

```sh
VM_PATH=vm-pool/vms/debian-docker
IMAGE_PATH=/mnt/vm-pool/vms

sudo qemu-img convert -O raw \
    ${IMAGE_PATH}/debian-12-generic-amd64.qcow2 \
    /dev/zvol/${VM_PATH}
```

This expands the qcow2 image and writes it raw onto the zvol. The zvol size (50 GiB) defines the maximum usable space — Debian's `growpart` service will automatically expand the root partition to fill it on first boot.

---

## Step 4: Create the Virtual Machine (TrueNAS SSH)

Still on TrueNAS via SSH, create the VM and its devices using `midclt` (the TrueNAS middleware client):

```sh
VM_NAME=debian-docker
VM_PATH=vm-pool/vms/debian-docker
IMAGE_PATH=/mnt/vm-pool/vms
VM_MEMORY=$(( 4 * 1024 ))   # 4 GiB — increase for heavier workloads

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

# Root disk — the zvol written in Step 3
midclt call vm.device.create '{
    "vm": '"${VM_ID}"',
    "dtype": "DISK",
    "order": 1001,
    "attributes": {
        "path": "/dev/zvol/'"${VM_PATH}"'",
        "type": "VIRTIO"
    }
}'

# cloud-init seed — mounted as virtual CD-ROM so cloud-init can read it
midclt call vm.device.create '{
    "vm": '"${VM_ID}"',
    "dtype": "CDROM",
    "order": 1005,
    "attributes": {
        "path": "'"${IMAGE_PATH}/${VM_NAME}-seed.qcow2"'"
    }
}'

# NIC — place the VM on the same LAN as TrueNAS
MAC_ADDRESS=$(midclt call vm.random_mac)
midclt call vm.device.create '{
    "vm": '"${VM_ID}"',
    "dtype": "NIC",
    "order": 1010,
    "attributes": {
        "type":       "VIRTIO",
        "nic_attach": "br0",
        "mac":        "'"${MAC_ADDRESS}"'"
    }
}'
```

!!! note
Replace `br0` with your actual bridge or NIC name. Run `ip link` on TrueNAS to find the right interface.

### Start the VM

```sh
midclt call vm.start "${VM_ID}"
```

---

## Step 5: Connect via SSH

Cloud-init runs on first boot and may take 1–2 minutes to complete (package upgrades can add more). Once done, the VM reboots automatically. Find the assigned IP from your router's DHCP table or the TrueNAS ARP cache, then:

```sh
ssh your-user@<vm-ip>
```

No VNC client needed — cloud-init already installed your SSH key, created your user, and rebooted the VM cleanly.

### Remove the CD-ROM after first boot

Once cloud-init has finished the seed image is no longer needed. Remove it to keep the VM config tidy:

```sh
# Find and delete the CDROM device
CDROM_ID=$(midclt call vm.device.query \
    '[["vm","=",'"${VM_ID}"'],["dtype","=","CDROM"]]' | jq '.[0].id')
midclt call vm.device.delete "${CDROM_ID}"
```

Or remove it manually via **Virtualization → debian-docker → Devices** in the TrueNAS UI.

---

## Step 6: Assign a Static IP (recommended)

By default the VM gets an address from DHCP. For a Docker host, a static IP is strongly recommended so that other services always reach it at a predictable address.

The cleanest way is to configure this in the cloud-init seed before first boot (Step 2c), by adding a `write_files` block:

```yaml
write_files:
  - path: /etc/network/interfaces
    content: |
      auto lo
      iface lo inet loopback

      auto ens3
      iface ens3 inet static
        address 192.168.1.50
        netmask 255.255.255.0
        gateway 192.168.1.1
        dns-nameservers 192.168.1.1
```

If the VM is already running, edit `/etc/network/interfaces` on the VM directly and restart networking:

```sh
sudo systemctl restart networking
```

Replace `ens3` with the interface name shown by `ip link`, and adjust addresses to match your network.

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
zfs snapshot vm-pool/vms/debian-docker@post-cloud-init
zfs snapshot vm-pool/vms/debian-docker@post-docker-install
```

You can also configure periodic auto-snapshots in the TrueNAS UI under **Data Protection → Periodic Snapshot Tasks**.
