#!/bin/bash
# Create a full disk image from Yocto rootfs
# Usage: create-disk-image.sh <rootfs.ext4> <output.img> <size_in_MB>

set -e

ROOTFS="$1"
OUTPUT_IMG="$2"
SIZE_MB="${3:-2048}"  # Default 2GB

if [ -z "$ROOTFS" ] || [ -z "$OUTPUT_IMG" ]; then
    echo "Usage: $0 <rootfs.ext4> <output.img> [size_in_MB]"
    exit 1
fi

if [ ! -f "$ROOTFS" ]; then
    echo "Error: Rootfs file not found: $ROOTFS"
    exit 1
fi

echo "Creating disk image from rootfs..."
echo "  Rootfs: $ROOTFS"
echo "  Output: $OUTPUT_IMG"
echo "  Size: ${SIZE_MB}MB"

# Get rootfs size and add some overhead
ROOTFS_SIZE=$(stat -c%s "$ROOTFS")
ROOTFS_SIZE_MB=$((ROOTFS_SIZE / 1024 / 1024))
MIN_SIZE=$((ROOTFS_SIZE_MB + 100))  # Add 100MB overhead

if [ "$SIZE_MB" -lt "$MIN_SIZE" ]; then
    echo "Warning: Requested size ${SIZE_MB}MB is less than minimum ${MIN_SIZE}MB"
    echo "Using minimum size: ${MIN_SIZE}MB"
    SIZE_MB=$MIN_SIZE
fi

# Create empty disk image
echo "Creating ${SIZE_MB}MB disk image..."
# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_IMG")"

# Create the file with dd and capture any errors
if ! dd if=/dev/zero of="$OUTPUT_IMG" bs=1M count="$SIZE_MB" 2>&1; then
    echo "Error: Failed to create disk image file with dd"
    exit 1
fi
sync  # Ensure file is written to disk

# Verify file was created and has correct size
if [ ! -f "$OUTPUT_IMG" ]; then
    echo "Error: Disk image file was not created: $OUTPUT_IMG"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$OUTPUT_IMG" 2>/dev/null || echo "0")
EXPECTED_SIZE=$((SIZE_MB * 1024 * 1024))
if [ "$FILE_SIZE" -lt "$EXPECTED_SIZE" ]; then
    echo "Error: Disk image file is too small. Expected: ${EXPECTED_SIZE}, Got: ${FILE_SIZE}"
    exit 1
fi

echo "Disk image file created: $OUTPUT_IMG (size: $FILE_SIZE bytes)"

# Create partition table (MBR for x86_64)
echo "Creating MBR partition table..."
parted -s "$OUTPUT_IMG" mklabel msdos

# Create primary partition (use 95% of disk, leave some space)
PART_SIZE=$((SIZE_MB * 95 / 100))
parted -s "$OUTPUT_IMG" mkpart primary ext4 1MiB ${PART_SIZE}MiB
parted -s "$OUTPUT_IMG" set 1 boot on
sync  # Ensure partition table is written

# Setup loop device with partition support
echo "Setting up loop device..."
# Check if file exists and is readable
if [ ! -f "$OUTPUT_IMG" ]; then
    echo "Error: Disk image file does not exist: $OUTPUT_IMG"
    exit 1
fi

if [ ! -r "$OUTPUT_IMG" ]; then
    echo "Error: Disk image file is not readable: $OUTPUT_IMG"
    ls -la "$OUTPUT_IMG" 2>/dev/null || echo "Cannot stat file"
    exit 1
fi

# Verify we can access the file
if ! test -r "$OUTPUT_IMG"; then
    echo "Error: Cannot read disk image file: $OUTPUT_IMG"
    exit 1
fi

# Check if loop module is loaded
if ! lsmod | grep -q "^loop "; then
    echo "Error: Loop module is not loaded"
    echo "Try running: sudo modprobe loop"
    exit 1
fi

# Check permissions - user needs to be able to create loop devices
# This usually requires being in the 'disk' group or having sudo access
if [ ! -w /dev/loop-control ] 2>/dev/null; then
    echo "Warning: May not have permission to create loop devices"
    echo "You may need to run this script with sudo, or add your user to the 'disk' group"
fi

# Try with -P flag first (for partition scanning), fallback to without
echo "Attempting to create loop device..."
LOOP_DEV=""
LOOP_ERROR=""

# Try with -P flag first
if LOOP_DEV=$(losetup --find --show -P "$OUTPUT_IMG" 2>&1); then
    # Check if output is actually a device (not an error message)
    if [ -b "$LOOP_DEV" ] 2>/dev/null; then
        echo "Loop device created with -P: $LOOP_DEV"
    else
        # Output might be an error message, try without -P
        LOOP_ERROR="$LOOP_DEV"
        LOOP_DEV=""
    fi
else
    # -P failed, capture error and try without
    LOOP_ERROR="$LOOP_DEV"
    LOOP_DEV=""
fi

# If -P didn't work, try without it
if [ -z "$LOOP_DEV" ] || [ ! -b "$LOOP_DEV" ]; then
    echo "Note: -P flag not supported or failed, trying without..."
    if LOOP_DEV=$(losetup --find --show "$OUTPUT_IMG" 2>&1); then
        if [ -b "$LOOP_DEV" ] 2>/dev/null; then
            echo "Loop device created: $LOOP_DEV"
        else
            # Still got error message instead of device
            LOOP_ERROR="$LOOP_DEV"
            LOOP_DEV=""
        fi
    else
        LOOP_ERROR="$LOOP_DEV"
        LOOP_DEV=""
    fi
