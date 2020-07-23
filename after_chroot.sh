#!/bin/bash

set -e

confirm() {
    echo -n "Do you want to run $*? [N/y] "
    read -N 1 REPLY
    echo
    if test "$REPLY" = "y" -o "$REPLY" = "Y"; then
        "$@"
    else
        echo "Cancelled by user"
    fi
}

ask() {
    # https://djm.me/ask
    local prompt default reply

    if [ "${2:-}" = "Y" ]; then
        prompt="Y/n"
        default=Y
    elif [ "${2:-}" = "N" ]; then
        prompt="y/N"
        default=N
    else
        prompt="y/n"
        default=
    fi

    while true; do

        # Ask the question (not using "read -p" as it uses stderr not stdout)
        echo -n "$1 [$prompt] "

        # Read the answer (use /dev/tty in case stdin is redirected from somewhere else)
        read reply </dev/tty

        # Default?
        if [ -z "$reply" ]; then
            reply=$default
        fi

        # Check if the reply is valid
        case "$reply" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac

    done
}


echo "Choose what to do"

TIMEZONE="America/New_York"
HOSTNAME="HomeMacbook"
ETH_NAME=eth0
USER_NAME=cshao

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set_locale() {
    echo "Check available locales in /usr/share/i18n/SUPPORTED"

    confirm cat << EOF > /etc/locale.gen
# All blank lines and lines starting with # are ignored.
en_US.UTF-8 UTF-8
en_US ISO-8859-1
zh_CN.GB18030 GB18030
zh_CN.GBK GBK
zh_CN.UTF-8 UTF-8
zh_CN GB2312
EOF

    confirm locale-gen
    eselect locale list
    echo "Run \"eselect locale set [number]\" to change system locale if needed"
}

steps="env mount_boot update_repo update_world timezone locale firmware kernel initramfs fstab network users tools grub"

select option in $steps; do
    echo "$REPLY $option selected"
    case $option in
        env)
            confirm source /etc/profile
            confirm export PS1="(chroot) ${PS1}"
            ;;
        mount_boot)
            echo "Please mount the boot partition in /boot"
            ;;
        update_repo)
            echo "run \"emerge-webrsync\" if you are behind restrictive firewalls"
            confirm emerge --sync
            eselect profile list
            echo "Please use \"eselect profile set [number]\" to select the profile if needed"
            ;;
        update_world)
            confirm emerge --ask --verbose --update --deep --newuse @world
            ;;
        timezone)
            ls /usr/share/zoneinfo
            confirm echo $TIMEZONE > /etc/timezone
            confirm emerge --config sys-libs/timezone-data
            ;;
        locale)
            set_locale
            ;;
        firmware)
            confirm emerge --ask sys-kernel/linux-firmware
            confirm echo "net-wireless/broadcom-sta" >> /etc/portage/package.accept_keywords
            confirm emerge --ask net-wireless/broadcom-sta
        kernel)
            confirm emerge --ask sys-kernel/gentoo-sources
            confirm emerge --ask sys-apps/pciutils
            confirm cd /usr/src/linux
            echo "Run \"make menuconfig\" to configure the kernel"
            echo "Run \"make -j[num of cpus] && modules_install && make install\" to compile and install the kernel"
            ;;
        initramfs)
            confirm emerge --ask sys-kernel/genkernel
            confirm genkernel --install initramfs
            ls /boot/initramfs*
            cd /
            ;;
        fstab)
            confirm cp $SCRIPT_DIR/fstab /etc/fstab
            cat /etc/fstab
            ;;
        network)
            confirm sed -i "s/localhost/$HOSTNAME/g" /etc/conf.d/hostname
            confirm emerge --ask --noreplace net-misc/netifrc
            confirm cd /etc/init.d
            confirm cp $SCRIPT_DIR/net /etc/init.d/
            confirm ln -s net.lo net.$ETH_NAME
            confirm rc-update add net.$ETH_NAME default
            confirm cp $SCRIPT_DIR/hosts /etc/
            cd /
            ;;
        users)
            confirm passwd
            confirm useradd -m -G users,wheel,audio -s /bin/bash $USER_NAME
            confirm passwd $USER_NAME
            ;;
        tools)
            confirm emerge --ask app-admin/sysklogd
            confirm rc-update add sysklogd default
            confirm emerge --ask sys-apps/mlocate
            confirm rc-update add sshd default
            confirm emerge --ask sys-fs/dosfstools
            confirm emerge --ask net-misc/dhcpcd
            confirm emerge --ask net-wireless/iw net-wireless/wpa_supplicant
            ;;
        grub_uefi)
            confirm echo 'GRUB_PLATFORMS="efi-64"' >> /etc/portage/make.conf
            confirm emerge --ask sys-boot/grub:2
            confirm grub-install --target=x86_64-efi --efi-directory=/boot
            confirm grub-mkconfig -o /boot/grub/grub.cfg
        *)
            break;
            ;;
    esac
done
