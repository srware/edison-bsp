DESCRIPTION = "Check which enables AP mode if one time setup has not been completed."
SECTION = "base"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS_prepend := "${THISDIR}/files/"

SRC_URI += "file://one-time-setup.service"

S = "${WORKDIR}"

do_install() {
        # Copy service file
        install -d ${D}/${systemd_unitdir}/system
        install -m 644 ${WORKDIR}/one-time-setup.service ${D}/${systemd_unitdir}/system
}

inherit systemd
SYSTEMD_AUTO_ENABLE = "enable"
SYSTEMD_SERVICE_${PN} = "one-time-setup.service"

FILES_${PN} = "${base_libdir}/systemd/system/one-time-setup.service"
FILES_${PN} += "${sysconfdir}/systemd/system/default.target.wants/one-time-setup.service"
