# Model audit: 3DWOX 1 vs DP200 (2026-11-13)

Which files in this repo are specific to the 3DWOX 1, specific to the DP200,
or shared. This is input to the repo split (Klipper port and USB stick moving
to their own repo) and to how the config is laid out per model.

Sources: [3DWOX1.md](../3DWOX1.md), [3dwox1_calibration.md](3dwox1_calibration.md),
[other_models.md](other_models.md), [hardware_notes.md](hardware_notes.md),
the commits of 2026-11-11 to 2026-11-13, and the files themselves at `HEAD`
(2502a9b). The uncommitted changes to `dp200_printer.cfg` and the orca
profiles were read but not changed. They are print-start behaviour changes
(no mesh by default, no bed-empty question, `MESH_ADAPTIVE`) and are not
model-specific.

## Summary

1. **No printer config is 3DWOX 1-specific today.** The 3DWOX 1 runs the same
   firmware family (`RODIN_SUB=U`), SoC, kernel, UPC firmware and Klipper
   config as the DP200. The 2x travel seen on 2026-11-12 was a firmware build
   fault, not a model difference (calibration notes, section 8).
   `rotation_distance` is the stock 40/40/1/6.975 on both.
2. **The model differences are on the stock Linux side**: USB update folder and
   cipher, firmware tag, free NAND space, and what `/DEBUG_MACHINE` does to
   Wi-Fi DHCP. They affect the *installers*, not Klipper.
3. **The stepper driver board is a separate axis from the model.** The tested
   3DWOX 1 has the newer Trinamic board (TMC2224 over UART on `/dev/ttyS2`,
   detected by the stock app through GPIO bank 2 pin 0). The config and
   `hardware_notes.md` describe the Allegro A4982 board of the development
   DP200. Either board may exist in either model. See "Driver board" below.
4. **Model detection already exists.** `dp200-start.sh` reads `RODIN_` or
   `RODUP_` from `/snapshot_version.sh`, and `dp200_screen.py` names the model
   from it (`MODEL_BY_FW`). The update folder that ran the stub is a second,
   independent signal.
5. **The 3DWOX 1's per-unit values exist only on the stick**, in its
   `printer.cfg`: `z_offset` 2.678, extruder PID 14.565 / 1.566 / 33.865 and
   gentler motion limits. They are not in the repo.

## Driver board (A4982 vs TMC2224)

| | Development DP200 | Tested 3DWOX 1 |
|---|---|---|
| Driver | Allegro A4982 | TMC2224, UART on `/dev/ttyS2` |
| Microsteps | 16 (MS pins; config comment says "MS1/MS2 unknown") | 16 (CHOPCONF `0x14010053`) |
| Current | REF from filtered PWM (`motor_current_*` pins) | GCONF `0x141` has `I_scale_analog` = 1, so the VREF pin still scales current (inferred) |
| Who sets the driver up | nothing to set up | the stock app, over UART, at boot |

Under the USB live start the stock app always runs before Klipper, so a
TMC2224 is already configured when Klipper takes over. That's why it worked
unchanged. This doesn't hold for any boot path that skips the stock app
(`/DEBUG_MACHINE`, the NAND hook): there the TMC2224 starts with its power-on
defaults. Klipper has no TMC section in the config, so it doesn't set the
drivers up.

Before relying on the shared config for every unit:
- confirm on the 3DWOX 1 that `motor_current_*` still changes the motor
  current;
- read what the stock app writes over UART, so the setup can be repeated
  without it.

This is a per-board choice, and the board can be detected at runtime. It does
not belong in the per-model config.

## Values seen on the 3DWOX 1 that may or may not be model differences

