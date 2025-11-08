#!/bin/bash
# Package Yocto image into Clonezilla Live ISO
# Usage: package-image.sh <project_dir> <build_dir>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$1"
BUILD_DIR="$2"

if [ -z "$PROJECT_DIR" ] || [ -z "$BUILD_DIR" ]; then
    echo "Usage: $0 <project_dir> <build_dir>"
    exit 1
fi

# Check for required tools
for cmd in wget 7z xorriso genisoimage mkisofs; do
    if ! command -v $cmd >/dev/null 2>&1; then
        if [ "$cmd" = "xorriso" ] || [ "$cmd" = "genisoimage" ] || [ "$cmd" = "mkisofs" ]; then
            # Check if any ISO creation tool is available
            if ! command -v xorriso >/dev/null 2>&1 && ! command -v genisoimage >/dev/null 2>&1 && ! command -v mkisofs >/dev/null 2>&1; then
                echo "Error: No ISO creation tool found. Please install xorriso, genisoimage, or mkisofs"
                exit 1
            fi
        else
            echo "Error: Required tool not found: $cmd"
            exit 1
        fi
    fi
done

# Find ISO creation tool
ISO_TOOL=""
if command -v xorriso >/dev/null 2>&1; then
    ISO_TOOL="xorriso"
elif command -v genisoimage >/dev/null 2>&1; then
    ISO_TOOL="genisoimage"
elif command -v mkisofs >/dev/null 2>&1; then
    ISO_TOOL="mkisofs"
fi

echo "Using ISO tool: $ISO_TOOL"

# Find Yocto image files
IMAGE_DIR="$BUILD_DIR/tmp-glibc/deploy/images/qemux86-64"
if [ ! -d "$IMAGE_DIR" ]; then
    echo "Error: Image directory not found: $IMAGE_DIR"
    echo "Please build the image first with: ./setup-yocto.sh --build"
    exit 1
fi

# Find rootfs
ROOTFS=$(find "$IMAGE_DIR" -name "bbdemo-image-qemux86-64.rootfs.ext4" -o -name "bbdemo-image-qemux86-64.rootfs-*.ext4" | head -1)
if [ -z "$ROOTFS" ]; then
    echo "Error: Rootfs image not found in $IMAGE_DIR"
    exit 1
fi

echo "Found rootfs: $(basename "$ROOTFS")"

# Create work directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "Work directory: $WORK_DIR"

# Step 1: Create disk image from rootfs
echo ""
echo "Step 1: Creating disk image from rootfs..."
DISK_IMAGE="$WORK_DIR/bbdemo-disk.img"
"$SCRIPT_DIR/create-disk-image.sh" "$ROOTFS" "$DISK_IMAGE" 2048

# Step 2: Download Clonezilla Live (ISO or ZIP)
echo ""
echo "Step 2: Downloading Clonezilla Live..."
# Try a few known working versions (in order of preference)
# Note: Newer versions may be distributed as ZIP files
CLONEZILLA_VERSIONS=("3.3.0-33" "3.1.1-22" "3.1.0-21" "3.0.3-19")
CLONEZILLA_VERSION=""
CLONEZILLA_FILE=""

DOWNLOAD_DIR="$PROJECT_DIR/downloads"
mkdir -p "$DOWNLOAD_DIR"

# Check if any version already exists (ISO or ZIP)
for version in "${CLONEZILLA_VERSIONS[@]}"; do
    # Try both ISO and ZIP formats
    for ext in zip iso; do
        file="clonezilla-live-${version}-amd64.${ext}"
        path="$DOWNLOAD_DIR/$file"
        if [ -f "$path" ]; then
            CLONEZILLA_VERSION="$version"
            CLONEZILLA_FILE="$file"
            CLONEZILLA_PATH="$path"
            echo "Found existing Clonezilla file: $file"
            break 2
        fi
    done
done

