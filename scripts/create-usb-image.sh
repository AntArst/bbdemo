#!/bin/bash
# Create a USB-bootable image directly (alternative to ISO)
# This creates a proper USB structure with FAT32 EFI partition
# Usage: create-usb-image.sh <project_dir> <build_dir> <output.img>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$1"
BUILD_DIR="$2"
OUTPUT_IMG="$3"

if [ -z "$PROJECT_DIR" ] || [ -z "$BUILD_DIR" ] || [ -z "$OUTPUT_IMG" ]; then
    echo "Usage: $0 <project_dir> <build_dir> <output.img>"
    exit 1
fi

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "Creating USB-bootable image..."
echo "This will create a proper USB structure with FAT32 EFI partition"

# Find Clonezilla files (from previous ISO creation or extract fresh)
CLONEZILLA_ZIP="$PROJECT_DIR/downloads/clonezilla-live-3.3.0-33-amd64.zip"
if [ ! -f "$CLONEZILLA_ZIP" ]; then
    echo "Error: Clonezilla ZIP not found. Please run package-image.sh first or download Clonezilla."
    exit 1
fi

# Extract Clonezilla
CLONEZILLA_EXTRACT="$WORK_DIR/clonezilla"
mkdir -p "$CLONEZILLA_EXTRACT"
unzip -q "$CLONEZILLA_ZIP" -d "$CLONEZILLA_EXTRACT"

# Find disk image
DISK_IMAGE=$(find "$BUILD_DIR/tmp-glibc/deploy/images" -name "bbdemo-disk.img" 2>/dev/null | head -1)
if [ -z "$DISK_IMAGE" ]; then
    # Create it if it doesn't exist
    ROOTFS=$(find "$BUILD_DIR/tmp-glibc/deploy/images" -name "bbdemo-image*.ext4" | head -1)
    if [ -z "$ROOTFS" ]; then
        echo "Error: Rootfs not found. Please build the image first."
        exit 1
    fi
    DISK_IMAGE="$WORK_DIR/bbdemo-disk.img"
    "$SCRIPT_DIR/create-disk-image.sh" "$ROOTFS" "$DISK_IMAGE" 2048
fi

# Copy disk image to Clonezilla extract
cp "$DISK_IMAGE" "$CLONEZILLA_EXTRACT/bbdemo-disk.img"

# Create USB image structure
USB_SIZE=4096  # 4GB should be enough
USB_IMG="$OUTPUT_IMG"

echo "Creating ${USB_SIZE}MB USB image..."
dd if=/dev/zero of="$USB_IMG" bs=1M count=$USB_SIZE 2>/dev/null

# Create GPT partition table with EFI System Partition
echo "Creating GPT partition table with EFI System Partition..."
parted -s "$USB_IMG" mklabel gpt
parted -s "$USB_IMG" mkpart primary fat32 1MiB 512MiB  # EFI System Partition
parted -s "$USB_IMG" set 1 esp on  # Mark as ESP
parted -s "$USB_IMG" mkpart primary ext4 512MiB 100%  # Rest for Clonezilla

# Setup loop device
LOOP_DEV=$(losetup --find --show -P "$USB_IMG")
EFI_PART="${LOOP_DEV}p1"
DATA_PART="${LOOP_DEV}p2"

sleep 2
partprobe "$LOOP_DEV" 2>/dev/null || true

# Format EFI partition as FAT32
echo "Formatting EFI partition as FAT32..."
mkfs.vfat -F 32 -n "EFI" "$EFI_PART" >/dev/null 2>&1 || \
    mkfs.fat -F 32 "$EFI_PART" >/dev/null 2>&1

# Format data partition as ext4 (or keep as is for Clonezilla)
echo "Formatting data partition..."
mkfs.ext4 -F -L "CLONEZILLA" "$DATA_PART" >/dev/null 2>&1

# Mount EFI partition and copy EFI files
EFI_MOUNT=$(mktemp -d)
mount "$EFI_PART" "$EFI_MOUNT"

echo "Copying EFI boot files..."
mkdir -p "$EFI_MOUNT/EFI/boot"
cp -a "$CLONEZILLA_EXTRACT/EFI/boot"/* "$EFI_MOUNT/EFI/boot/" 2>/dev/null || true

# Create boot entry
cat > "$EFI_MOUNT/EFI/boot/grub.cfg" << 'GRUB_EOF'
set timeout=5
menuentry "Clonezilla Live" {
    linux /live/vmlinuz boot=live union=overlay username=user config components quiet noswap edd=on nomodeset ocs_live_run="ocs-live-device-image" ocs_live_extra_param="" ocs_live_batch="no" locales=en_US.UTF-8 keyboard-layouts=NONE ocs_live_keymap="" ocs_live_username="user" ocs_live_full_mode="no" ocs_live_iso_path="" ocs_prerun="mount /dev/sr0 /mnt/iso 2>/dev/null || mount /dev/cdrom /mnt/iso 2>/dev/null || true; if [ -f /mnt/iso/bbdemo-disk.img ]; then cp /mnt/iso/bbdemo-disk.img /home/partimag/bbdemo-disk.img || ln -sf /mnt/iso/bbdemo-disk.img /home/partimag/bbdemo-disk.img; fi"
    initrd /live/initrd.img
}
GRUB_EOF

umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"

# Mount data partition and copy Clonezilla files
DATA_MOUNT=$(mktemp -d)
mount "$DATA_PART" "$DATA_MOUNT"

echo "Copying Clonezilla files..."
cp -a "$CLONEZILLA_EXTRACT"/* "$DATA_MOUNT/" 2>/dev/null || true

umount "$DATA_MOUNT"
rmdir "$DATA_MOUNT"

# Cleanup
losetup -d "$LOOP_DEV"

echo "USB image created: $USB_IMG"
echo "To write to USB: sudo dd if=$USB_IMG of=/dev/sdX bs=4M status=progress oflag=sync"

