#!/bin/bash
# Runs INSIDE the build container (see ../build.sh).
#
#   build_in_container.sh firmware   MCU images -> /out/firmware
#   build_in_container.sh image      firmware + Debian root + stick -> /out/stick
#
#   /src    this repository (read-only)
#   /build  persistent work volume: every slow step is cached there and
#           redone only when its inputs change
#   /out    results on the host
set -euo pipefail
SRC=/src
B=/build
MODE=${1:-image}
PORT_VERSION=${PORT_VERSION:-dev}
export PORT_VERSION
. $SRC/klipper/klipper.lock
. $SRC/image/versions

say() { echo "== $*"; }

# ---------------------------------------------------------------- firmware
# Klipper tree = upstream at klipper.lock + the port, committed and tagged
# (build_firmware.sh). The image's klippy is a copy of this same tree, so
# host and MCU code always match.
say "firmware"
rm -rf /out/firmware
sh $SRC/klipper/build_firmware.sh $B/fw-klipper /out/firmware ${KLIPPER_REF:-}
[ "$MODE" = firmware ] && exit 0

# ---------------------------------------------------------------- root fs
R=$B/rootfs
KUSER=klipper
KHOME=$R/home/$KUSER

in_root() { chroot "$R" /usr/bin/env -i HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 "$@"; }
as_user() { in_root su -s /bin/bash $KUSER -c "$1"; }
# a step is redone when its key (the inputs it depends on) changes
done_key() { [ -f "$B/stamp.$1" ] && [ "$(cat "$B/stamp.$1")" = "$2" ]; }
set_key() { echo "$2" > "$B/stamp.$1"; }

cleanup() {
    for m in dev/pts dev proc sys; do
        mountpoint -q "$R/$m" && umount "$R/$m" || true
    done
}
trap cleanup EXIT

# Docker Desktop registers qemu for 32-bit ARM; make sure before the long part
update-binfmts --enable qemu-arm 2>/dev/null || true

# Why armel: the vendor kernel 3.2 has no CONFIG_ARM_THUMB, and Debian armhf
# is Thumb-2 code ("Exec format error"); armel is ARM mode. trixie's glibc
# still supports kernel 3.2.
say "1. debootstrap $DEBIAN_SUITE armel"
if [ ! -x "$R/bin/bash" ]; then
    rm -rf "$R"
    debootstrap --arch=armel --foreign --variant=minbase \
        --include=ca-certificates "$DEBIAN_SUITE" "$R" "$DEBIAN_MIRROR"
    cp "$(command -v qemu-arm-static)" "$R/usr/bin/"
    chroot "$R" /debootstrap/debootstrap --second-stage
fi
cp "$(command -v qemu-arm-static)" "$R/usr/bin/"
mount -t proc proc "$R/proc"; mount -t sysfs sys "$R/sys"
mount -o bind /dev "$R/dev"; mount -o bind /dev/pts "$R/dev/pts"
cp /etc/resolv.conf "$R/etc/resolv.conf"

say "2. packages"
PKGS="python3 python3-venv python3-dev python3-pip gcc g++ make libc6-dev
    libffi-dev libncurses-dev git sudo curl unzip nginx
    libjpeg62-turbo-dev zlib1g-dev liblmdb-dev libsodium-dev
    procps iproute2 iputils-ping less nano
    ustreamer v4l-utils python3-pil fonts-dejavu-core"
if ! done_key apt "$PKGS"; then
    in_root apt-get update
    in_root apt-get install -y --no-install-recommends $PKGS
    in_root apt-get clean
    set_key apt "$PKGS"
fi
in_root dpkg-query -W -f '${Package} ${Version}\n' > $B/packages.txt

say "3. klipper user"
in_root id $KUSER >/dev/null 2>&1 || in_root useradd -m -s /bin/bash -G dialout,video,tty $KUSER
chmod 755 "$KHOME"
KUID=$(in_root id -u $KUSER); KGID=$(in_root id -g $KUSER)

say "4. Klipper (the firmware's tree) + klippy venv"
rsync -a --delete --exclude /out --exclude /.config --exclude /.config.old \
    $B/fw-klipper/ "$KHOME/klipper/"
