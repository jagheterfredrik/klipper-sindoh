# Build upctool as a static armhf binary (runs on the stock BusyBox/glibc
# 2.15 userland and inside a Debian chroot alike).
#
#   make                       # uses arm-linux-gnueabihf-gcc
#   make CC="zig cc -target arm-linux-musleabihf -mcpu=cortex_a9-neon-d32-fp16"
#
# A static link avoids any dependency on the printer's old glibc.
# The Marvell PJ4 has VFPv3-D16: code must never touch d16-d31, hence
# -mfpu=vfpv3-d16 (gcc) / "-neon-d32" (zig/clang).

CC ?= arm-linux-gnueabihf-gcc
ifeq ($(origin CC),default)
CC = arm-linux-gnueabihf-gcc
endif
ARCHFLAGS ?= -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter -std=gnu99 $(ARCHFLAGS)
LDFLAGS ?= -static

# The shared-memory layout is shared with the MCU firmware: one copy of the
# headers, in the port (klipper/src/upc).
UPC_INC ?= ../klipper/src/upc

upctool: upctool.c $(UPC_INC)/upc_hw.h $(UPC_INC)/upc_ipc.h
	$(CC) $(CFLAGS) -I$(UPC_INC) -o $@ upctool.c $(LDFLAGS)

clean:
	rm -f upctool

.PHONY: clean
