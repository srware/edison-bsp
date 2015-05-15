DESCRIPTION="The out-of-box configuration service"
LICENSE = "MIT"

SRC_URI = "git://github.com/srware/edison-oobe.git;protocol=https"
SRCREV = "${AUTOREV}"

LIC_FILES_CHKSUM = "file://LICENSE;md5=ea398a763463b76b18da15f013c0c531"

S = "${WORKDIR}/git"

DEPENDS = "nodejs-native"

do_compile() {
    # changing the home directory to the working directory, the .npmrc will be created in this directory
    export HOME=${WORKDIR}

    # does not build dev packages
    npm config set dev false

    # access npm registry using http
    npm set strict-ssl false
    npm config set registry http://registry.npmjs.org/

    # configure http proxy if neccessary
    if [ -n "${http_proxy}" ]; then
        npm config set proxy ${http_proxy}
    fi
    if [ -n "${HTTP_PROXY}" ]; then
        npm config set proxy ${HTTP_PROXY}
    fi

    # configure cache to be in working directory
    npm set cache ${WORKDIR}/npm_cache

    # clear local cache prior to each compile
    npm cache clear

    # compile and install  node modules in source directory
    npm --arch=${TARGET_ARCH} --verbose install
}

do_install() {
   install -d ${D}${libdir}/config_tools
   install -d ${D}/var/lib/config_tools
   cp -r ${S}/src/public ${D}${libdir}/config_tools
   cp -r ${S}/node_modules ${D}${libdir}/config_tools
   install -m 0644 ${S}/src/server.js ${D}${libdir}/config_tools/config-server.js
   install -d ${D}${systemd_unitdir}/system/
   install -m 0644 ${S}/src/device_config.service ${D}${systemd_unitdir}/system/
   install -d ${D}${bindir}
   install -m 0755 ${S}/src/configure_device ${D}${bindir}
}

inherit systemd

SYSTEMD_AUTO_ENABLE = "enable"
SYSTEMD_SERVICE_${PN} = "device_config.service"

FILES_${PN} = "${libdir}/config_tools \
               ${systemd_unitdir}/system \
               /var/lib/config_tools \
               ${bindir}/"

PACKAGES = "${PN}"

