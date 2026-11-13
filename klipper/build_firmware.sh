#!/bin/sh
# Build the two UPC MCU images (FM and IO core) from upstream Klipper plus
# this port, and smoke-test them in the Unicorn emulator.
#
#   klipper/build_firmware.sh WORK_DIR OUT_DIR [KLIPPER_REF]
#
#   WORK_DIR     Klipper checkout to (re)use; reset to KLIPPER_REF every run
#   OUT_DIR      gets fm.bin, fm.dict, io.bin, io.dict, version, kemu logs
#   KLIPPER_REF  default: KLIPPER_SHA from klipper.lock ("master" for the
#                weekly upstream check)
#
# Needs: git, make, python3, arm-none-eabi-gcc (+ newlib headers). The
# emulator test needs the Python package `unicorn` (skipped, with a warning,
# when KEMU=0).
set -e
WORK=${1:?usage: build_firmware.sh WORK_DIR OUT_DIR [KLIPPER_REF]}
OUT=${2:?usage: build_firmware.sh WORK_DIR OUT_DIR [KLIPPER_REF]}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/klipper.lock"
REF=${3:-$KLIPPER_SHA}
PY=${PYTHON:-python3}

# 1. a pristine upstream tree at REF
mkdir -p "$WORK"
if [ ! -d "$WORK/.git" ]; then
    git -C "$WORK" init -q
    git -C "$WORK" remote add origin "$KLIPPER_REPO"
fi
git -C "$WORK" fetch -q --depth 1 origin "$REF"
git -C "$WORK" checkout -qf FETCH_HEAD
git -C "$WORK" clean -qfdx
echo "klipper $(git -C "$WORK" rev-parse HEAD) ($(git -C "$WORK" log -1 --format=%cs))"

# 2. the port, committed and tagged in the work tree. A modified tree gets a
# build time and host name in its version string (scripts/buildcommands.py);
# a commit with fixed identity and dates gives the same version on every
# build of the same sources: sindoh-<PORT_VERSION>-0-g<commit>.
sh "$HERE/install_port.sh" "$WORK"
D=$(git -C "$WORK" log -1 --format=%cI)
PORT_VERSION=${PORT_VERSION:-dev}
git -C "$WORK" add -A -f
GIT_AUTHOR_DATE=$D GIT_COMMITTER_DATE=$D git -C "$WORK" \
    -c user.name=klipper-sindoh -c user.email=build@klipper-sindoh.invalid \
    commit -q -m "Sindoh UPC port $PORT_VERSION"
git -C "$WORK" tag -f "sindoh-$PORT_VERSION" >/dev/null

# 3. both cores
mkdir -p "$OUT"
for core in fm io; do
    ( cd "$WORK" && make clean >/dev/null &&
      cp "config/dp200_$core.config" .config &&
      make olddefconfig >/dev/null &&
      make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null )
    cp "$WORK/out/klipper.bin" "$OUT/$core.bin"
    cp "$WORK/out/klipper.dict" "$OUT/$core.dict"
    echo "built $core.bin: $(wc -c < "$OUT/$core.bin") bytes"
done
# The version string compiled into the images; the host klippy gets the same
# one (klippy/.version) so the two report alike.
$PY -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$OUT/fm.dict" > "$OUT/version"
echo "version $(cat "$OUT/version")"

# 4. emulator smoke test
if [ "${KEMU:-1}" = 0 ]; then
    echo "WARNING: emulator test skipped (KEMU=0)"
else
    for core in fm io; do
        $PY "$HERE/test/kemu.py" "$WORK" "$OUT/$core.bin" $core > "$OUT/kemu_$core.log" 2>&1 || {
            cat "$OUT/kemu_$core.log"; echo "kemu: $core FAILED" >&2; exit 1; }
        $PY "$HERE/test/check_kemu.py" "$OUT/kemu_$core.log" $core || {
            cat "$OUT/kemu_$core.log"; exit 1; }
    done
fi
make -C "$WORK" clean >/dev/null
rm -f "$WORK/.config" "$WORK/.config.old"
