#!/bin/bash
# Check USB drive structure
# Usage: check-usb.sh /dev/sdb

DEVICE="${1:-/dev/sdb}"

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

echo "Checking USB drive: $DEVICE"
echo "=========================================="
echo ""

echo "Partition table:"
sudo fdisk -l "$DEVICE" 2>/dev/null | head -20
echo ""

echo "File system types:"
sudo file -s "$DEVICE"* 2>/dev/null
echo ""

echo "Boot sector (first 512 bytes):"
sudo hexdump -C "$DEVICE" | head -20
echo ""

echo "Trying to mount and check contents..."
for part in ${DEVICE}1 ${DEVICE}2 ${DEVICE}p1 ${DEVICE}p2; do
    if [ -b "$part" ]; then
        echo "Found partition: $part"
        MOUNT_POINT=$(mktemp -d)
        if sudo mount "$part" "$MOUNT_POINT" 2>/dev/null; then
            echo "Contents of $part:"
            ls -la "$MOUNT_POINT" | head -20
            echo ""
            if [ -d "$MOUNT_POINT/EFI" ]; then
                echo "EFI directory found:"
                find "$MOUNT_POINT/EFI" -type f | head -10
            fi
            if [ -d "$MOUNT_POINT/boot" ]; then
                echo "Boot directory found:"
                ls -la "$MOUNT_POINT/boot" | head -10
            fi
            sudo umount "$MOUNT_POINT"
            rmdir "$MOUNT_POINT"
            break
        fi
    fi
done