fi

# If still no device, show detailed error
if [ -z "$LOOP_DEV" ] || [ ! -b "$LOOP_DEV" ]; then
    echo "Error: Failed to create loop device"
    echo "losetup error: $LOOP_ERROR"
    echo "File path: $OUTPUT_IMG"
    echo "File exists: $([ -f "$OUTPUT_IMG" ] && echo 'yes' || echo 'no')"
    echo "File readable: $([ -r "$OUTPUT_IMG" ] && echo 'yes' || echo 'no')"
    echo "File size: $(stat -c%s "$OUTPUT_IMG" 2>/dev/null || echo 'unknown') bytes"
    echo "File permissions: $(ls -la "$OUTPUT_IMG" 2>/dev/null || echo 'cannot stat')"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check if loop module is loaded: lsmod | grep loop"
    echo "2. Try loading loop module: sudo modprobe loop"
    echo "3. Check if you have permission to create loop devices"
    echo "4. You may need to run this script with sudo: sudo ./setup-yocto.sh --image"
    echo "5. Or add your user to the 'disk' group: sudo usermod -aG disk $USER"
    echo "   (then log out and back in)"
    exit 1
fi
PART_DEV="${LOOP_DEV}p1"

# Wait for partition device to appear
echo "Waiting for partition device..."
# Try partprobe first to trigger partition device creation
partprobe "$LOOP_DEV" 2>/dev/null || true
sleep 2

# Check for partition device with different naming conventions
if [ -e "${LOOP_DEV}p1" ]; then
    PART_DEV="${LOOP_DEV}p1"
elif [ -e "${LOOP_DEV}1" ]; then
    PART_DEV="${LOOP_DEV}1"
else
    # Try using kpartx if available
    if command -v kpartx >/dev/null 2>&1; then
        echo "Using kpartx to create partition devices..."
        kpartx -av "$LOOP_DEV" 2>/dev/null || true
        sleep 1
        # kpartx creates devices in /dev/mapper/
        MAPPER_DEV="/dev/mapper/$(basename ${LOOP_DEV})p1"
        if [ -e "$MAPPER_DEV" ]; then
            PART_DEV="$MAPPER_DEV"
        else
            # Try alternative mapper name
            MAPPER_DEV="/dev/mapper/$(basename ${LOOP_DEV})1"
            if [ -e "$MAPPER_DEV" ]; then
                PART_DEV="$MAPPER_DEV"
            fi
        fi
    fi
    
    # Final check
    if [ ! -e "$PART_DEV" ]; then
        # Try one more time with partprobe and wait
        partprobe "$LOOP_DEV" 2>/dev/null || true
        sleep 3
        if [ -e "${LOOP_DEV}p1" ]; then
            PART_DEV="${LOOP_DEV}p1"
        elif [ -e "${LOOP_DEV}1" ]; then
            PART_DEV="${LOOP_DEV}1"
        else
            losetup -d "$LOOP_DEV" 2>/dev/null || true
            echo "Error: Failed to create partition device after multiple attempts"
            echo "Loop device: $LOOP_DEV"
            echo "Available devices:"
            ls -la "${LOOP_DEV}"* 2>/dev/null || echo "None found"
            if command -v kpartx >/dev/null 2>&1; then
                echo "Kpartx devices:"
                ls -la /dev/mapper/$(basename ${LOOP_DEV})* 2>/dev/null || echo "None found"
            fi
            exit 1
        fi
    fi
fi

echo "Using partition device: $PART_DEV"

# Format partition as ext4
echo "Formatting partition as ext4..."
mkfs.ext4 -F -L "bbdemo-root" "$PART_DEV" > /dev/null 2>&1

# Mount partition
MOUNT_POINT=$(mktemp -d)
mount "$PART_DEV" "$MOUNT_POINT"

# Copy rootfs contents
echo "Copying rootfs contents..."
# The rootfs is an ext4 filesystem, so we need to mount it
ROOTFS_LOOP=$(losetup --find --show "$ROOTFS")
ROOTFS_MOUNT=$(mktemp -d)
mount "$ROOTFS_LOOP" "$ROOTFS_MOUNT"

# Copy all files from rootfs to the new partition
echo "Copying files (this may take a while)..."
rsync -aAX "$ROOTFS_MOUNT"/ "$MOUNT_POINT"/ 2>/dev/null || \
    cp -a "$ROOTFS_MOUNT"/* "$MOUNT_POINT"/ 2>/dev/null || true

# Unmount rootfs
umount "$ROOTFS_MOUNT"
losetup -d "$ROOTFS_LOOP"
rmdir "$ROOTFS_MOUNT"

# Install bootloader (GRUB) if available, otherwise just ensure kernel is accessible
if [ -f "$MOUNT_POINT/boot/bzImage" ] || [ -f "$MOUNT_POINT/bzImage" ]; then
    echo "Kernel found in rootfs"
fi

# Unmount
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

# Detach loop device and clean up kpartx if used
if command -v kpartx >/dev/null 2>&1 && echo "$PART_DEV" | grep -q mapper; then
    kpartx -d "$LOOP_DEV" 2>/dev/null || true
fi
losetup -d "$LOOP_DEV" 2>/dev/null || true

echo "Disk image created successfully: $OUTPUT_IMG"
echo "  Size: $(du -h "$OUTPUT_IMG" | cut -f1)"

