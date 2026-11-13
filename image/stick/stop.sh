#!/bin/sh
# Stop Klipper and release the stick:  sh /mnt/sda1/dp200/stop.sh
# (UPC cores held in reset, heaters/fans/motors forced off). Afterwards the
# stick can be removed; a reboot gives the stock firmware (the stock UI does
# not come back without one).
ROOT=/tmp/dp200root
[ -x $ROOT/dp200/dp200-start.sh ] && sh $ROOT/dp200/dp200-start.sh stop
sleep 1
# unmount everything the start script mounted under the root, deepest first
for m in `grep " $ROOT/" /proc/mounts | awk '{print $2}' | sort -r`; do umount $m 2>/dev/null || umount -l $m; done
umount $ROOT && for i in 0 1 2 3; do losetup -d /dev/loop$i 2>/dev/null; done
sync
echo "stopped; the stick can be removed"
