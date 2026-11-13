# Klipper for Sindoh 3DWOX printers, from a USB stick

Runs [Klipper](https://www.klipper3d.org/), Moonraker and Mainsail on a
Sindoh 3DWOX 1 (and, untested, a DP200) **without changing the printer**.
Put the stick in and power on: the stock firmware runs a small script from
the stick, which starts Klipper from a Debian image on the stick. Pull the
stick and power-cycle: the printer is stock again. Nothing is written to the
printer's internal flash.

## Supported printers

| Printer | Status |
|---|---|
| Sindoh 3DWOX 1 | Tested on one unit: start from the stick, homing, motion at the right scale, extruder heater, probe. Bed PID, a full print and several inputs are still open (docs/model_audit.md). |
| Sindoh 3DWOX DP200 / DP201 | **Untested** with the stick. The same hardware config was developed on a DP200 (installed on its internal flash), but this stick's DP200 start path (`_update_rodin`, des3) has never run on one. |
| 2X, 1X, 7X, 30X | Not supported (different SoC) |

The model is picked automatically from the stock firmware tag (`RODUP_` =
3DWOX 1, `RODIN_` = DP200); see [docs/model_audit.md](docs/model_audit.md).

## Get the stick files

Download `klipper-sindoh-stick-<version>.zip` from the releases, or build it
(Docker with ARM emulation, e.g. Docker Desktop):

```sh
./build.sh image        # -> out/stick/   (first build: an hour or more)
./build.sh firmware     # only the MCU firmware + emulator test -> out/firmware/
./build.sh clean        # drop the build cache (Docker volume klipper-sindoh-build)
```

## Copy to the stick

FAT32 stick, at least 2 GB. Copy the **contents** of `out/stick/` to the top
of the stick:

```
_update_rodin_up/unmistakable_klipper_usb.she   start script for the 3DWOX 1
_update_rodin/unmistakable_klipper_usb.she      start script for the DP200 (untested)
dp200/launch.sh, stop.sh                        launcher (plain text)
dp200/dp200.img, dp200.img.md5                  the Debian root with Klipper
dp200/versions.txt                              what is in this build
```

Plug it in, power on. Once the stock boot is done the Sindoh app is replaced
by the Klipper touch screen, and Mainsail answers at `http://<printer-ip>/`. The printer joins the
Wi-Fi networks saved in the stock firmware; Ethernet uses DHCP. The log is
`dp200/launch.log` on the stick.

On the first start `printer.cfg` is created for your model. Calibrate it
(Z endstop / probe offset with `LV_PROBE_CALIBRATE`, `PID_CALIBRATE` for both
heaters) and `SAVE_CONFIG`. **Your `printer.cfg` lives inside `dp200.img`:**
download it from Mainsail before you copy a new `dp200.img` to the stick, and
upload it again afterwards.

## Remove

Stop Klipper from Mainsail or the screen (power off), pull the stick,
power-cycle. Or from a shell: `sh /mnt/sda1/dp200/stop.sh`. Never pull the
stick while Klipper runs: its root file system is on the stick.

## Safety

- Klipper replaces the stock firmware's motion control and heater safety
  with its own (`verify_heater`, `max_temp`). Don't leave a first print
  unattended.
- **Z homes upward**: the bed rises to the switch. Clear the bed before
  homing Z.
- The 3DWOX 1 template starts with gentle motion limits (acceleration 500,
  homing 50 mm/s, Z 4 mm/s): raise them one at a time.
- Mainsail's emergency stop (`M112`) shuts Klipper down;
  `FIRMWARE_RESTART` recovers.
- The stock firmware's root shell and TFTP server stay reachable on the LAN
  (stock crontab); an empty file `dp200/debug` on the stick adds a root
  shell on tcp/2323. Use it on trusted networks only.

## How it is put together

```
klipper/        the Klipper port: added to an UNMODIFIED upstream Klipper
  src/upc/        MCU port for the two UPC coprocessors of the Marvell 88PA6170
  patches/        the one change to an upstream file: registering MACH_UPC in src/Kconfig
  kconfig/        build configs of the two cores (FM: motion, IO: heaters/fans/ADC)
  extras/         klippy modules: upc_stats, upc_clockcheck, dp200_cartridge
  config/         common/ (hardware + macros), 3dwox1/ and dp200/ printer.cfg templates
  install_port.sh, build_firmware.sh, klipper.lock (pinned upstream commit)
  test/           Unicorn emulator smoke test of both images
upctool/        host bridge: loads the images, links the cores' shared memory to ptys
image/          the stick: Docker builder, runtime scripts, screen app, overlays, stubs
slicer/         Orca, PrusaSlicer and Cura profiles
```

### Using the port without the stick

On any Linux Klipper install with an `arm-none-eabi-gcc` toolchain:

```sh
klipper/install_port.sh ~/klipper      # patches + files, safe to repeat
klipper/build_firmware.sh ~/klipper ./fw   # or build by hand: config/dp200_fm.config
```

Then copy `klipper/config/common/*` and the model's `printer.cfg` to
`printer_data/config/`. The firmware is loaded with `upctool load io.bin fm.bin`
and bridged with `upctool bridge` (see `image/runtime/rootfs/etc/dp200/rc.dp200`).

### Keeping up with upstream Klipper

`klipper/klipper.lock` pins the upstream commit. The port only adds files,
plus a 3-line patch that registers the UPC machine in `src/Kconfig`, so an
upstream update only needs work when that patch stops applying or an
internal MCU API the port uses changes. Keep it that way: changes to
upstream's own files (for example `src/stepper.c`) are what make a port
expensive to carry. A weekly CI job builds against
upstream master: when the patches apply and the emulator test passes it opens
a PR that bumps the lock; otherwise it opens an issue. To refresh a patch by
hand: apply it with `git apply --3way` in an upstream checkout, fix the
conflict, and `git diff` the file back into `klipper/patches/`.

The research behind the port (reverse engineering, hardware notes, kernel
work, tools) is in the separate research repository.
