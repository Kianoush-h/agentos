#!/usr/bin/env bash
#
# Phase 06: Package VM image
# Converts the rootfs into OVA (VirtualBox) and QCOW2 (QEMU/KVM) formats.
# Produces a GPT disk with both an EFI System Partition and a root partition,
# installing GRUB for both UEFI and legacy BIOS so the image boots on any hypervisor.
#
set -euo pipefail

log "Packaging VM image..."

RAW_DISK="${BUILD_DIR}/${VM_NAME}.raw"
QCOW2_DISK="${OUTPUT_DIR}/${VM_NAME}.qcow2"
OVA_FILE="${OUTPUT_DIR}/${VM_NAME}.ova"
MOUNT_POINT="${BUILD_DIR}/mnt"
EFI_MOUNT="${BUILD_DIR}/mnt-efi"

# ── Unmount chroot filesystems ─────────────────────────────────────
log "Unmounting chroot filesystems..."
for mp in "${ROOTFS}/dev/pts" "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/run"; do
    mountpoint -q "$mp" 2>/dev/null && umount -lf "$mp" || true
done

# ── Install UEFI GRUB packages into rootfs ────────────────────────
log "Installing GRUB UEFI packages into rootfs..."
chroot "${ROOTFS}" apt-get update -qq
chroot "${ROOTFS}" apt-get install -y --no-install-recommends \
    grub-efi-amd64 grub-efi-amd64-bin grub-pc-bin \
    dosfstools efibootmgr
chroot "${ROOTFS}" apt-get clean

# ── Create raw disk image with GPT layout ─────────────────────────
# Partition layout:
#   p1: EFI System Partition (256 MiB, FAT32)
#   p2: root filesystem (remaining space, ext4)
log "Creating raw disk image (${DISK_SIZE}) with GPT..."
qemu-img create -f raw "$RAW_DISK" "$DISK_SIZE"

parted -s "$RAW_DISK" mklabel gpt
parted -s "$RAW_DISK" mkpart ESP fat32 1MiB 257MiB
parted -s "$RAW_DISK" set 1 esp on
parted -s "$RAW_DISK" mkpart primary ext4 257MiB 100%

# Set up loop device
LOOP_DEV=$(losetup --find --show --partscan "$RAW_DISK")
EFI_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

sleep 2
if [[ ! -b "$ROOT_PART" ]]; then
    partprobe "$LOOP_DEV"
    sleep 2
fi

# ── Format partitions ──────────────────────────────────────────────
log "Formatting EFI partition (FAT32)..."
mkfs.fat -F32 -n "EFI" "$EFI_PART"

log "Formatting root partition (ext4)..."
mkfs.ext4 -L "AgentOS" "$ROOT_PART"

# ── Mount and copy rootfs ──────────────────────────────────────────
mkdir -p "$MOUNT_POINT"
mount "$ROOT_PART" "$MOUNT_POINT"

mkdir -p "${MOUNT_POINT}/boot/efi"
mount "$EFI_PART" "${MOUNT_POINT}/boot/efi"

log "Copying rootfs to disk image (this takes a few minutes)..."
rsync -aHAX --info=progress2 "${ROOTFS}/" "${MOUNT_POINT}/"

# ── Update fstab with correct UUIDs ───────────────────────────────
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

cat > "${MOUNT_POINT}/etc/fstab" <<EOF
UUID=${ROOT_UUID}  /          ext4  errors=remount-ro  0  1
UUID=${EFI_UUID}   /boot/efi  vfat  umask=0077         0  1
EOF

# ── Mount virtual filesystems for GRUB install ────────────────────
log "Installing GRUB (UEFI + BIOS fallback)..."
for fs in dev dev/pts proc sys; do
    mount --bind "/${fs}" "${MOUNT_POINT}/${fs}"
done

# ── Configure GRUB ────────────────────────────────────────────────
cat > "${MOUNT_POINT}/etc/default/grub" <<'GRUB'
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="AgentOS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
GRUB_THEME="/boot/grub/themes/agentos/theme.txt"
GRUB

