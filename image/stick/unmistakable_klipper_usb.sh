#!/bin/sh
# Stub, packed as _update_rodin_up/unmistakable_klipper_usb.she and run by the
# stock /app/auto_update.sh (synchronously, as root, with the folder as $1)
# whenever this stick is plugged in or present at boot.
#
# It only does what must happen before auto_update.sh returns, and hands the
# rest to dp200/launch.sh on the stick (plain text: edit without re-packing).
#  - mount the image NOW: that keeps /mnt/sda1 busy, so the final
#    "umount /mnt/sda1/" of auto_update.sh fails harmlessly instead of
#    pulling the stick away under us;
#  - start the long part in the background: /etc/profile waits for this script.
exec >/dev/console 2>&1
D=/mnt/sda1/dp200
# Optional debug access: a root shell on tcp/2323 (no authentication, so only
# when the file dp200/debug exists on the stick). A breadcrumb in the log proves
# the stub ran.
[ -f $D/debug ] && { pidof nc >/dev/null 2>&1 || ( setsid nc -llp 2323 -e /bin/sh </dev/null >/dev/null 2>&1 & ) ; }
[ -d $D ] && echo "[klipper-usb `date '+%F %T'`] stub ran" >> $D/launch.log
if [ ! -f $D/launch.sh ]; then
    echo "klipper-usb: $D/launch.sh missing, nothing to do"
    exit 0
fi
echo "klipper-usb: mounting $D/dp200.img"
sh $D/launch.sh mount || { echo "klipper-usb: mount failed (see $D/launch.log)"; exit 0; }
( setsid sh $D/launch.sh run </dev/null >> $D/launch.log 2>&1 & )
exit 0