| Item | Shared config | 3DWOX 1 | Status |
|---|---|---|---|
| Z speed | `max_z_velocity` 5, homing 5 | stalled at "5 mm/s" | That test ran at the 2x scale (about 10 mm/s real), which stalls on the DP200 too. **Retest at 1:1.** |
| X/Y homing | 208 mm/s | "violent", lowered to 50 on the stick | Also at 2x (about 416 mm/s real). **Retest at 1:1.** |
| `max_accel` | 3000 | 500 on the stick | Set after the scale fix as a precaution. **Retest.** |
| Z travel | `position_max` 194 | "198 mm" in 3DWOX1.md | Measured by step count with the faulty firmware; the calibration notes call the figure doubtful. **Re-measure.** |
| Probe x/y offset | 23.5 / -28.0 | same values, not re-measured | **Measure with a ruler.** |
| `z_offset`, PIDs | DP200 unit values | per unit (on the stick) | Per-unit calibration, as on any printer; not a model difference. |
| Bed PID | DP200 unit values | not calibrated | Open. |
| Thermistor tables | `dp200_nozzle`, `dp200_bed` | raw readings match at room temperature | Not checked against a thermometer. |
| Extruder clutch, fans, lamp, encoder, door and lever inputs, cartridge chip | shared | not tested | Open (3DWOX1.md). |

Until one of these is confirmed as a model difference, the 3DWOX 1 needs no
config of its own.

## File by file

S = shared, D = DP200-only as written, W = 3DWOX 1-only as written.

### Klipper port and config

| File | Class | Notes |
|---|---|---|
| `klipper/src/upc/*`, `common/upc_*.h`, `klipper/configs/dp200_{fm,io}.config` | S | Same SoC and UPC cores. **Not the source of truth**; see below. |
| `klipper/extras/upc_stats.py`, `upc_clockcheck.py` | S | |
| `klipper/extras/dp200_cartridge.py` | S | Same cartridge chip path expected; not tested on the 3DWOX 1. |
| `klipper/config/dp200_printer.cfg` | S | A4982 comments describe the DP200 board only (see above). |
| `klipper/config/dp200_macros.cfg` | S | Coordinates (bin, lever at X -10..-20, bed area) are the same machine; the lever position is still to be confirmed on the 3DWOX 1. |
| `klipper/config/printer.cfg` | S | Header says "Sindoh DP200" and the values are the development DP200's: per-unit template. |
| `klipper/config/dp200_adxl.cfg.off` | S | |
| `klipper/patches/*`, `make_fork.sh` | S | Stale; superseded by the fork (see below). |

### Stick and installers

| File | Class | Notes |
|---|---|---|
| `install/usb_live/stick/unmistakable_klipper_usb.sh` | S | The script itself has nothing model-specific. |
| `install/usb_live/in_container.sh` (packing step) | W | Packs only `_update_rodin_up` with AES `sindoh024601779U`. The DP200 needs `_update_rodin` with des3 (`pack_she.sh`). |
| `install/usb_live/stick/launch.sh`, `stop.sh` | S | Wait for `/tmp/dmesg.boot.txt` (written after UIManager starts): verified on the 3DWOX 1 only. |
| `install/usb/*` (NAND/SD installer) | D | `_update_rodin`, des3, firmware check against `RODIN_`. The 3DWOX 1 has 34.5 MB free on its root (DP200: 54 MB). |
| `install/printer/hook_install.sh`, `hook_remove.sh`, `dp200-boot.sh` | D | Use `/DEBUG_MACHINE`. On the 3DWOX 1 firmware that boot leaves Wi-Fi without DHCP (3DWOX1.md). Not used by the stick. |
| `install/nand/*` | D | NAND install path; tested on the DP200 only. Only `runtime.exclude` is used by the stick build. |
| `install/printer/dp200-start.sh` | S | Kills the stock app, reads the model from `/snapshot_version.sh`. |
| `install/printer/dp200-wifi*.sh`, `dp200-netd.sh` | S | `mlan0`, `eth0`, `karas.db`: same on both. On the stick path the stock app has already started `udhcpc`, which matches the 3DWOX 1 findings. |
| `install/printer/dp200-powerkey.sh`, `dp200-mounts.sh`, `dp200-entropy.py` | S | |
| `install/printer/dp200-sntp.py` | S | Mainline-kernel boot only; not used by the stick. |
| `install/rootfs/etc/dp200/rc.dp200` | S | The UPC bridge uses ptys, not TCP 9100, so the 3DWOX 1's busy port 9100 doesn't matter here (it only affects the `tools/` test scripts). |
| `install/rootfs/etc/dp200/init.mainline` | S | Mainline kernel path; not used by the stick. |
| `install/rootfs/.../moonraker.conf`, `dp200_moonraker.conf`, nginx | S | |
| `install/display/dp200_screen.py`, `dp200_wifi.py`, `dp200_net.py` | S | Same 800×480 portrait panel (boot-logo table in other_models.md); model name from the firmware tag. |
| `install/camera/*` | S | |
| `install/kernel_modules/cdc-acm.ko` | S | Same kernel build (`3.2.0-g67a8e16`). |
| `install/input_shaping/*` | S | |
| `install/slicer/*` | S | Profiles are named "DP200" but the machine geometry is the same; a 3DWOX 1 name is cosmetic. |
| `install/rescue/README.txt` | D | NAND recovery for the DP200. |
| `install/build_rootfs.sh`, `build_rootfs_native.sh`, `rootfs_inside.sh`, `write_sd.sh` | D | SD-card and on-printer build paths; the 3DWOX 1 has no microSD slot. |