# Install GRUB for UEFI
chroot "${MOUNT_POINT}" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=AgentOS \
    --no-nvram \
    --removable

# Install GRUB for BIOS fallback (protective MBR on GPT disk)
chroot "${MOUNT_POINT}" grub-install \
    --target=i386-pc \
    "$LOOP_DEV"

chroot "${MOUNT_POINT}" update-grub

# ── Unmount everything ─────────────────────────────────────────────
for fs in dev/pts dev proc sys; do
    umount -lf "${MOUNT_POINT}/${fs}" || true
done
umount -lf "${MOUNT_POINT}/boot/efi" || true
umount -lf "${MOUNT_POINT}"

losetup -d "$LOOP_DEV"

# ── Convert to QCOW2 ──────────────────────────────────────────────
log "Converting to QCOW2..."
qemu-img convert -f raw -O qcow2 -c "$RAW_DISK" "$QCOW2_DISK"
ok "QCOW2 image: ${QCOW2_DISK} ($(du -h "$QCOW2_DISK" | cut -f1))"

# ── Convert to OVA (VirtualBox) ───────────────────────────────────
log "Creating OVA for VirtualBox..."

VMDK_DISK="${BUILD_DIR}/${VM_NAME}.vmdk"
qemu-img convert -f raw -O vmdk "$RAW_DISK" "$VMDK_DISK"

VMDK_SIZE=$(stat -c%s "$VMDK_DISK")
cat > "${BUILD_DIR}/${VM_NAME}.ovf" <<OVF
<?xml version="1.0"?>
<Envelope ovf:version="1.0"
  xmlns="http://schemas.dmtf.org/ovf/envelope/1"
  xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
  xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
  xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
  xmlns:vbox="http://www.virtualbox.org/ovf/machine">

  <References>
    <File ovf:href="${VM_NAME}.vmdk" ovf:id="file1" ovf:size="${VMDK_SIZE}"/>
  </References>

  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="${DISK_SIZE//G/}" ovf:capacityAllocationUnits="byte * 2^30"
          ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>

  <NetworkSection>
    <Info>Logical networks</Info>
    <Network ovf:name="NAT">
      <Description>NAT network</Description>
    </Network>
  </NetworkSection>

  <VirtualSystem ovf:id="${VM_NAME}">
    <Info>AgentOS Virtual Machine</Info>
    <Name>${VM_NAME}</Name>
    <OperatingSystemSection ovf:id="96">
      <Info>Ubuntu 64-bit</Info>
    </OperatingSystemSection>

    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>

      <Item>
        <rasd:Caption>${VM_CPUS} virtual CPUs</rasd:Caption>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>${VM_CPUS}</rasd:VirtualQuantity>
      </Item>

      <Item>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:Caption>${VM_RAM} MB of memory</rasd:Caption>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>${VM_RAM}</rasd:VirtualQuantity>
      </Item>

      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Caption>disk1</rasd:Caption>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:HostResource>/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>

      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Caption>Ethernet adapter on NAT</rasd:Caption>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVF

log "Packaging OVA..."
cd "${BUILD_DIR}"
tar -cf "$OVA_FILE" "${VM_NAME}.ovf" "${VM_NAME}.vmdk"
cd -

ok "OVA image: ${OVA_FILE} ($(du -h "$OVA_FILE" | cut -f1))"

# ── Clean up raw disk ─────────────────────────────────────────────
log "Cleaning up intermediate files..."
rm -f "$RAW_DISK" "$VMDK_DISK" "${BUILD_DIR}/${VM_NAME}.ovf"

# ── Generate checksums ─────────────────────────────────────────────
log "Generating checksums..."
cd "${OUTPUT_DIR}"
sha256sum "${VM_NAME}.qcow2" "${VM_NAME}.ova" > SHA256SUMS
cd -

ok "Checksums: ${OUTPUT_DIR}/SHA256SUMS"
ok "Build complete!"
