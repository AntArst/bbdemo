# BBDemo - Yocto BusyBox VM Build System

This project demonstrates how to build a minimal Linux VM image using Yocto and BitBake, featuring BusyBox and custom applications.

**Note:** This project uses Yocto Project Scarthgap 5.0 (LTS release).

## Overview

The project creates a bootable Linux image for x86_64 QEMU that includes:
- BusyBox as the init system and core utilities
- Custom applications (example: hello-bbdemo)
- SSH server for remote access
- Minimal footprint suitable for embedded systems

## Prerequisites

Before starting, ensure you have the following installed:

- **Git** - For cloning Poky
- **Python 3** - Required by BitBake
- **Build tools** - gcc, make, and other standard build utilities
- **Development libraries** - For building packages
- **QEMU** - For running the built image (optional, for testing)

On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y gawk wget git-core diffstat unzip texinfo \
    gcc-multilib build-essential chrpath socat cpio python3 python3-pip \
    python3-pexpect xz-utils debianutils iputils-ping python3-git \
    python3-jinja2 libegl1-mesa libsdl1.2-dev pylint3 xterm qemu-system-x86
```

On Fedora/RHEL:
```bash
sudo dnf install -y gawk make wget tar bzip2 gzip python3 unzip perl patch \
    diffutils diffstat git cpp gcc gcc-c++ glibc-devel texinfo chrpath \
    ccache perl-Data-Dumper perl-Text-ParseWords perl-Thread-Queue \
    perl-bignum xz which SDL-devel xterm rpcgen mesa-libGL-devel perl-FindBin \
    perl-File-Compare perl-File-Copy perl-locale zstd qemu-system-x86
```

## Project Structure

```
bbdemo/
├── README.md                          # This file
├── setup-yocto.sh                     # Yocto environment setup script
├── conf/
│   ├── local.conf                     # Local build configuration
│   └── bblayers.conf                  # Layer configuration
├── meta-bbdemo/                       # Custom layer
│   ├── conf/
│   │   └── layer.conf                 # Layer metadata
│   ├── recipes-core/
│   │   └── images/
│   │       └── bbdemo-image.bb        # Custom image recipe
│   └── recipes-apps/
│       └── hello-bbdemo/
│           ├── hello-bbdemo_1.0.bb    # Custom app recipe
│           └── files/
│               ├── hello-bbdemo.c     # Example C application
│               └── Makefile           # Build instructions
└── .gitignore                         # Git ignore patterns
```

## Setup Instructions

### 1. Initialize Yocto Environment

Run the setup script to clone Poky and prepare the build environment:

```bash
chmod +x setup-yocto.sh
./setup-yocto.sh
```

Or to automatically build the image after setup:

```bash
./setup-yocto.sh --build
# or
./setup-yocto.sh -b
```

This will:
- Clone the Poky repository (Yocto reference distribution)
- Create the build directory structure
- Copy configuration files
- (Optional) Build the image if `--build` flag is used

### 2. Enter Build Environment

If you didn't use the `--build` flag, navigate to the Poky directory and source the build environment:

```bash
cd poky
source oe-init-build-env ../build
```

This script sets up the BitBake environment and changes your working directory to the build directory.

### 3. Build the Image

If you didn't use the `--build` flag during setup, build the bbdemo-image:

```bash
bitbake bbdemo-image
```

**Note:** The first build can take several hours as it downloads and compiles all dependencies. Subsequent builds will be much faster thanks to shared state caching.

### 4. Run in QEMU

After a successful build, you can run the image in QEMU:

```bash
runqemu qemux86-64
```

Or manually:

```bash
runqemu qemux86-64 nographic
```

## Using the Built Image

### Login

The default login credentials are:
- **Username:** root
- **Password:** (empty, no password)

### Test Custom Application

Once logged in, test the custom hello-bbdemo application:

```bash
hello-bbdemo
hello-bbdemo test argument
```

### SSH Access

SSH server is enabled. From your host machine, you can connect:

```bash
ssh root@<qemu-ip-address>
```

The IP address will be shown when QEMU starts, or you can check with `ifconfig` inside the VM.

## Adding Custom Applications

To add your own custom applications:

1. **Create a recipe directory:**
   ```bash
   mkdir -p meta-bbdemo/recipes-apps/myapp/files
   ```

2. **Create the recipe file** (`meta-bbdemo/recipes-apps/myapp/myapp_1.0.bb`):
   ```bitbake
   SUMMARY = "My Custom Application"
   DESCRIPTION = "Description of my application"
   
   LICENSE = "MIT"
   LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
   
   SRC_URI = "file://myapp.c \
              file://Makefile"
   
   S = "${WORKDIR}"
   
   do_compile() {
       oe_runmake
   }
   
   do_install() {
       install -d ${D}${bindir}
       install -m 0755 myapp ${D}${bindir}
   }
   
   FILES:${PN} = "${bindir}/myapp"
   ```

3. **Add source files** to `meta-bbdemo/recipes-apps/myapp/files/`

4. **Include in image** by adding to `IMAGE_INSTALL` in `bbdemo-image.bb`:
   ```bitbake
   IMAGE_INSTALL += "myapp"
   ```

5. **Rebuild** the image:
   ```bash
   bitbake bbdemo-image
   ```

## Build Artifacts

After building, you'll find:

- **Kernel:** `tmp/deploy/images/qemux86-64/bzImage`
- **Root filesystem:** `tmp/deploy/images/qemux86-64/bbdemo-image-qemux86-64.ext4`
- **Complete image:** `tmp/deploy/images/qemux86-64/bbdemo-image-qemux86-64.wic`

## Troubleshooting

### Build Fails with "No space left on device"

Ensure you have at least 50GB of free disk space. Yocto builds require significant disk space.

### Build is Very Slow

- First builds are always slow. Subsequent builds use cached artifacts.
- Ensure you have enough RAM (8GB+ recommended).
- Use `bitbake -c cleanall <package>` to clean specific packages if needed.

### QEMU Won't Start

- Ensure QEMU is installed: `qemu-system-x86_64 --version`
- Check that the image was built successfully: `ls tmp/deploy/images/qemux86-64/`

### Recipe Build Errors

- Check recipe syntax: `bitbake -e <recipe-name> | grep ^S=`
- Verify source files are in the correct location
- Check build logs: `tmp/log/cooker/qemux86-64/`

## Clean Build

To perform a clean build:

```bash
bitbake -c cleanall bbdemo-image
bitbake bbdemo-image
```

To clean everything (including downloads and shared state):

```bash
rm -rf tmp downloads sstate-cache
```

## Resources

- [Yocto Project Documentation](https://docs.yoctoproject.org/)
- [BitBake User Manual](https://docs.yoctoproject.org/bitbake/)
- [Yocto Project Reference Manual](https://docs.yoctoproject.org/ref-manual/)

## License

This project uses the MIT license for custom components. Yocto/Poky components follow their respective licenses.