# If no existing file found, try to download
if [ -z "$CLONEZILLA_VERSION" ]; then
    for version in "${CLONEZILLA_VERSIONS[@]}"; do
        # Try ZIP first (newer format), then ISO
        for ext in zip iso; do
            CLONEZILLA_VERSION="$version"
            CLONEZILLA_FILE="clonezilla-live-${version}-amd64.${ext}"
            CLONEZILLA_PATH="$DOWNLOAD_DIR/$CLONEZILLA_FILE"
            
            echo "Attempting to download Clonezilla Live ${version} (${ext})..."
            
            # Try downloads.sourceforge.net first (more reliable)
            CLONEZILLA_URL="https://downloads.sourceforge.net/project/clonezilla/clonezilla_live_stable/${version}/${CLONEZILLA_FILE}?r=&ts=$(date +%s)"
            
            if wget --progress=bar:force -O "$CLONEZILLA_PATH" "$CLONEZILLA_URL" 2>&1 | grep -qE "(200 OK|saved|100%)"; then
                echo "Successfully downloaded ${CLONEZILLA_FILE}"
                break 2
            else
                rm -f "$CLONEZILLA_PATH"
            fi
        done
        CLONEZILLA_VERSION=""
        CLONEZILLA_FILE=""
    done
fi

# If still no file, provide manual download instructions
if [ -z "$CLONEZILLA_VERSION" ] || [ ! -f "$CLONEZILLA_PATH" ]; then
    echo ""
    echo "Error: Failed to download Clonezilla automatically"
    echo ""
    echo "Please manually download Clonezilla Live from:"
    echo "  https://clonezilla.org/downloads.php"
    echo "  Or: https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/"
    echo ""
    echo "Look for: clonezilla-live-*-amd64.zip or clonezilla-live-*-amd64.iso"
    echo "Then place it in: $DOWNLOAD_DIR/"
    echo ""
    echo "Supported versions (rename if needed):"
    for version in "${CLONEZILLA_VERSIONS[@]}"; do
        echo "  - clonezilla-live-${version}-amd64.zip (preferred)"
        echo "  - clonezilla-live-${version}-amd64.iso"
    done
    echo ""
    exit 1
fi

echo "Using Clonezilla file: $CLONEZILLA_FILE ($(du -h "$CLONEZILLA_PATH" | cut -f1))"

# Step 3: Extract Clonezilla (ISO or ZIP)
echo ""
echo "Step 3: Extracting Clonezilla..."
CLONEZILLA_EXTRACT="$WORK_DIR/clonezilla-extract"
mkdir -p "$CLONEZILLA_EXTRACT"

if [ ! -f "$CLONEZILLA_PATH" ]; then
    echo "Error: Clonezilla file not found"
    exit 1
fi

# Check file type
FILE_TYPE=$(file -b "$CLONEZILLA_PATH")

if echo "$FILE_TYPE" | grep -qi "zip"; then
    # It's a ZIP file - extract it
    echo "Detected ZIP archive, extracting..."
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$CLONEZILLA_PATH" -d "$CLONEZILLA_EXTRACT" || {
            echo "Error: Failed to extract ZIP file"
            exit 1
        }
    else
        echo "Error: unzip not found. Please install unzip"
        exit 1
    fi
