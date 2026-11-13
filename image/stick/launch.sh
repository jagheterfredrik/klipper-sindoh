#!/bin/sh
# Klipper live start from a USB stick (stock BusyBox shell, root).
#
#   launch.sh mount   loop-mount dp200.img on /tmp/dp200root (RAM disk dir)
#   launch.sh run     wait for the stock boot, then start the Klipper stack
#                     (kills the Sindoh app first): dp200-start.sh
#
# Nothing is written to the printer's flash: the mount point is on the /tmp
# tmpfs, the loop module is loaded from the stock root. A power cycle without
# the stick (or after stop.sh) is the stock firmware again.
D=$(cd "$(dirname "$0")" && pwd)
IMG=$D/dp200.img
ROOT=/tmp/dp200root
say() { echo "[klipper-usb $(date +%T)] $*"; }

do_mount() {
    grep -q " $ROOT " /proc/mounts && { say "already mounted"; return 0; }
    [ -s "$IMG" ] || { say "no image $IMG"; return 1; }
    grep -q '^loop ' /proc/modules || \
        insmod /lib/modules/`uname -r`/kernel/drivers/block/loop.ko || { say "no loop.ko"; return 1; }
    for i in 0 1 2 3; do [ -b /dev/loop$i ] || mknod /dev/loop$i b 7 $i; done
    L=
    for i in 0 1 2 3; do
        losetup /dev/loop$i "$IMG" 2>/dev/null && { L=/dev/loop$i; break; }
    done
    [ -n "$L" ] || { say "no free loop device"; return 1; }
    mkdir -p $ROOT
    mount -t ext3 -o noatime $L $ROOT || { say "mount failed"; losetup -d $L; return 1; }
    say "mounted $IMG on $ROOT via $L"
}

case "$1" in
mount)
    do_mount
    ;;
run)
    do_mount || exit 1
    # /etc/profile starts UIManager after media.connect (this script runs inside
    # it on a boot with the stick in; /tmp/dmesg.boot.txt is written 3 s after
    # UIManager starts). On a hot-plug the file is already there.
    i=0
    while [ ! -f /tmp/dmesg.boot.txt ] && [ $i -lt 120 ]; do sleep 1; i=$((i + 1)); done
    sleep 2
    [ -x $ROOT/dp200/dp200-start.sh ] || { say "no $ROOT/dp200/dp200-start.sh"; exit 1; }
    say "starting Klipper (waited ${i}s)"
    exec sh $ROOT/dp200/dp200-start.sh
    ;;
*)
    echo "usage: $0 mount|run"
    exit 2
    ;;
esac
