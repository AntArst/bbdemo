SUMMARY = "Hello BBDemo - Example custom application"
DESCRIPTION = "A simple example application demonstrating how to add \
custom commands to the Yocto build."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://hello-bbdemo.c \
           file://Makefile"

S = "${WORKDIR}"

do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 hello-bbdemo ${D}${bindir}
}

FILES:${PN} = "${bindir}/hello-bbdemo"

