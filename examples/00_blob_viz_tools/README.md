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
