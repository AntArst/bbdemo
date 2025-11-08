#!/bin/bash
# Generate Clonezilla configuration for automated restore
# Usage: clonezilla-config.sh <work_dir> <disk_image> <output_config>

set -e

WORK_DIR="$1"
DISK_IMAGE="$2"
OUTPUT_CONFIG="$3"

if [ -z "$WORK_DIR" ] || [ -z "$DISK_IMAGE" ] || [ -z "$OUTPUT_CONFIG" ]; then
    echo "Usage: $0 <work_dir> <disk_image> <output_config>"
    exit 1
fi

# Get just the filename of the disk image
DISK_IMAGE_NAME=$(basename "$DISK_IMAGE")

# Create ocs-iso.cfg for Clonezilla
# This configures Clonezilla to run in device-image mode (restore from embedded image)
cat > "$OUTPUT_CONFIG" << EOF
# Clonezilla configuration for BBDemo image restore
# This file configures Clonezilla to restore the embedded disk image

# Set to device-image mode (restore from image file)
ocs_live_run="ocs-live-device-image"

# Enable semi-automated mode (prompts for disk selection)
ocs_live_batch="no"

# Image repository - will be mounted from ISO
# Clonezilla will look for images in /home/partimag/
# We'll mount the ISO and copy/link the image there
ocs_prerun="mkdir -p /mnt/iso /home/partimag && mount /dev/sr0 /mnt/iso 2>/dev/null || mount /dev/cdrom /mnt/iso 2>/dev/null || mount /dev/loop0 /mnt/iso 2>/dev/null || true; if [ -f /mnt/iso/bbdemo-disk.img ]; then cp /mnt/iso/bbdemo-disk.img /home/partimag/bbdemo-disk.img || ln -sf /mnt/iso/bbdemo-disk.img /home/partimag/bbdemo-disk.img; fi"

# Image file location for Clonezilla
# Clonezilla expects images in /home/partimag/
IMAGE_FILE="/home/partimag/bbdemo-disk.img"

# Post-mount: ensure image is accessible
ocs_postrun="if [ ! -f \$IMAGE_FILE ]; then echo 'Error: Image file not found. Trying alternative locations...'; if [ -f /mnt/iso/bbdemo-disk.img ]; then cp /mnt/iso/bbdemo-disk.img \$IMAGE_FILE || ln -sf /mnt/iso/bbdemo-disk.img \$IMAGE_FILE; else echo 'Error: Cannot find embedded disk image on ISO'; exit 1; fi; fi; echo 'Image file ready: \$IMAGE_FILE'; ls -lh \$IMAGE_FILE"
EOF

# Create a restore script that Clonezilla will use
RESTORE_SCRIPT="$WORK_DIR/ocs-restore.sh"
cat > "$RESTORE_SCRIPT" << 'RESTORE_EOF'
#!/bin/bash
# Clonezilla restore script for BBDemo image

set -e

# Mount ISO to access embedded image
ISO_MOUNT="/mnt/iso"
IMAGE_FILE="$ISO_MOUNT/bbdemo-disk.img"

# Try to mount ISO
if [ ! -f "$IMAGE_FILE" ]; then
    # Try different device names
    for dev in /dev/sr0 /dev/cdrom /dev/loop0; do
        if [ -b "$dev" ]; then
            mount -t iso9660 "$dev" "$ISO_MOUNT" 2>/dev/null && break
        fi
    done
fi

if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: Cannot find embedded disk image on ISO"
    exit 1
fi

echo "Found embedded image: $IMAGE_FILE"
echo "Image size: $(du -h "$IMAGE_FILE" | cut -f1)"

# Clonezilla will handle the actual restore process
# This script just ensures the image is accessible
echo "Image is ready for restore via Clonezilla"
RESTORE_EOF

chmod +x "$RESTORE_SCRIPT"

# Create a simple menu entry script for Clonezilla
MENU_SCRIPT="$WORK_DIR/ocs-menu.sh"
cat > "$MENU_SCRIPT" << 'MENU_EOF'
#!/bin/bash
# Clonezilla menu customization

echo "=========================================="
echo "BBDemo Image Restore"
echo "=========================================="
echo ""
echo "This Clonezilla Live ISO contains a BBDemo disk image."
echo "You will be prompted to select the target disk."
echo ""
echo "WARNING: This will overwrite all data on the selected disk!"
echo ""
MENU_EOF

chmod +x "$MENU_SCRIPT"

echo "Clonezilla configuration created: $OUTPUT_CONFIG"

