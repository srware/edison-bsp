#!/bin/bash
# This script performs post treatments after flash

# global variable set to 1 if output is systemd journal
fi_journal_out=0

export PATH="$PATH:/usr/sbin/"

# handle argument, if post-install is called from systemd service
# arg1 is "systemd-service"
if [ "$1" == "systemd-service" ]; then fi_journal_out=1; fi;

#echo function to output to journal system or in colored terminal
#arg $1 message
#arg $2 log level
fi_echo () {
    lg_lvl=${2:-"log"}
    msg_prefix=""
    msg_suffix=""
    case "$lg_lvl" in
        log) if [ $fi_journal_out -eq 1 ]; then msg_prefix="<5>"; else msg_prefix="\033[1m"; msg_suffix="\033[0m"; fi;;
        err) if [ $fi_journal_out -eq 1 ]; then msg_prefix="<1>"; else msg_prefix="\033[31;40m\033[1m"; msg_suffix="\033[0m"; fi;;
    esac
    printf "${msg_prefix}${1}${msg_suffix}\n"
}

# set_retry_count to failure file
# arg $1 new retry count
set_retry_count () {
    fw_setenv first_install_retry $1
}

# get_retry_count from failure from bootloader
get_retry_count () {
    retry_count=$(fw_printenv first_install_retry | tr -d "first_install_retry=")
    [ -z $retry_count ] && { set_retry_count 0; retry_count=0;}
    return $retry_count
}

# exit first_install by rebooting and handling the failure by setting
# the firmware target according to failure or success
# on failure increment fail count and reboot
# on success reboot in multi-user target
# arg $1 exit code
exit_first_install () {
    if [ $1 -eq 0 ]; then
        # reset failure count
        set_retry_count 0
        # update firmware target
        # next reboot will be on multi-user target
        fw_setenv bootargs_target multi-user
    fi
    # dump journal to log file
    journalctl -u post-install -o short-iso >> /post-install.log
    systemctl daemon-reload
}

# continue normal flow or exit on error code
# arg $1 : return code to check
# arg $2 : string resuming the action
fi_assert () {
    if [ $1 -ne 0 ]; then
        fi_echo "${2} : Failed ret($1)" err;
        exit_first_install $1;
    else
        fi_echo "${2} : Success";
    fi
}

factory_partition () {
    #unmount factory partition
    systemctl stop factory.mount

    mkdir -p /factory
    mount /dev/disk/by-partlabel/factory /factory
    # test can fail if done during manufacturing
    if [ $? -ne 0 ];
    then
        mkfs.ext4 /dev/disk/by-partlabel/factory
        mount /dev/disk/by-partlabel/factory /factory
        echo "00:11:22:33:55:66" > /factory/bluetooth_address
        echo "VSPPYWWDXXXXXNNN" > /factory/serial_number
    fi
}

mount_home () {
    # mount home partition on /home
    mount /dev/disk/by-partlabel/home /home
    fi_assert $? "Mount /home partition"
}

