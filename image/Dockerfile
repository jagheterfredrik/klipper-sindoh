# Build environment (build.sh). Needs `docker run --privileged` for the image
# build (debootstrap mounts proc/sys/dev) and qemu binfmt for ARM (Docker
# Desktop has it; on Linux: docker run --privileged tonistiigi/binfmt --install arm).
FROM debian:trixie
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        debootstrap qemu-user-static binfmt-support gcc-arm-none-eabi libnewlib-arm-none-eabi \
        gcc make git python3 python3-venv ca-certificates curl unzip openssl e2fsprogs \
        xz-utils bzip2 rsync procps file \
    && rm -rf /var/lib/apt/lists/*
# Unicorn for the firmware smoke test (klipper/test/kemu.py)
RUN python3 -m venv /opt/kemu && /opt/kemu/bin/pip install -q unicorn==2.1.1
ENV PYTHON=/opt/kemu/bin/python
