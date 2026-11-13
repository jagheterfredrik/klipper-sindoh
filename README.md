# Klipper for Sindoh 3DWOX printers, from a USB stick

Runs [Klipper](https://www.klipper3d.org/), Moonraker and Mainsail on a
Sindoh 3DWOX 1 (and, untested, a DP200) **without changing the printer**. With
the stick in, the stock firmware runs a small script from it, which starts
Klipper from a Debian image on the stick. Pull the stick and power-cycle: the
printer is stock again. Nothing is written to the printer's internal flash.

## Supported printers

| Printer | Status |
|---|---|
| Sindoh 3DWOX 1 | Tested on one unit: start from the stick, Wi-Fi, homing, motion at the right scale, extruder heater, probe, bed mesh. Bed PID and several inputs (door, filament encoder, cartridge chip) are still open; see [docs/model_audit.md](docs/model_audit.md). |
| Sindoh 3DWOX DP200 / DP201 | **Untested** from the stick. The printer config was developed on a DP200 (Klipper installed on its internal flash), but the stick's DP200 start script (`_update_rodin`) has never run on one. |
| 2X, 1X, 7X, 30X | Not supported (different SoC). |

The model is detected from the stock firmware tag (`RODUP_` = 3DWOX 1,
`RODIN_` = DP200).

## Install

### 1. Get the stick files

Build them (Docker with ARM emulation, for example Docker Desktop):

```sh
./build.sh image        # -> out/stick/   (first build: an hour or more)
```

Tagged releases attach the same files as `klipper-sindoh-stick-<version>.zip`.

### 2. Copy them to a stick

A FAT32 stick of at least 2 GB. Copy the **contents** of `out/stick/` to the
top of the stick (other files on it can stay):

```
_update_rodin_up/unmistakable_klipper_usb.she   start script for the 3DWOX 1
_update_rodin/unmistakable_klipper_usb.she      start script for the DP200 (untested)
dp200/launch.sh, stop.sh                        launcher (plain text)
dp200/dp200.img, dp200.img.md5                  the Debian root with Klipper
dp200/versions.txt                              what is in this build
```

### 3. Start

Plug the stick in and power on (or plug it into a printer that has already
booted). The launcher lets the stock firmware finish joining Wi-Fi, up to a
minute, then replaces the Sindoh app with Klipper: the touch screen shows the
Klipper screen, and Mainsail answers at `http://<printer-ip>/`. Wi-Fi uses the
networks saved in the stock firmware; Ethernet uses DHCP. Each start is logged
in `dp200/launch.log` on the stick.

### 4. Check and calibrate

On the first start, `printer.cfg` is created for your model. The 3DWOX 1
template starts from the values of the first tested unit.

1. **Step check, before anything else:** `FORCE_MOVE STEPPER=stepper_x
   DISTANCE=10 VELOCITY=5`, then `UPC_STEP_STATS`. The pulse count must equal
   the step count, and a ruler should show 10 mm.
2. Z switch height and probe offset: `LV_PROBE_CALIBRATE`, paper test, then
   `SAVE_CONFIG`.
3. `PID_CALIBRATE HEATER=extruder TARGET=210` and
   `PID_CALIBRATE HEATER=heater_bed TARGET=60`, each followed by `SAVE_CONFIG`.
4. A bed mesh: `BED_MESH_CALIBRATE`, then `SAVE_CONFIG`. It's saved as the
   `default` mesh.

## Slicing

Use OrcaSlicer with the profiles in [slicer/](slicer/README.md) (printer,
0.20 mm process, PLA). The start G-code is `PRINT_START`, then `PRIME_LINE`.
An adaptive bed mesh (`MESH_ADAPTIVE`) runs before the first layer. Other
slicers are untested.

## Update

Your `printer.cfg`, print history and saved networks live inside `dp200.img`.
Build the new image with the old one as input and they are carried over. The
shared config, scripts and firmware are the new ones.

```sh
cp /Volumes/<stick>/dp200/dp200.img old-dp200.img
KEEP_STATE=old-dp200.img ./build.sh image
```

Then copy `out/stick/` over the stick as before.

## Remove

Power off from Mainsail or the touch screen, pull the stick, power-cycle. From
a shell: `sh /mnt/sda1/dp200/stop.sh`. Never pull the stick while Klipper is
running: its root file system is on the stick.

## Safety

- Klipper replaces the stock firmware's motion control and heater safety with
  its own (`verify_heater`, `max_temp`). Don't leave a first print unattended.
- **Z homes upward:** the bed rises to the switch. Clear the bed before homing
  Z.
- The 3DWOX 1 template starts with gentle motion limits (acceleration 500,
  X/Y homing 50 mm/s, Z 3 mm/s). Raise them one at a time.
- Mainsail's emergency stop (`M112`) shuts Klipper down; `FIRMWARE_RESTART`
  recovers.
- The stock firmware's root shell and TFTP server stay reachable on the LAN
  (stock crontab). An empty file `dp200/debug` on the stick adds a root shell
  on tcp/2323. Use the printer on trusted networks only.

## For developers

```
klipper/        the Klipper port, added to an UNMODIFIED upstream Klipper
  src/upc/        MCU port for the two UPC coprocessors of the Marvell 88PA6170
  patches/        the one change to an upstream file: MACH_UPC in src/Kconfig
  kconfig/        build configs of the two cores (FM: motion, IO: heaters/fans/ADC)
  extras/         klippy modules: upc_stats, upc_clockcheck, dp200_cartridge
  config/         common/ (hardware + macros), 3dwox1/ and dp200/ printer.cfg templates
  test/           Unicorn emulator smoke test of both images
  install_port.sh, build_firmware.sh, klipper.lock (pinned upstream commit)
upctool/        host bridge: loads the images, links the cores' shared memory to ptys
image/          the stick: Docker builder, runtime scripts, screen app, overlays, stubs
slicer/         OrcaSlicer profiles, pressure-advance tower
```

`./build.sh firmware` builds only the two MCU images and runs the emulator
test (`out/firmware/`); `./build.sh clean` drops the build cache (Docker
volume `klipper-sindoh-build`).

### Using the port without the stick

On any Linux Klipper install with an `arm-none-eabi-gcc` toolchain:

```sh
klipper/install_port.sh ~/klipper          # patch + files, safe to repeat
klipper/build_firmware.sh ~/klipper ./fw   # fm/io images + emulator test
```

Then copy `klipper/config/common/*` and the model's `printer.cfg` to
`printer_data/config/`. The firmware is loaded with `upctool load io.bin fm.bin`
and bridged with `upctool bridge` (see `image/runtime/rootfs/etc/dp200/rc.dp200`).

### Keeping up with upstream Klipper

`klipper/klipper.lock` pins the upstream commit. The port only adds files,
plus a 3-line patch that registers the UPC machine in `src/Kconfig`, so an
upstream update needs work only when that patch stops applying or an internal
MCU API the port uses changes. Keep it that way: changes to upstream's own
files (for example `src/stepper.c`) are what make a port expensive to carry.

CI (`.github/workflows/`):
- **firmware:** every push builds both images and runs the emulator test. A
  weekly job builds against upstream master and opens a PR that bumps the lock
  when it passes, or an issue when it doesn't. (The PR needs "Allow GitHub
  Actions to create and approve pull requests" in the repo settings.)
- **release:** a `v*` tag builds the stick under qemu and attaches the stick
  zip, the firmware and `SHA256SUMS` to a GitHub release.

To refresh the patch by hand: apply it with `git apply --3way` in an upstream
checkout, fix the conflict, and `git diff` the file back into
`klipper/patches/`.

## Credits

The Klipper port is the work of [catawalks](https://github.com/catawalks): the
reverse engineering of the Sindoh firmware and hardware, the UPC MCU port,
`upctool`, the klippy extras, the printer configuration, the touch screen app
and the runtime scripts all come from
[catawalks/sindoh](https://github.com/catawalks/sindoh) and the
[catawalks/klipper](https://github.com/catawalks/klipper) fork (branch
`sindoh-dp200`). This repository packages that work as a Klipper add-on and a
USB-stick image, and adds the 3DWOX 1 support. The research repository has the
full history, hardware notes and tools.

Built on [Klipper](https://github.com/Klipper3d/klipper),
[Moonraker](https://github.com/Arksine/moonraker) and
[Mainsail](https://github.com/mainsail-crew/mainsail).
