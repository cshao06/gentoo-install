#!/bin/bash

set -e
# set -x
# trap read debug


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

GENTOO_RELEASES_URL=http://distfiles.gentoo.org/releases
GENTOO_ARCH=amd64
GENTOO_VARIANT=hardened

MOUNT_PATH=/mnt/gentoo
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

download_and_extract_tarball() {
    # Add check for pwd
    echo "Please cd into the mounted root for gentoo first"
    echo
    STAGE3_PATH_URL=$GENTOO_RELEASES_URL/$GENTOO_ARCH/autobuilds/latest-stage3-$GENTOO_ARCH-$GENTOO_VARIANT.txt
    STAGE3_PATH=$(curl -s $STAGE3_PATH_URL | grep -v "^#" | cut -d" " -f1)
    STAGE3_URL=$GENTOO_RELEASES_URL/$GENTOO_ARCH/autobuilds/$STAGE3_PATH

    confirm wget $STAGE3_URL
    confirm tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
}

mount_for_chroot() {
    confirm mount --types proc /proc /mnt/gentoo/proc
    confirm mount --rbind /sys /mnt/gentoo/sys
    confirm mount --make-rslave /mnt/gentoo/sys
    confirm mount --rbind /dev /mnt/gentoo/dev
    confirm mount --make-rslave /mnt/gentoo/dev
}


echo "Choose what to do"

steps="date download_and_extract_tarball change_make.conf mirrors dns chroot umount"

select option in $steps; do
    echo "$REPLY $option selected"
    case $option in
        date)
            confirm ntpd -q -g
            ;;
        download_and_extract_tarball)
            download_and_extract_tarball
            ;;
        change_make.conf)
            echo "Example in repo"
            echo "Add USE flags if needed"
            ;;
        mirrors)
            confirm mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf
            confirm mkdir --parents /mnt/gentoo/etc/portage/repos.conf
            confirm cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
            ;;
        dns)
            confirm cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
            ;;
        chroot)
            mount_for_chroot
            echo "Copy the after chroot script in to the new root"
            confirm cp $SCRIPT_DIR/after_chroot.sh $MOUNT_PATH
            echo "Please run \"chroot /mnt/gentoo /bin/bash\" manually"
            ;;
        umount)
            cd
            confirm umount -l /mnt/gentoo/dev{/shm,/pts,}
            confirm umount -R /mnt/gentoo
            echo "Ready to reboot"
            ;;
        *)
            break;
            ;;
    esac
done
