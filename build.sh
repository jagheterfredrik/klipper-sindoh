#!/bin/bash
# Build on the PC (macOS or Linux with Docker).
#
#   ./build.sh firmware   MCU images + emulator test      -> out/firmware/
#   ./build.sh image      firmware, Debian root, stick    -> out/stick/  (default)
#   ./build.sh clean      drop the cached build volume
#
# The first image build is long (debootstrap and Python wheels under qemu);
# the work is cached in the Docker volume klipper-sindoh-build, so later
# builds redo only what changed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out
IMG=klipper-sindoh-build
VOL=klipper-sindoh-build
MODE=${1:-image}

case "$MODE" in
clean) docker volume rm $VOL; exit 0 ;;
firmware|image) ;;
*) echo "usage: $0 [firmware|image|clean]" >&2; exit 2 ;;
esac

VERSION=$(git -C "$HERE" describe --always --tags --dirty 2>/dev/null || echo unknown)
mkdir -p "$OUT"
docker build -q -t $IMG "$HERE/image" >/dev/null
docker run --rm --privileged -e PORT_VERSION="$VERSION" \
    -v "$HERE":/src:ro -v "$OUT":/out -v $VOL:/build \
    $IMG bash /src/image/build_in_container.sh "$MODE"
echo "done ($VERSION): $OUT/$([ "$MODE" = image ] && echo stick || echo firmware)"