KLIPPER_VERSION=$(cat /out/firmware/version)
echo "$KLIPPER_VERSION" > "$KHOME/klipper/klippy/.version"   # the image has no .git
chown -R $KUID:$KGID "$KHOME/klipper"
REQ=$(sha256sum "$KHOME/klipper/scripts/klippy-requirements.txt" | cut -d' ' -f1)
if ! done_key klippy-env "$REQ"; then
    as_user "rm -rf ~/klippy-env && python3 -m venv ~/klippy-env && \
        ~/klippy-env/bin/pip install -q -r ~/klipper/scripts/klippy-requirements.txt"
    set_key klippy-env "$REQ"
fi
# Klipper's host C helper, so the first start on the printer is fast
as_user "cd ~/klipper/klippy && ~/klippy-env/bin/python -c 'import chelper; chelper.get_ffi()'"

say "5. Moonraker $MOONRAKER_SHA"
if ! done_key moonraker "$MOONRAKER_SHA"; then
    as_user "rm -rf ~/moonraker ~/moonraker-env && mkdir ~/moonraker && cd ~/moonraker && \
        git init -q && git remote add origin $MOONRAKER_REPO && \
        git fetch -q --depth 1 origin $MOONRAKER_SHA && git checkout -q FETCH_HEAD"
    # Pillow has no armel wheel and its sdist builds CMake from source under
    # qemu (hours): link Debian's python3-pil into the venv instead.
    as_user "python3 -m venv ~/moonraker-env && \
        grep -vi '^pillow' ~/moonraker/scripts/moonraker-requirements.txt > /tmp/moonraker-req.txt && \
        ~/moonraker-env/bin/pip install -q -r /tmp/moonraker-req.txt"
    SP=$(as_user "~/moonraker-env/bin/python -c 'import site; print(site.getsitepackages()[0])'")
    as_user "ln -sfn /usr/lib/python3/dist-packages/PIL $SP/PIL"
    as_user "~/moonraker-env/bin/python -c 'import PIL.Image'"
    as_user "cd ~/moonraker && git describe --always --tags --long > moonraker/.version"
    set_key moonraker "$MOONRAKER_SHA"
fi

say "6. Mainsail $MAINSAIL_VERSION"
if ! done_key mainsail "$MAINSAIL_VERSION"; then
    as_user "rm -rf ~/mainsail && mkdir ~/mainsail && cd ~/mainsail && \
        curl -fsSL -o mainsail.zip https://github.com/mainsail-crew/mainsail/releases/download/$MAINSAIL_VERSION/mainsail.zip && \
        unzip -q mainsail.zip && rm mainsail.zip"
    set_key mainsail "$MAINSAIL_VERSION"
fi

say "7. upctool and the camera shim (built in the armel root)"
rm -rf "$R/usr/src/klipper-sindoh"
mkdir -p "$R/usr/src/klipper-sindoh/klipper/src" "$R/usr/src/klipper-sindoh/camera"
cp -r $SRC/upctool "$R/usr/src/klipper-sindoh/"
cp -r $SRC/klipper/src/upc "$R/usr/src/klipper-sindoh/klipper/src/"
rm -f "$R/usr/src/klipper-sindoh/upctool/upctool"
in_root make -s -C /usr/src/klipper-sindoh/upctool CC=gcc ARCHFLAGS= \
    CFLAGS="-O2 -Wall -std=gnu99 -marm -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp"
install -m 755 "$R/usr/src/klipper-sindoh/upctool/upctool" "$R/usr/local/bin/upctool"
# time64 -> time32 V4L2 shim for kernel 3.2 (ustreamer)
cp $SRC/image/runtime/camera/v4l2_time32_shim.c "$R/usr/src/klipper-sindoh/camera/"
in_root gcc -O2 -Wall -shared -fPIC -o /usr/local/lib/v4l2_time32_shim.so \
    /usr/src/klipper-sindoh/camera/v4l2_time32_shim.c -ldl

say "8. runtime files, config, firmware"
RT=$SRC/image/runtime
install -d "$R/etc/dp200" "$R/dp200" "$R/opt/dp200" "$KHOME/printer_data/config" \
    "$KHOME/printer_data/gcodes" "$KHOME/printer_data/logs"
