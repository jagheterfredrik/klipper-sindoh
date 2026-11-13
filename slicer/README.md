# OrcaSlicer profiles

Tested with [OrcaSlicer](https://github.com/SoftFever/OrcaSlicer) only. The
profiles are named "DP200", but the 3DWOX 1 is the same machine: use them for
both.

## Import

**File → Import → Import Configs…** and select the three files in `orca/`:

| File | Orca type |
|---|---|
| `Sindoh DP200 Klipper 0.4 nozzle.json` | printer |
| `DP200 0.20mm Klipper.json` | process (0.20 mm layers) |
| `DP200 PLA.json` | filament |

If Orca asks, import the printer first: the process and the filament are tied
to "Sindoh DP200 Klipper 0.4 nozzle".

## What the profiles set

- **Bed:** 210 × 201 mm, origin at the front left (Klipper X 0 / Y 0, about
  2 mm in from the plate's front and left edges). Y can't reach the last
  ~4 mm at the back of the 216 × 209 mm plate. The plate's 4 × 11 mm notches
  at both back corners are left out of the printable area (X 0–4 and 206–210,
  Y 193–201). Measured 2026-10-27, to about ±1 mm.
- **Height:** 190 mm.
- **Start G-code:** `PRINT_START BED=… EXTRUDER=…`, then `PRIME_LINE`.
  `PRINT_START` heats, homes, purges and wipes over the bin; the slicer sends
  no heating commands of its own. `PRIME_LINE` draws a line at the very front
  edge of the plate (Y 0).
- **Bed mesh:** `PRINT_START` makes no mesh. Before the first layer the
  profile calls `MESH_ADAPTIVE`, which probes only the area the objects cover.
  It needs the object outlines, which Orca writes after the start G-code, so
  exclude-object labels stay on. The 3DWOX 1 `printer.cfg` also loads the
  saved `default` mesh at start-up, for prints without `MESH_ADAPTIVE`.
- **Cancel one object:** exclude-object labels let you cancel a single object
  in Mainsail or on the touch screen (OBJECTS on the print page).
- **End G-code:** `PRINT_END`.
- **Extrusion:** relative (M83), 4 mm retraction at 35 mm/s on the long
  Bowden tube, 0.2 mm z-hop on every retraction (without it the nozzle scuffed
  finished top surfaces). Retraction is a first guess. Pressure advance (0.30)
  is set in `dp200_printer.cfg`, not in the slicer.
- **Thumbnails:** 32×32 and 300×300 PNG, shown in Mainsail.
- **PLA:** 210 °C first layer, then 205 °C; bed 60 °C.

## Pressure-advance tower

`make_pa_tower.py` writes a ready-to-print tower (no slicer needed) for
Klipper's `TUNING_TOWER` method:

```sh
python3 make_pa_tower.py        # -> dp200_pa_tower.gcode
```

Upload and print it. Pressure advance rises 0.020 per mm of height (0 at the
bed, 1.0 at the top of the 50 mm tower). Find the height where the corners are
sharpest, with no bulge before them and no gap after them (ignore the front
left corner: that's the layer-change seam). Then put
`pressure_advance: <0.020 × height>` in the `[extruder]` section of
`printer.cfg`.

## Other slicers

Not tested. Set the values above by hand: use the start and end G-code as
given, turn off the slicer's own start-of-print temperature commands, and call
`MESH_ADAPTIVE` before the first layer (or start with `PRINT_START … MESH=4`
for a full 4×4 mesh).
