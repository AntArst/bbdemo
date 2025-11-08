SUMMARY = "A minimal Linux image with BusyBox and custom applications"
DESCRIPTION = "A minimal image suitable for QEMU that includes BusyBox \
and custom BBDemo applications."

IMAGE_FEATURES += "splash package-management ssh-server-dropbear"

LICENSE = "MIT"

inherit core-image

# Base packages
IMAGE_INSTALL += "\
    packagegroup-core-boot \
    packagegroup-core-ssh-dropbear \
    hello-bbdemo \
    "

# BusyBox is included by default in core-image-minimal
# Additional custom applications can be added here

