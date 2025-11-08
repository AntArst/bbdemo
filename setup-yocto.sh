#!/bin/bash
# Yocto Project Setup Script for BBDemo
# This script initializes the Yocto build environment
# Usage: ./setup-yocto.sh [--build] [--run] [--image]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POKY_DIR="$SCRIPT_DIR/poky"
BUILD_DIR="$SCRIPT_DIR/build"

# Parse command line arguments
BUILD_IMAGE=false
RUN_IMAGE=false
CREATE_IMAGE=false
for arg in "$@"; do
    case "$arg" in
        --build|-b)
            BUILD_IMAGE=true
            ;;
        --run|-r)
            RUN_IMAGE=true
            ;;
        --image|-i)
            CREATE_IMAGE=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--build] [--run] [--image]"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "Yocto Project Setup for BBDemo"
echo "=========================================="

# Check if Poky already exists
if [ -d "$POKY_DIR" ]; then
    echo "Poky directory already exists. Skipping clone..."
else
    echo "Cloning Poky (Yocto reference distribution)..."
    # Clone latest LTS branch (Scarthgap 5.0)
    git clone -b scarthgap https://git.yoctoproject.org/git/poky "$POKY_DIR"
    echo "Poky cloned successfully."
fi

# Check if build directory exists
if [ -d "$BUILD_DIR" ]; then
    echo "Build directory already exists."
else
    echo "Creating build directory..."
    mkdir -p "$BUILD_DIR"
fi

# Copy configuration files to build directory
echo "Setting up build configuration..."
mkdir -p "$BUILD_DIR/conf"

if [ ! -f "$BUILD_DIR/conf/local.conf" ]; then
    cp "$SCRIPT_DIR/conf/local.conf" "$BUILD_DIR/conf/"
    echo "Created build/conf/local.conf"
fi

if [ ! -f "$BUILD_DIR/conf/bblayers.conf" ]; then
    cp "$SCRIPT_DIR/conf/bblayers.conf" "$BUILD_DIR/conf/"
    # Update paths in bblayers.conf
    sed -i "s|##OEROOT##|$POKY_DIR|g" "$BUILD_DIR/conf/bblayers.conf"
    sed -i "s|##PROJECTROOT##|$SCRIPT_DIR|g" "$BUILD_DIR/conf/bblayers.conf"
    echo "Created build/conf/bblayers.conf"
fi

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="

# Build the image if requested
if [ "$BUILD_IMAGE" = true ]; then
    echo ""
    echo "=========================================="
    echo "Building bbdemo-image..."
    echo "=========================================="
    echo ""
    
    # Check if Poky's oe-init-build-env exists
    if [ ! -f "$POKY_DIR/oe-init-build-env" ]; then
        echo "Error: Poky's oe-init-build-env not found. Please ensure Poky is properly cloned."
        exit 1
    fi
    
    # Source the build environment and run bitbake
    # We need to source in the current shell to preserve environment variables
    cd "$POKY_DIR"
    source "$POKY_DIR/oe-init-build-env" "$BUILD_DIR" > /dev/null
    echo "Build environment initialized."
    echo "Starting image build (this may take a while)..."
    echo ""
    bitbake bbdemo-image
    
    echo ""
    echo "=========================================="
    echo "Build complete!"
    echo "=========================================="
    echo ""
fi

# Run the image if requested
if [ "$RUN_IMAGE" = true ]; then
    echo ""
    echo "=========================================="
    echo "Running bbdemo-image in QEMU..."
    echo "=========================================="
    echo ""
    
    # Check if build directory exists
    if [ ! -d "$BUILD_DIR" ]; then
        echo "Error: Build directory not found. Please run setup first."
        exit 1
    fi
    
    # Check if Poky's oe-init-build-env exists
    if [ ! -f "$POKY_DIR/oe-init-build-env" ]; then
        echo "Error: Poky's oe-init-build-env not found. Please ensure Poky is properly cloned."
        exit 1
    fi
    
    # Check if image exists
    IMAGE_DIR="$BUILD_DIR/tmp-glibc/deploy/images/qemux86-64"
    if [ ! -d "$IMAGE_DIR" ]; then
        echo "Error: Image directory not found. Please build the image first with --build"
        exit 1
    fi
    
    # Check if rootfs exists
    ROOTFS=$(find "$IMAGE_DIR" -name "bbdemo-image-qemux86-64.rootfs.ext4" -o -name "bbdemo-image-qemux86-64.rootfs-*.ext4" | head -1)
    if [ -z "$ROOTFS" ]; then
        echo "Error: Rootfs image not found. Please build the image first with --build"
        exit 1
    fi
    
    echo "Found image: $(basename "$ROOTFS")"
    echo "Starting QEMU with serial console..."
    echo ""
    echo "Note: You can interact with the console directly."
    echo "      To exit QEMU, press Ctrl+A then X"
    echo ""
    
    # Source the build environment and run QEMU
    cd "$POKY_DIR"
    source "$POKY_DIR/oe-init-build-env" "$BUILD_DIR" > /dev/null
    # Use serialstdio to get an interactive console
    runqemu qemux86-64 serialstdio
fi

# Create Clonezilla ISO if requested
if [ "$CREATE_IMAGE" = true ]; then
    echo ""
    echo "=========================================="
    echo "Creating Clonezilla ISO package..."
    echo "=========================================="
    echo ""
    
    # Check if packaging script exists
    PACKAGE_SCRIPT="$SCRIPT_DIR/scripts/package-image.sh"
    if [ ! -f "$PACKAGE_SCRIPT" ]; then
        echo "Error: Packaging script not found at $PACKAGE_SCRIPT"
        exit 1
    fi
    
    # Check if build directory exists
    if [ ! -d "$BUILD_DIR" ]; then
        echo "Error: Build directory not found. Please build the image first with --build"
        exit 1
    fi
    
    # Run the packaging script
    bash "$PACKAGE_SCRIPT" "$SCRIPT_DIR" "$BUILD_DIR"
    
    echo ""
    echo "=========================================="
    echo "ISO packaging complete!"
    echo "=========================================="
    echo ""
fi

# Show help if no actions were requested
if [ "$BUILD_IMAGE" != true ] && [ "$RUN_IMAGE" != true ] && [ "$CREATE_IMAGE" != true ]; then
    echo ""
    echo "To start building, run:"
    echo "  cd $POKY_DIR"
    echo "  source oe-init-build-env $BUILD_DIR"
    echo "  bitbake bbdemo-image"
    echo ""
    echo "Or use the --build flag to build automatically:"
    echo "  ./setup-yocto.sh --build"
    echo ""
    echo "To run the image in QEMU:"
    echo "  ./setup-yocto.sh --run"
    echo ""
    echo "To create a Clonezilla ISO for deployment:"
    echo "  ./setup-yocto.sh --image"
    echo ""
fi

