# Viewers

Each is a Python generator plus an HTML template. The generator writes the numbers into the
template as one JSON literal and emits a single self-contained file: no server, no install, no
fetch at run time. Standard library only.

## What is general and what belongs to this tree

The general ones take their input as an argument and open nothing else. They are the toolkit
candidates. The rest hardcode a path into this repository and are examples of the pattern,
not tools:

| general | reads |
|---|---|
| `build_blob_view.py` | any file you name |
| `build_field_view.py` | any long-format table you name |
| `build_chart_view.py` | any table you name |
| `build_plot_view.py` | an expression you type |
| `build_sound_view.py` | a wav you name, or its own generated signal |
| `build_sweep_view.py` | the same, swept across analysis settings |
| `dsp.py` `exact.py` `settings.py` | shared, no inputs of their own |

| stays here | why |
|---|---|
| `build_voxel_view.py` `build_shadow_view.py` `build_sources_view.py` | open `src/bench/*.csv` |
| `make_shadow_figure.py` | opens `src/bench/shadows.csv` |
| `build_step_view.py` | traces SHA-256, which is this tree's subject |

Checked by opening each one and never by pattern: `make_shadow_figure.py` reads as general to a
grep for `src/bench` because it builds the path with two nested `dirname` calls, and it is not.

## Opening state

Every general generator takes `--set key=value`, repeatable. A caller asks for a view instead of
publishing one and describing which controls to move. An unknown key exits with the list of known
ones, because a typo is otherwise silent and the page just opens looking wrong.

```
python build_blob_view.py file.bin --set shape=hilbert --set spin=0.3 --set theme=dark
python build_field_view.py data.csv --set floor=20 --set order=64 --set contrast=0.35
```

Settings cover the step and representation, the transform, the overlay, the ramp and contrast, box
opacity, the observer as yaw, pitch and distance, and spin in turns per minute.

## Solids

```
python build_blob_view.py FILE                 any binary, eight readings of its bytes
python build_field_view.py TABLE.csv           any long-format table
python build_plot_view.py "sin(x)*cos(y)"      an expression over a grid
```

All three write the same page: the data as a mesh you turn, 32 representations, 9 transforms.
Height and color are the value.

The readouts box holds the distribution. Drag it to select a range, click for one bin; matching
cells light up with a count and a share. Click a cell in the object and its value is marked on the
distribution.

## Flat charts

```
python build_chart_view.py TABLE.csv
python build_chart_view.py TABLE.csv --x time --y temperature pressure
python build_chart_view.py long.csv --split sensor --y value --kind scatter
```

Line, scatter, step, bar, area. Hover reads the nearest point, drag zooms x, double click resets,
series toggle off, y switches to log. It prints which columns it chose, making a wrong guess visible.

## One hash

```
python build_step_view.py --bit 96
```

Two SHA-256 traces, a message and the same message with one bit flipped, every intermediate kept.

## On representations

A representation decides where a cell sits. Joining the ends of an axis says the last value is next
to the first, which is a period the picture adds. The plane joins nothing. Keep the reading that
holds up when it is drawn several ways.

## Boundaries

What a closed surface can hold, and what can be read back off it. These carry checks that fail, so
run the check before trusting the picture.

```
python sphere_field.py --check          the harmonics, the depth law, the null
python boundary_count.py --check        the area law on a sphere, exactly, to 40 dimensions
python torus_count.py --check           the same law on a flat torus, by counting lattice points
```

A source at radius r inside a ball reaches harmonic degree l as (r/R)^l, so depth sets bandwidth and
a source prints a patch of angular size about d/R however small it is. A spot on a boundary is
always wider than the thing that made it. Counting the modes that survive gives an area law: the
count goes as the surface measure over the resolution, raised to the dimension of the surface, and
never as the volume.

```
python build_sphere_view.py FILE        a blob written onto the inside of a scattering ball
python build_orrery_view.py             a known system inside, derived back from the boundary alone
python build_room_view.py               a dark room, a carried beam, and a shell you can pass through
```

`build_sphere_view.py` ships the placement you asked for alongside the same sources placed at
random, on the same axes. A symbol has a rareness without anyone choosing anything; it does not have
a direction, so whatever supplies one is a choice, and a degree where the chosen map beats the null
is the only place worth reading.

`build_orrery_view.py` writes the interior down first and then shows only the surface, and a viewer
that draws a convincing picture and recovers the wrong radius is caught in the same glance. Recovery
is a harmonic-sum periodogram across six patches, and a period is believed where three independent
axes agree on it.

`build_room_view.py` puts the reader inside, because the outside of one shell is the inside of the
next. The shell is a window to whoever is outside and a wall to everything within. Dwell sorts the
light by how long it stayed: early light went straight and prints an edge, late light arrives from
everywhere and fills the shadow it would have cast.

### On the card

```
powershell build_pack.ps1               builds the packer, importing vcvars for nvcc
python gpu_pack.py --check              shape against shape, packed on the device
```

Spherical harmonics settle the dimension half of the area law and live only on spheres, so shape has
to be packed. The device counts and does nothing else: every measure, constant and verdict is
computed on the host from closed forms that never read a count.

A packing count means something only while the gap stays well under the typical distance between two
points on the surface. Past that the count stops being what the geometry allows and becomes how many
unusually distant pairs the draw happened to hold. The tool enforces that limit and refuses to report
a row outside it, which is worth more than the row.