## Source of truth: the fork is ahead of this repo

The working `fm.bin` (the one that fixed the 2x travel) was built from
[catawalks/klipper](https://github.com/catawalks/klipper), branch
`sindoh-dp200` (HEAD acfbcde, 2026-11-11, base upstream 9cb9975, 23 commits).
Compared with this repo:

- **The fork changes upstream core files**: `src/stepper.c` (+115 lines,
  `UPC_STEP_SINGLE` and `UPC_STEP_BATCH`) and `src/sched.c` (+8,
  `upc_sleep_busy`). `install_port.sh` only copies `src/upc` and registers
  Kconfig, so **building from this repo gives an `fm.bin` with
  `CONFIG_UPC_STEP_BATCH=y` but without the stepper.c side**: the 2x-travel
  firmware. That applies to `build_rootfs.sh` step 6, and with it to the
  current `install/usb_live` build.
- **The fork's `src/upc` is newer**: `UPC_ADC_HOLD_US` in Kconfig and
  `adc.c`, and the `sched.c` half of the load accounting. `main.c` here still
  says that half is "to go into the fork".
- **This repo's config is newer**: `dp200_printer.cfg` and `dp200_macros.cfg`
  differ from the fork's `config/sindoh-dp200/` by 160 and 188 lines (the
  2026-11-12 load/home/pause/prime work and the 2026-11-13 step comment).
  `printer.cfg` differs by 5 lines. The extras, `dp200_adxl.cfg.off` and the
  `.config` files are identical.

Consequences for the split:
- The MCU code can't be an add-on that only copies files into upstream
  Klipper; it needs the `stepper.c` and `sched.c` changes. It has to come
  from the fork (or from patches against upstream that touch those files).
- Before anything moves, the two copies need to be reconciled: MCU code from
  the fork, config from here.

**Update (same day):** the new repo (`klipper-sindoh`) took the MCU code from
the fork and the config from here, then dropped `UPC_STEP_SINGLE` and
`UPC_STEP_BATCH` (no measured need; they were the `stepper.c` and `sched.c`
changes, and the cause of the 2x trap). The firmware now pulses on the step
edge of klippy's normal step/unstep pair, so the only change to an upstream
file is registering `MACH_UPC` in `src/Kconfig`, and the port works as an
add-on.

## Proposed config layout

Following from the above, there is no need for a per-model config set yet:

```
config/
  common/      printer hardware + macros (today's dp200_printer.cfg, dp200_macros.cfg, adxl)
  3dwox1/      printer.cfg template only (includes common/; per-unit values)
  dp200/       printer.cfg template only
```

A model directory gains overrides only when a retest from the table above
confirms a real model difference. The driver board question (A4982 vs
TMC2224) is handled by board detection, not by model.

## To do before the 3DWOX 1 counts as supported

- Retest Z speed, X/Y homing speed and `max_accel` at the 1:1 scale.
- Re-measure Z travel and the probe x/y offsets.
- Calibrate the bed PID; check both thermistors against a thermometer.
- Test the extruder clutch, fans, lamp, filament encoder, door and lever
  inputs, and the cartridge chip.
- Find out what the stock app writes to the TMC2224, and whether
  `motor_current_*` still sets the current on that board.
- Copy the 3DWOX 1's per-unit values from the stick's `printer.cfg` into the
  3DWOX 1 template (as examples, like the DP200 ones).