install -m 755 $RT/rootfs/etc/dp200/rc.dp200 "$R/etc/dp200/rc.dp200"
install -m 644 $RT/rootfs/etc/nginx/sites-available/mainsail "$R/etc/nginx/sites-available/mainsail"
rm -f "$R/etc/nginx/sites-enabled/default"
ln -sf ../sites-available/mainsail "$R/etc/nginx/sites-enabled/mainsail"
install -m 755 $RT/display/dp200_screen.py $RT/display/dp200_wifi.py $RT/display/dp200_net.py \
    "$R/usr/local/bin/"
install -m 755 $RT/printer/*.sh $RT/printer/*.py "$R/dp200/"
install -m 644 $SRC/image/vendor/cdc-acm.ko "$R/dp200/"
for core in fm io; do
    install -m 644 /out/firmware/$core.bin "$R/opt/dp200/$core.bin"
    install -m 644 /out/firmware/$core.dict "$R/opt/dp200/$core.dict"
done
# Printer config: the shared files go to printer_data/config; printer.cfg is
# created on the first start from the template for the detected model
# (dp200-start.sh), so none is shipped there.
CFG="$KHOME/printer_data/config"
rm -f "$CFG"/*.cfg "$CFG"/*.cfg.off
install -m 644 $SRC/klipper/config/common/* "$CFG/"
for m in 3dwox1 dp200; do
    install -D -m 644 $SRC/klipper/config/$m/printer.cfg "$R/opt/dp200/config/$m/printer.cfg"
done
install -m 644 $RT/rootfs/home/klipper/printer_data/config/moonraker.conf \
    $RT/rootfs/home/klipper/printer_data/config/dp200_moonraker.conf "$CFG/"
in_root chown -R $KUSER:$KUSER /home/$KUSER
echo "dp200-klipper" > "$R/etc/hostname"
# versions for the screen's INFO page ("Build") and for support questions
MOONRAKER_VERSION=$(cat "$KHOME/moonraker/moonraker/.version")
echo "klipper-sindoh $PORT_VERSION ($(date -u +%Y-%m-%d))" > "$R/etc/dp200/build"
cat > "$R/etc/dp200/versions" <<EOF
klipper_sindoh=$PORT_VERSION
klipper=$KLIPPER_VERSION
klipper_upstream=$KLIPPER_SHA
moonraker=$MOONRAKER_VERSION
mainsail=$MAINSAIL_VERSION
debian=$DEBIAN_SUITE $(cat "$R/etc/debian_version")
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
cleanup
rm -f "$R/usr/bin/qemu-arm-static"

# ---------------------------------------------------------------- image
say "9. runtime tree (the root minus compilers, docs, caches)"
RTREE=$B/runtime
rm -rf $RTREE; mkdir -p $RTREE; chmod 755 $RTREE
tar -C $R -cf - --numeric-owner --one-file-system \
    --exclude-from=$SRC/image/runtime/runtime.exclude \
    ./bin ./etc ./home ./lib ./opt ./sbin ./srv ./usr ./var ./dp200 \
  | tar -C $RTREE -xpf - --numeric-owner
for d in proc sys dev run tmp root mnt var/log var/lib home/klipper/printer_data/logs; do
    mkdir -p $RTREE/$d
done
chmod 1777 $RTREE/tmp
touch $RTREE/etc/dp200/on_nand        # logs in RAM (stick wear): dp200-start.sh keys on it
touch $RTREE/etc/dp200/usb_live       # "Installed on: USB stick" on the screen
rm -f $RTREE/etc/dp200/wpa_supplicant.conf* $RTREE/etc/wpa_supplicant/*.conf
# nothing of the build host's networks or secrets may ship
if grep -rIl -e 'psk=' $RTREE/etc $RTREE/home/klipper/printer_data 2>/dev/null | grep -q .; then
    echo "a Wi-Fi passphrase is in the image" >&2; exit 1
fi

# The printer's own files from a stick's previous dp200.img (KEEP_STATE in
# build.sh): printer.cfg and everything else the owner added to the config
# folder, Moonraker's database (history, Mainsail settings), uploaded
# G-codes, saved Wi-Fi networks and network settings. Files this build
# ships (shared config, rc.dp200, versions) are never replaced by old ones.
if [ -n "${STATE_IMG:-}" ]; then
    say "9b. the printer's own files from $(basename "$STATE_IMG")"
    ST=$B/state; rm -rf $ST $B/state.img; mkdir -p $ST
    cp "$STATE_IMG" $B/state.img
    e2fsck -fy $B/state.img >/dev/null || [ $? -le 1 ]   # replays the journal of a pulled stick
    P=home/klipper/printer_data
    for d in $P etc/dp200 var/lib/dp200; do
        mkdir -p $ST/$(dirname $d)
        debugfs -R "rdump /$d $ST/$(dirname $d)" $B/state.img 2>/dev/null || true
    done
    [ -f $ST/$P/config/printer.cfg ] || { echo "no printer.cfg in $STATE_IMG" >&2; exit 1; }
    cp -an $ST/$P/config/. $RTREE/$P/config/                  # owner's files; shipped ones win
    for f in database gcodes .moonraker.uuid moonraker.asvc; do
        [ -e $ST/$P/$f ] && { rm -rf $RTREE/$P/$f; cp -a $ST/$P/$f $RTREE/$P/; }
    done
    cp -an $ST/etc/dp200/. $RTREE/etc/dp200/                  # wpa_supplicant.conf, network.json, ...
    [ -d $ST/var/lib/dp200 ] && cp -a $ST/var/lib/dp200 $RTREE/var/lib/
    echo "kept: $(cd $RTREE/$P/config && ls | tr '\n' ' ')"
    rm -rf $ST $B/state.img
fi

say "10. ext3 image (kernel 3.2 mounts ext3; the journal replays after a pulled stick)"
USED=$(du -sm $RTREE | cut -f1)
SIZE=$(( USED * 125 / 100 + 128 ))
echo "$USED MB used -> $SIZE MB image"
rm -rf /out/stick; mkdir -p /out/stick/dp200
rm -f $B/dp200.img
mke2fs -q -t ext3 -b 4096 -L dp200root -m 1 -O ^resize_inode -d $RTREE $B/dp200.img ${SIZE}M
e2fsck -fn $B/dp200.img
cp $B/dp200.img /out/stick/dp200/dp200.img
( cd /out/stick/dp200 && md5sum dp200.img > dp200.img.md5 )
cp $R/etc/dp200/versions /out/stick/dp200/versions.txt
cp $B/packages.txt /out/packages.txt

say "11. launcher + stubs"
install -m 755 $SRC/image/stick/launch.sh $SRC/image/stick/stop.sh /out/stick/dp200/
STUBDIR=$(mktemp -d)
install -m 755 $SRC/image/stick/unmistakable_klipper_usb.sh $STUBDIR/
STUB=unmistakable_klipper_usb
# The stock /app/auto_update.sh decrypts every unmistakable*.she in its
# model's update folder and runs it (docs/model_audit.md, other_models.md):
#   3DWOX 1  _update_rodin_up  AES-256-CBC, key = IV = "sindoh024601779U"
#   DP200    _update_rodin     des3 (salted, MD5 key derivation), "sindoh024601779"
pack_aes() {
    # key: the string zero-padded to 32 bytes; IV: its first 16 bytes
    local k iv
    k=$(printf '%s' "$2" | od -An -v -tx1 | tr -d ' \n')
    iv=$(printf '%-32.32s' "$k" | tr ' ' 0)
    k=$(printf '%-64.64s' "$k" | tr ' ' 0)
    mkdir -p /out/stick/$1
    tar -cjf - -C $STUBDIR $STUB.sh | openssl enc -aes-256-cbc -K $k -iv $iv > /out/stick/$1/$STUB.she
    openssl enc -d -aes-256-cbc -K $k -iv $iv -in /out/stick/$1/$STUB.she \
        | tar -xjO $STUB.sh | cmp - $STUBDIR/$STUB.sh
}
pack_des3() {
    mkdir -p /out/stick/$1
    tar -cjf - -C $STUBDIR $STUB.sh | openssl des3 -e -salt -md md5 -k "$2" > /out/stick/$1/$STUB.she
    openssl des3 -d -salt -md md5 -k "$2" -in /out/stick/$1/$STUB.she \
        | tar -xjO $STUB.sh | cmp - $STUBDIR/$STUB.sh
}
# (called as plain commands, so a failed round-trip check stops the build)
pack_aes _update_rodin_up sindoh024601779U
echo "stub verified: _update_rodin_up (3DWOX 1)"
pack_des3 _update_rodin sindoh024601779
echo "stub verified: _update_rodin (DP200, untested)"
rm -rf $STUBDIR
find /out/stick -type f -exec ls -l {} +
