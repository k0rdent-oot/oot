#!/usr/bin/env bash
#
# Prepare MicroOS image with Ec2 datasource for Tinkerbell provisioning
#

set -euo pipefail

MICROOS_URL="https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-OpenStack-Cloud.qcow2"

log_info() { echo "[INFO] $1"; }
log_error() { echo "[ERROR] $1" >&2; }

cleanup() {
    local exit_code=$?
    umount -l /mnt/proc 2>/dev/null || true
    umount -l /mnt/sys 2>/dev/null || true
    umount -l /mnt/dev 2>/dev/null || true
    umount -l /mnt/run 2>/dev/null || true
    if mountpoint -q /mnt 2>/dev/null; then
        umount -l /mnt || true
    fi
    if [[ -n "${LOOP_DEV:-}" ]] && [[ -b "${LOOP_DEV}" ]]; then
        losetup -d "${LOOP_DEV}" || true
    fi
    exit "${exit_code}"
}

trap cleanup EXIT

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") <output_directory> <metadata_ip>"
    echo "Example: $(basename "$0") /var/artifacts 172.17.1.1"
    exit 1
fi

OUTPUT_DIR="$1"
METADATA_IP="$2"

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

for dep in curl qemu-img losetup btrfs; do
    if ! command -v "${dep}" &>/dev/null; then
        log_error "Missing dependency: ${dep}"
        exit 1
    fi
done

if [[ ! -d "${OUTPUT_DIR}" ]]; then
    log_error "Output directory does not exist: ${OUTPUT_DIR}"
    exit 1
fi

QCOW2_FILE="${OUTPUT_DIR}/microos.qcow2"
RAW_FILE="${OUTPUT_DIR}/microos.raw"

log_info "Downloading MicroOS cloud image..."
curl -L -o "${QCOW2_FILE}" "${MICROOS_URL}"

log_info "Converting qcow2 to raw format..."
qemu-img convert -f qcow2 -O raw "${QCOW2_FILE}" "${RAW_FILE}"
rm -f "${QCOW2_FILE}"

log_info "Setting up loop device..."
LOOP_DEV=$(losetup -fP --show "${RAW_FILE}")

log_info "Partition table:"
fdisk -l "${LOOP_DEV}"

ROOT_PART=$(blkid -t PARTLABEL="p.lxroot" -o device "${LOOP_DEV}"* 2>/dev/null | head -1)
if [[ -z "${ROOT_PART}" ]]; then
    log_error "Root partition (PARTLABEL=p.lxroot) not found"
    exit 1
fi
log_info "Found root partition: ${ROOT_PART}"

log_info "Mounting btrfs root partition..."
mount -o subvol=/@/.snapshots/1/snapshot "${ROOT_PART}" /mnt

log_info "Making snapshot writable..."
btrfs property set -ts /mnt ro false

log_info "Configuring cloud-init for Ec2 datasource..."

cat > /mnt/etc/cloud/ds-identify.cfg <<EOF
datasource: Ec2
EOF

cat > /mnt/etc/cloud/cloud.cfg.d/10_ec2.cfg <<EOF
datasource:
  Ec2:
    metadata_urls:
      - http://${METADATA_IP}:7172
    strict_id: false
warnings:
  dsid_missing_source: off
EOF

log_info "Adding CRI-O repository..."
cat > /mnt/etc/zypp/repos.d/cri-o.repo <<EOF
[cri-o]
name=CRI-O stable v1.33
baseurl=http://download.opensuse.org/repositories/isv:/kubernetes:/addons:/cri-o:/stable:/v1.33:/build/rpm/
enabled=1
gpgcheck=0
EOF

log_info "Mounting system directories for chroot..."
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /dev /mnt/dev
mount --bind /run /mnt/run

log_info "Setting up temporary DNS..."
RESOLV_BACKUP=$(cat /mnt/etc/resolv.conf 2>/dev/null || true)
echo "nameserver 1.1.1.1" > /mnt/etc/resolv.conf

log_info "Installing CRI-O and Kubernetes packages..."
chroot /mnt zypper --non-interactive --no-gpg-checks refresh
chroot /mnt zypper --non-interactive --no-gpg-checks install --replacefiles cri-o kubernetes1.33-kubeadm kubernetes1.33-kubelet

log_info "Restoring DNS configuration..."
echo "${RESOLV_BACKUP}" > /mnt/etc/resolv.conf

log_info "Configuring CRI-O to use runc with STATX fallback..."
cat > /mnt/etc/crio/crio.conf.d/10-runc.conf <<EOF
[crio.runtime.runtimes.runc]
runtime_path = "/usr/bin/runc"
runtime_type = "oci"
runtime_env = ["RUNC_STATX_FALLBACK=1"]
monitor_path = "/usr/libexec/crio/conmon"
EOF

log_info "Enabling CRI-O service..."
mkdir -p /mnt/etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/crio.service /mnt/etc/systemd/system/multi-user.target.wants/crio.service

log_info "Disabling containerd service..."
rm -f /mnt/etc/systemd/system/multi-user.target.wants/containerd.service 2>/dev/null || true
ln -sf /dev/null /mnt/etc/systemd/system/containerd.service

log_info "Enabling root login with password 'root'..."
echo 'root:root' | chroot /mnt chpasswd
chroot /mnt passwd -u root
log_info "Root login enabled (password: root)"

log_info "Making snapshot read-only again..."
btrfs property set -ts /mnt ro true

log_info "Unmounting chroot directories..."
umount -l /mnt/proc
umount -l /mnt/sys
umount -l /mnt/dev
umount -l /mnt/run
umount -l /mnt

losetup -d "${LOOP_DEV}"
unset LOOP_DEV

log_info "Compressing image..."
gzip -f "${RAW_FILE}"

log_info "Done: ${RAW_FILE}.gz ($(du -h "${RAW_FILE}.gz" | cut -f1))"
log_info "Metadata URL configured: http://${METADATA_IP}:7172"