elif echo "$FILE_TYPE" | grep -qi "iso"; then
    # It's an ISO file - extract or mount it
    echo "Detected ISO image, extracting..."
    if command -v 7z >/dev/null 2>&1; then
        7z x -o"$CLONEZILLA_EXTRACT" "$CLONEZILLA_PATH" >/dev/null 2>&1 || {
            # If 7z fails, try mounting
            ISO_MOUNT=$(mktemp -d)
            mount -o loop "$CLONEZILLA_PATH" "$ISO_MOUNT" 2>/dev/null || {
                echo "Error: Cannot extract or mount Clonezilla ISO"
                rmdir "$ISO_MOUNT"
                exit 1
            }
            cp -a "$ISO_MOUNT"/* "$CLONEZILLA_EXTRACT/" 2>/dev/null || true
            umount "$ISO_MOUNT"
            rmdir "$ISO_MOUNT"
        }
    else
        # Fallback to mounting
        ISO_MOUNT=$(mktemp -d)
        mount -o loop "$CLONEZILLA_PATH" "$ISO_MOUNT" 2>/dev/null || {
            echo "Error: Cannot mount Clonezilla ISO. Please install 7z or ensure you have mount permissions"
            rmdir "$ISO_MOUNT"
            exit 1
        }
        cp -a "$ISO_MOUNT"/* "$CLONEZILLA_EXTRACT/" 2>/dev/null || true
        umount "$ISO_MOUNT"
        rmdir "$ISO_MOUNT"
    fi
else
    echo "Error: Unknown file type: $FILE_TYPE"
    echo "Expected ZIP archive or ISO image"
    exit 1
fi

# Verify extraction was successful
if [ ! -d "$CLONEZILLA_EXTRACT/boot" ] && [ ! -d "$CLONEZILLA_EXTRACT/EFI" ]; then
    echo "Error: Extracted Clonezilla doesn't contain expected boot structure"
    echo "Found directories:"
    ls -d "$CLONEZILLA_EXTRACT"/*/ 2>/dev/null | head -10
    exit 1
fi

# Step 4: Embed disk image into Clonezilla ISO
echo ""
echo "Step 4: Embedding disk image into Clonezilla ISO..."
# Copy disk image to ISO root
cp "$DISK_IMAGE" "$CLONEZILLA_EXTRACT/bbdemo-disk.img"

# Step 5: Generate Clonezilla configuration
echo ""
echo "Step 5: Generating Clonezilla configuration..."
"$SCRIPT_DIR/clonezilla-config.sh" "$WORK_DIR" "$DISK_IMAGE" "$WORK_DIR/ocs-iso.cfg"

# Copy configuration to ISO
# Clonezilla looks for config in multiple locations
CLONEZILLA_CFG_DIR="$CLONEZILLA_EXTRACT/ocs"
mkdir -p "$CLONEZILLA_CFG_DIR"
cp "$WORK_DIR/ocs-iso.cfg" "$CLONEZILLA_CFG_DIR/ocs-iso.cfg"

# Also create a simple README for users
cat > "$CLONEZILLA_EXTRACT/BBDEMO-README.txt" << 'README_EOF'
========================================
BBDemo Image Restore ISO
========================================

This Clonezilla Live ISO contains a BBDemo disk image that can be
restored to a physical device.

USAGE:
1. Boot from this USB/CD
2. Select "Clonezilla" from the boot menu
3. Choose "device-image" mode
4. Select the target disk when prompted
5. Confirm the restore operation

WARNING: This will overwrite all data on the selected disk!

The disk image is embedded in this ISO and will be automatically
detected by Clonezilla.

Image file: bbdemo-disk.img
README_EOF

# Step 6: Create bootable ISO with UEFI support
echo ""
echo "Step 6: Creating bootable ISO (BIOS + UEFI)..."

TIMESTAMP=$(date +%Y%m%d%H%M%S)
OUTPUT_ISO="$PROJECT_DIR/bbdemo-image-${TIMESTAMP}.iso"

# Find boot files
ISOLINUX_BIN=""
ISOLINUX_CAT=""
EFI_BOOT_IMG=""
EFI_BOOT_FILE=""

# Find isolinux files (BIOS boot)
if [ -f "$CLONEZILLA_EXTRACT/isolinux/isolinux.bin" ]; then
    ISOLINUX_BIN="$CLONEZILLA_EXTRACT/isolinux/isolinux.bin"
    ISOLINUX_CAT="$CLONEZILLA_EXTRACT/isolinux/boot.cat"
elif [ -f "$CLONEZILLA_EXTRACT/boot/isolinux/isolinux.bin" ]; then
    ISOLINUX_BIN="$CLONEZILLA_EXTRACT/boot/isolinux/isolinux.bin"
    ISOLINUX_CAT="$CLONEZILLA_EXTRACT/boot/isolinux/boot.cat"
elif [ -f "$CLONEZILLA_EXTRACT/syslinux/isolinux.bin" ]; then
    ISOLINUX_BIN="$CLONEZILLA_EXTRACT/syslinux/isolinux.bin"
    ISOLINUX_CAT="$CLONEZILLA_EXTRACT/syslinux/boot.cat"
fi

# Find EFI boot files (UEFI boot)
if [ -f "$CLONEZILLA_EXTRACT/EFI/boot/bootx64.efi" ]; then
    EFI_BOOT_FILE="$CLONEZILLA_EXTRACT/EFI/boot/bootx64.efi"
elif [ -f "$CLONEZILLA_EXTRACT/EFI/boot/grubx64.efi" ]; then
    EFI_BOOT_FILE="$CLONEZILLA_EXTRACT/EFI/boot/grubx64.efi"
fi

# Create a temporary EFI boot image for UEFI boot
if [ -n "$EFI_BOOT_FILE" ] && [ -d "$CLONEZILLA_EXTRACT/EFI/boot" ]; then
    echo "Preparing UEFI boot image..."
    EFI_BOOT_IMG="$WORK_DIR/efiboot.img"
    # Create a FAT32 image for EFI boot
    EFI_SIZE=4096  # 4MB should be enough
    dd if=/dev/zero of="$EFI_BOOT_IMG" bs=1K count=$EFI_SIZE 2>/dev/null
    mkfs.vfat -F 32 -n "EFIBOOT" "$EFI_BOOT_IMG" >/dev/null 2>&1 || {
        # Fallback if mkfs.vfat not available
        mkfs.fat -F 32 "$EFI_BOOT_IMG" >/dev/null 2>&1 || true
    }
    
    # Mount and copy EFI files
    EFI_MOUNT=$(mktemp -d)
    if mount -o loop "$EFI_BOOT_IMG" "$EFI_MOUNT" 2>/dev/null; then
        mkdir -p "$EFI_MOUNT/EFI/boot"
        cp -a "$CLONEZILLA_EXTRACT/EFI/boot"/* "$EFI_MOUNT/EFI/boot/" 2>/dev/null || true
        umount "$EFI_MOUNT"
        rmdir "$EFI_MOUNT"
    else
        # If mounting fails, try using mcopy from mtools
        if command -v mcopy >/dev/null 2>&1; then
            mcopy -i "$EFI_BOOT_IMG" -s "$CLONEZILLA_EXTRACT/EFI"/* ::EFI/ 2>/dev/null || true
        fi
    fi
fi

# Create ISO using appropriate tool
cd "$CLONEZILLA_EXTRACT"

if [ "$ISO_TOOL" = "xorriso" ]; then
    # Use xorriso for better UEFI support
    echo "Creating hybrid ISO (BIOS + UEFI) with xorriso..."
    
    # Build xorriso command
    XORRISO_ARGS=(
        -as mkisofs
        -iso-level 3
        -full-iso9660-filenames
        -volid "BBDEMO-IMAGE"
    )
    
    # Add BIOS boot (isolinux)
    if [ -f "$CLONEZILLA_EXTRACT/isolinux/isolinux.bin" ]; then
        XORRISO_ARGS+=(
            -eltorito-boot isolinux/isolinux.bin
            -no-emul-boot -boot-load-size 4 -boot-info-table
        )
    elif [ -f "$CLONEZILLA_EXTRACT/boot/isolinux/isolinux.bin" ]; then
        XORRISO_ARGS+=(
            -eltorito-boot boot/isolinux/isolinux.bin
            -no-emul-boot -boot-load-size 4 -boot-info-table
        )
    elif [ -f "$CLONEZILLA_EXTRACT/syslinux/isolinux.bin" ]; then
        XORRISO_ARGS+=(
            -eltorito-boot syslinux/isolinux.bin
            -no-emul-boot -boot-load-size 4 -boot-info-table
        )
    fi
    
    # Add UEFI boot
    # xorriso supports -e for EFI boot, but we need efiboot.img file
    if [ -n "$EFI_BOOT_IMG" ] && [ -f "$EFI_BOOT_IMG" ]; then
        cp "$EFI_BOOT_IMG" "$CLONEZILLA_EXTRACT/efiboot.img"
        XORRISO_ARGS+=(
            -eltorito-alt-boot
            -e efiboot.img
            -no-emul-boot
        )
    elif [ -f "$CLONEZILLA_EXTRACT/EFI/boot/bootx64.efi" ] || [ -f "$CLONEZILLA_EXTRACT/EFI/boot/grubx64.efi" ]; then
        # Create EFI boot image if not already created
        if [ ! -f "$EFI_BOOT_IMG" ]; then
            echo "Creating EFI boot image for xorriso..."
            EFI_BOOT_IMG="$WORK_DIR/efiboot.img"
            EFI_SIZE=4096
            dd if=/dev/zero of="$EFI_BOOT_IMG" bs=1K count=$EFI_SIZE 2>/dev/null
            mkfs.vfat -F 32 -n "EFIBOOT" "$EFI_BOOT_IMG" >/dev/null 2>&1 || \
                mkfs.fat -F 32 "$EFI_BOOT_IMG" >/dev/null 2>&1 || true
            
            EFI_MOUNT=$(mktemp -d)
            if mount -o loop "$EFI_BOOT_IMG" "$EFI_MOUNT" 2>/dev/null; then
                mkdir -p "$EFI_MOUNT/EFI/boot"
                cp -a "$CLONEZILLA_EXTRACT/EFI/boot"/* "$EFI_MOUNT/EFI/boot/" 2>/dev/null || true
                umount "$EFI_MOUNT"
                rmdir "$EFI_MOUNT"
            fi
        fi
        cp "$EFI_BOOT_IMG" "$CLONEZILLA_EXTRACT/efiboot.img"
        XORRISO_ARGS+=(
            -eltorito-alt-boot
            -e efiboot.img
            -no-emul-boot
        )
    fi
    
    # Add isohybrid for USB boot support
    if [ -f /usr/lib/syslinux/isohdpfx.bin ]; then
        XORRISO_ARGS+=(
            -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin
            -isohybrid-gpt-basdat
        )
    fi
    
    XORRISO_ARGS+=(-output "$OUTPUT_ISO" .)
    
    xorriso "${XORRISO_ARGS[@]}" 2>&1 | grep -vE "(UPDATE|libisofs)" || true
    
elif [ "$ISO_TOOL" = "genisoimage" ] || [ "$ISO_TOOL" = "mkisofs" ]; then
    # genisoimage/mkisofs with UEFI support
    # Note: genisoimage has limited UEFI support, so we'll use xorriso if available
    # or create a proper hybrid ISO
    
    # Prefer xorriso for better UEFI support even if genisoimage is available
    if command -v xorriso >/dev/null 2>&1; then
        echo "Using xorriso instead of $ISO_TOOL for better UEFI support..."
        ISO_TOOL="xorriso"
        # Re-run with xorriso (will be handled in the xorriso section above)
        # But we need to rebuild the command here
        XORRISO_ARGS=(
            -as mkisofs
            -iso-level 3
            -full-iso9660-filenames
            -volid "BBDEMO-IMAGE"
        )
        
        # Add BIOS boot
        if [ -f "$CLONEZILLA_EXTRACT/isolinux/isolinux.bin" ]; then
            XORRISO_ARGS+=(
                -eltorito-boot isolinux/isolinux.bin
                -no-emul-boot -boot-load-size 4 -boot-info-table
            )
        elif [ -f "$CLONEZILLA_EXTRACT/boot/isolinux/isolinux.bin" ]; then
            XORRISO_ARGS+=(
                -eltorito-boot boot/isolinux/isolinux.bin
                -no-emul-boot -boot-load-size 4 -boot-info-table
            )
        fi
        
        # Add UEFI boot with efiboot.img
        if [ -n "$EFI_BOOT_IMG" ] && [ -f "$EFI_BOOT_IMG" ]; then
            cp "$EFI_BOOT_IMG" "$CLONEZILLA_EXTRACT/efiboot.img"
            XORRISO_ARGS+=(
                -eltorito-alt-boot
                -e efiboot.img
                -no-emul-boot
            )
        elif [ -f "$CLONEZILLA_EXTRACT/EFI/boot/bootx64.efi" ] || [ -f "$CLONEZILLA_EXTRACT/EFI/boot/grubx64.efi" ]; then
            if [ ! -f "$EFI_BOOT_IMG" ]; then
                echo "Creating EFI boot image..."
                EFI_BOOT_IMG="$WORK_DIR/efiboot.img"
                EFI_SIZE=4096
                dd if=/dev/zero of="$EFI_BOOT_IMG" bs=1K count=$EFI_SIZE 2>/dev/null
                mkfs.vfat -F 32 -n "EFIBOOT" "$EFI_BOOT_IMG" >/dev/null 2>&1 || \
                    mkfs.fat -F 32 "$EFI_BOOT_IMG" >/dev/null 2>&1 || true
                
                EFI_MOUNT=$(mktemp -d)
                if mount -o loop "$EFI_BOOT_IMG" "$EFI_MOUNT" 2>/dev/null; then
                    mkdir -p "$EFI_MOUNT/EFI/boot"
                    cp -a "$CLONEZILLA_EXTRACT/EFI/boot"/* "$EFI_MOUNT/EFI/boot/" 2>/dev/null || true
                    umount "$EFI_MOUNT"
                    rmdir "$EFI_MOUNT"
                fi
            fi
            cp "$EFI_BOOT_IMG" "$CLONEZILLA_EXTRACT/efiboot.img"
            XORRISO_ARGS+=(
                -eltorito-alt-boot
                -e efiboot.img
                -no-emul-boot
            )
        fi
        
        # Add hybrid support for USB
        if [ -f /usr/lib/syslinux/isohdpfx.bin ]; then
            XORRISO_ARGS+=(
                -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin
                -isohybrid-gpt-basdat
            )
        fi
        
        XORRISO_ARGS+=(-output "$OUTPUT_ISO" .)
        xorriso "${XORRISO_ARGS[@]}" 2>&1 | grep -vE "(UPDATE|libisofs)" || true
    else
        # Fallback to genisoimage/mkisofs (limited UEFI support)
        echo "Creating hybrid ISO (BIOS + UEFI) with $ISO_TOOL..."
        echo "Warning: $ISO_TOOL has limited UEFI support. Consider installing xorriso for better results."
        
        GENISO_ARGS=(
            -iso-level 3
            -full-iso9660-filenames
            -volid "BBDEMO-IMAGE"
        )
        
        # Add BIOS boot
        if [ -f "$CLONEZILLA_EXTRACT/isolinux/isolinux.bin" ]; then
            GENISO_ARGS+=(
                -b isolinux/isolinux.bin
                -c isolinux/boot.cat
                -no-emul-boot -boot-load-size 4 -boot-info-table
            )
        elif [ -f "$CLONEZILLA_EXTRACT/boot/isolinux/isolinux.bin" ]; then
            GENISO_ARGS+=(
                -b boot/isolinux/isolinux.bin
                -c boot/isolinux/boot.cat
                -no-emul-boot -boot-load-size 4 -boot-info-table
            )
        fi
        
        # Add UEFI boot (genisoimage/mkisofs needs EFI boot image file)
        if [ -n "$EFI_BOOT_IMG" ] && [ -f "$EFI_BOOT_IMG" ]; then
            cp "$EFI_BOOT_IMG" "$CLONEZILLA_EXTRACT/efiboot.img"
            GENISO_ARGS+=(
                -eltorito-alt-boot
                -b efiboot.img
                -no-emul-boot
            )
        elif [ -f "$CLONEZILLA_EXTRACT/EFI/boot/bootx64.efi" ] || [ -f "$CLONEZILLA_EXTRACT/EFI/boot/grubx64.efi" ]; then
            echo "Creating EFI boot image from EFI files..."
            EFI_BOOT_IMG="$WORK_DIR/efiboot.img"
            EFI_SIZE=4096
            dd if=/dev/zero of="$EFI_BOOT_IMG" bs=1K count=$EFI_SIZE 2>/dev/null
            mkfs.vfat -F 32 -n "EFIBOOT" "$EFI_BOOT_IMG" >/dev/null 2>&1 || \
                mkfs.fat -F 32 "$EFI_BOOT_IMG" >/dev/null 2>&1 || true
            
            EFI_MOUNT=$(mktemp -d)
            if mount -o loop "$EFI_BOOT_IMG" "$EFI_MOUNT" 2>/dev/null; then
                mkdir -p "$EFI_MOUNT/EFI/boot"
                cp -a "$CLONEZILLA_EXTRACT/EFI/boot"/* "$EFI_MOUNT/EFI/boot/" 2>/dev/null || true
                umount "$EFI_MOUNT"
                rmdir "$EFI_MOUNT"
            fi
            
            cp "$EFI_BOOT_IMG" "$CLONEZILLA_EXTRACT/efiboot.img"
            GENISO_ARGS+=(
                -eltorito-alt-boot
                -b efiboot.img
                -no-emul-boot
            )
        fi
        
        # Add isohybrid
        if [ -f /usr/lib/syslinux/isohdpfx.bin ]; then
            GENISO_ARGS+=(-isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin)
        fi
        
        GENISO_ARGS+=(-o "$OUTPUT_ISO" .)
        
        $ISO_TOOL "${GENISO_ARGS[@]}" 2>&1 | grep -v "UPDATE" || true
        
        # Make it hybrid bootable for USB
        if command -v isohybrid >/dev/null 2>&1; then
            echo "Making ISO hybrid bootable for USB with isohybrid..."
            isohybrid "$OUTPUT_ISO" 2>/dev/null || true
        fi
    fi
fi

# Verify ISO was created
if [ ! -f "$OUTPUT_ISO" ]; then
    echo "Error: Failed to create ISO"
    exit 1
fi

# Post-process ISO to ensure it's properly bootable
echo ""
echo "Post-processing ISO for USB boot compatibility..."

# Use isohybrid if available to make it USB-bootable with UEFI support
if command -v isohybrid >/dev/null 2>&1; then
    echo "Applying isohybrid to make ISO USB-bootable with UEFI support..."
    # Try --uefi first (for UEFI support), fallback to regular
    isohybrid --uefi "$OUTPUT_ISO" 2>/dev/null || \
    isohybrid "$OUTPUT_ISO" 2>/dev/null || true
fi

# Also try using xorriso to add GPT partition table for better UEFI support
if command -v xorriso >/dev/null 2>&1 && [ ! -f "$OUTPUT_ISO.gpt" ]; then
    echo "Adding GPT partition table for UEFI boot..."
    # xorriso can add GPT support to existing ISO
    xorriso -indev "$OUTPUT_ISO" \
        -boot_image any gpt_dir=. \
        -outdev "$OUTPUT_ISO.gpt" 2>/dev/null && \
        mv "$OUTPUT_ISO.gpt" "$OUTPUT_ISO" || true
fi

# Verify boot structure
echo "Verifying boot structure..."
if command -v file >/dev/null 2>&1; then
    ISO_TYPE=$(file "$OUTPUT_ISO")
    echo "ISO type: $ISO_TYPE"
fi

# Check if EFI files are accessible in the ISO
echo "Checking for EFI boot files..."
if command -v 7z >/dev/null 2>&1 || command -v isoinfo >/dev/null 2>&1; then
    if command -v isoinfo >/dev/null 2>&1; then
        if isoinfo -i "$OUTPUT_ISO" -l 2>/dev/null | grep -q "EFI/boot"; then
            echo "✓ EFI boot files found in ISO"
        else
            echo "⚠ Warning: EFI boot files may not be accessible in ISO"
        fi
    fi
fi

echo ""
echo "=========================================="
echo "ISO created successfully!"
echo "=========================================="
echo ""
echo "Output: $OUTPUT_ISO"
echo "Size: $(du -h "$OUTPUT_ISO" | cut -f1)"
echo ""
echo "To use this ISO:"
echo "  1. Burn to USB: sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress oflag=sync"
echo "     (Replace sdX with your USB device, e.g., sdb)"
echo "     WARNING: This will erase all data on the USB drive!"
echo "  2. Sync to ensure all data is written: sync"
echo "  3. Verify USB structure: sudo ./scripts/check-usb.sh /dev/sdX"
echo "  4. Boot from USB on target device"
echo "  5. In UEFI BIOS, ensure 'UEFI Boot' or 'EFI' mode is enabled"
echo "  6. Clonezilla will prompt you to select the target disk"
echo "  7. The BBDemo image will be restored to the selected disk"
echo ""
echo "Troubleshooting:"
echo "  - If USB doesn't boot, run: sudo ./scripts/check-usb.sh /dev/sdX"
echo "  - Check BIOS/UEFI settings (enable UEFI boot)"
echo "  - Try different USB ports or USB 2.0 port"
echo "  - Ensure Secure Boot is disabled if having issues"
echo "  - Alternative: Use a tool like 'balena-etcher' or 'Rufus' to write the ISO"
echo "    These tools properly handle UEFI boot structure"
echo ""
echo "Alternative: Create USB image directly (better UEFI support):"
echo "  sudo bash scripts/create-usb-image.sh $PROJECT_DIR $BUILD_DIR usb-image.img"
echo "  sudo dd if=usb-image.img of=/dev/sdX bs=4M status=progress oflag=sync"
echo ""

