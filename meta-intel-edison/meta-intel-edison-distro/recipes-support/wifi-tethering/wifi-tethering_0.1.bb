DESCRIPTION = "WiFi Tethering in Edison"
SECTION = "base"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS_prepend := "${THISDIR}/files/:"

SRC_URI = "file://wifi-tethering"

S = "${WORKDIR}"
PR = "r6"

FILES_${PN} += "${bindir}/*"

do_install_append() {
	install -d ${D}${bindir}
	install -m 0755 ${S}/wifi-tethering ${D}${bindir}
}