# generate sshd keys
sshd_init () {
    rm -rf /etc/ssh/*key*
    systemctl start sshdgenkeys
}

#
# Sets Device Name updating hostname, AP SSID and P2P SSID.
#
setup_device_name () {
    name="IOT-DEVICE"
    passphrase="password"
    factory_serial="12345678"
    manufacturer="Intel"
    manufacturerUrl="http://www.intel.com/content/www/us/en/homepage.html"
    model="Intel Edison"
    modelUrl="https://www-ssl.intel.com/content/www/us/en/do-it-yourself/edison.html"
    version="1.0.0"

    # Get Device Information
    if [ -f /etc/device-info ] ;
    then
        name=$(grep -o 'Name.*' /etc/device-info | cut -f2 -d'=' | tr -s ' ' '_' | tr '[:lower:]' '[:upper:]')
	manufacturer=$(grep -o 'Manufacturer.*' /etc/device-info | cut -f2 -d'=')
        manufacturerUrl=$(grep -o 'ManufacturerUrl.*' /etc/device-info | cut -f2 -d'=')
        model=$(grep -o 'Model.*' /etc/device-info | cut -f2 -d'=')
        modelUrl=$(grep -o 'ModelUrl.*' /etc/device-info | cut -f2 -d'=')
	version=$(grep -o 'Version.*' /etc/device-info | cut -f2 -d'=')
    fi

    # Get Factory Serial
    if [ -f /factory/serial_number ] ;
    then
        factory_serial=$(head -n1 /factory/serial_number | tr '[:lower:]' '[:upper:]')
        name="${name}-${factory_serial}"
    fi

    # Set hostname
    echo -e ${name} > /etc/hostname
    hostname -F /etc/hostname

    # Substitute the SSID
    sed -i -e 's/^ssid=.*/ssid='${name}'/g' /etc/hostapd/hostapd.conf

    # Substitute the passphrase
    sed -i -e 's/^wpa_passphrase=.*/wpa_passphrase='${passphrase}'/g' /etc/hostapd/hostapd.conf

    # Substitute P2P SSID
    sed -i -e 's/^p2p_ssid_postfix=.*/p2p_ssid_postfix='${name}'/g' /etc/wpa_supplicant/p2p_supplicant.conf

    # Setup UPnP
    sed -i 's/var name=\".*\";/var name=\"'${name}'\";/g' /usr/lib/upnp-service/upnp-service.js
    sed -i 's/var manufacturer=\".*\";/var manufacturer=\"'${manufacturer}'\";/g' /usr/lib/upnp-service/upnp-service.js
    sed -i 's/var manufacturerUrl=\".*\";/var manufacturerUrl=\"'${manufacturerUrl}'\";/g' /usr/lib/upnp-service/upnp-service.js
    sed -i 's/var model=\".*\";/var model=\"'${model}'\";/g' /usr/lib/upnp-service/upnp-service.js
    sed -i 's/var modelUrl=\".*\";/var modelUrl=\"'${modelUrl}'\";/g' /usr/lib/upnp-service/upnp-service.js
    sed -i 's/var version=\".*\";/var version=\"'${version}'\";/g' /usr/lib/upnp-service/upnp-service.js
    sed -i 's/var serial=\".*\";/var serial=\"'${factory_serial}'\";/g' /usr/lib/upnp-service/upnp-service.js

    sync
}


# script main part

# print to journal the current retry count
get_retry_count
retry_count=$?
set_retry_count $((${retry_count} + 1))
fi_echo "Starting Post Install (try: ${retry_count})"

systemctl start blink-led

ota_done=$(fw_printenv ota_done | tr -d "ota_done=")
if [ "$ota_done" != "1" ];
then
    # backup initial /home/root directory
    mkdir /tmp/oldhome
    cp -R /home/* /tmp/oldhome/
    fi_assert $? "Backup home/root contents of rootfs"

    # format partition home to ext4
    mkfs.ext4 -m0 /dev/disk/by-partlabel/home
    fi_assert $? "Formatting home partition"

    # mount home partition
    mount_home

    # copy back contents to /home and cleanup
    cp -R /tmp/oldhome/* /home/
    rm -rf /tmp/oldhome
    fi_assert $? "Restore home/root contents on new /home partition"

    # create a fat32 primary partition on all available space
    echo -ne "n\np\n1\n\n\nt\nb\np\nw\n" | fdisk /dev/disk/by-partlabel/update

    # silent error code for now because fdisk failed to reread MBR correctly
    # MBR is correct but fdisk understand it as the main system MBR, which is
    # not the case.
    fi_assert 0 "Formatting update partition Step 1"

    # format update partition
    mkfs.vfat /dev/disk/by-partlabel/update -n "Edison" -F 32
    fi_assert $? "Formatting update partition Step 2"

else
    # just mount home partition after OTA update
    mount_home
fi

# handle factory partition
factory_partition

# ssh
sshd_init
fi_assert $? "Generating sshd keys"

# update entry in /etc/fstab to enable auto mount
sed -i 's/#\/dev\/disk\/by-partlabel/\/dev\/disk\/by-partlabel/g' /etc/fstab
fi_assert $? "Update file system table /etc/fstab"

# Setup Device Name
setup_device_name
fi_assert $? "Generating Wifi Access Point SSID and passphrase"

fi_echo "Post install success"

systemctl stop blink-led
# end main part
exit_first_install 0

