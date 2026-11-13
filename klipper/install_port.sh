#!/bin/sh
# Install the Sindoh UPC port into an upstream Klipper checkout.
#
#   klipper/install_port.sh KLIPPER_DIR
#
# - applies patches/*.patch: the few changes to upstream core files
#   (src/Kconfig, src/stepper.c, src/sched.c); a patch that is already
#   applied is skipped, one that no longer applies stops the install
# - copies src/upc, the two MCU build configs and the klippy extras in
# - lists the copied files in .git/info/exclude (the patched core files
#   still show as modified in `git status`; that is expected)
#
# Safe to run again. Printer config is not installed here (see config/).
set -e
K=${1:?usage: install_port.sh KLIPPER_DIR}
HERE=$(cd "$(dirname "$0")" && pwd)

[ -f "$K/src/Kconfig" ] && [ -d "$K/klippy/extras" ] || { echo "no Klipper tree at $K" >&2; exit 1; }

for p in "$HERE"/patches/*.patch; do
    if git -C "$K" apply --reverse --check "$p" 2>/dev/null; then
        continue                                   # already applied
    fi
    git -C "$K" apply "$p" || {
        echo "$(basename "$p") does not apply to $K: refresh it for this Klipper version" >&2
        exit 1
    }
done

rm -rf "$K/src/upc"
cp -r "$HERE/src/upc" "$K/src/upc"
mkdir -p "$K/config"
cp "$HERE"/kconfig/*.config "$K/config/"
cp "$HERE"/extras/*.py "$K/klippy/extras/"

if [ -d "$K/.git" ]; then
    EX="$K/.git/info/exclude"
    mkdir -p "$(dirname "$EX")"
    touch "$EX"
    for f in /src/upc/ $(cd "$HERE" && ls kconfig/*.config | sed 's|^kconfig/|/config/|') \
             $(cd "$HERE" && ls extras/*.py | sed 's|^extras/|/klippy/extras/|'); do
        grep -qxF "$f" "$EX" || echo "$f" >> "$EX"
    done
fi
echo "UPC port installed in $K"
