#!/bin/bash
# Yocto Project Setup Script for BBDemo
# This script initializes the Yocto build environment
# Usage: ./setup-yocto.sh [--build]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POKY_DIR="$SCRIPT_DIR/poky"
BUILD_DIR="$SCRIPT_DIR/build"

# Parse command line arguments
BUILD_IMAGE=false
if [[ "$1" == "--build" ]] || [[ "$1" == "-b" ]]; then
    BUILD_IMAGE=true
fi

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
    echo "To run the image in QEMU:"
    echo "  cd $POKY_DIR"
    echo "  source oe-init-build-env $BUILD_DIR"
    echo "  runqemu qemux86-64"
    echo ""
else
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
    echo "  runqemu qemux86-64"
    echo ""
fi

