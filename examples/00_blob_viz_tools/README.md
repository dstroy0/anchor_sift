# Blob visualization tools

`view` is a symbolic link to where these are maintained. It resolves where both trees sit side by
side under `git_project`, and dangles anywhere else.

Three generators, each writing one self-contained HTML file. No server, no install, no dependencies
past the standard library. Open the output in a browser.

## A raw binary

```
python view/build_blob_view.py firmware.bin
```

Folds the bytes into a grid and builds eight readings of them: the byte, bits set, delta from the
previous byte, windowed entropy, distinct values in the window, run length, high nibble, low nibble.

Width is the only assumption. Nothing in a blob says how wide it is, so structure that appears at
one width and not another belongs to the width:

```
python view/build_blob_view.py firmware.bin --width 16 --offset 4096 --rows 4096
```

`--rows 0` reads the whole file. Past about 200,000 cells the page gets heavy, and it says so.

## Any table

```
python view/build_field_view.py data.csv
```

Long format, one row per cell. It works out which column holds the value, which one is the depth axis, and
which are the series, then says what it decided. Name them yourself when the guess is wrong:

```
python view/build_field_view.py data.csv --value amplitude --depth time --field sensor
```

## Both, once open

The same seven embeddings apply to whatever was loaded: plane, tube, toroid, sphere, cone, helix,
balloon. The embedding is a choice, not a measurement. Structure that shows under one shape and
vanishes under another belongs to the map, not to the data, so what agrees across shapes is
the part worth keeping.

Height and color are the value. The Floor slider hides the quietest cells, which is how a large
page becomes tractable.

## The rest

`build_step_view.py`, `build_shadow_view.py`, `build_sources_view.py` and `make_shadow_figure.py`
are the same machinery pointed at one specific measurement, and read files that only exist in the
repository they came from. They are here as worked examples of the pattern, not as tools for
general use.

That pattern: a generator computes numbers and injects them into a template as a single JSON
literal, replacing one marker. The template is a complete working page that can be opened and
edited with a browser on it; the generator never touches layout. Adding a viewer means writing a
generator that emits `{depth, depthLabel, valueLabel, title, blurb, fields:[{key, label, axis,
rows}]}`, where `rows` is one array per series over the depth axis.
