# Every option the viewers expose, before the bar is designed

One row per option across every blob viz unit: what it controls, which data key it reads, what it
does when that key is absent, and whether that absence is silent. The shared control bar is designed
from this. The survey comes before the bar.

Read from `examples/00_blob_viz_tools/`: the 23 `build_*_view.py`, the 14 `*_view_template.html`,
and the engine viewer under `view/engine_view/`. No unit is changed here; this only records what is.

## The lead finding: every builder with a template reaches it

A template holds its data in a marker, `var DATA = /*ROOM_DATA*/ null;`, with a space before `null`.
Each builder matches the marker its template carries, tolerant of the whitespace around `null`, and
writes its data in place of it. A builder handed a template whose marker is absent writes no page and
says so. One builder has no template to write into at all.

| outcome | what happens | builders |
|---|---|---|
| injects | the builder matches its template's marker and writes the page carrying its data | every builder with a template |
| no template | `build_blind_view.py` targets `blind_view_template.html`, which is not in the tree | blind |

Twenty-two builders inject. One has no template. The marker forms vary across the templates, from
`/*DATA*/` through `/*PAIRS_DATA*/` to the spaced `/*XXX_DATA*/ null`, and each builder matches the
marker its own template carries. No template in the tree is missing its marker. None of the
twenty-two fails loud here; the loud failure guards against a template that drops its marker.

## The committed pages carry data no builder now writes

Four built pages sit beside the tools: `shadow_view.html`, `sources_view.html`, `step_view.html`,
`voxel_view.html`. Each holds its data as a JavaScript object with unquoted keys, `depth: 64`, while
every builder writes `json.dumps`, `"depth": 64`. `data_check` and `inert_report` read strict JSON
and report all four as not JSON. They hold data no current builder writes, and no current builder
injects into the current template. They cannot be rebuilt from the tree.

## The engine viewer: the option model the bar generalizes

The viewer under `view/engine_view/` already carries the discipline the bar needs. `cfg.js` holds
`EV.VIEW_SCHEME`, one entry per option, each with a kind, a range, and a fallback. `EV.errorValue`
reports a value of the wrong kind or out of range by name, and `EV.applyView` applies a partial view
and returns what it took and what it refused, each by name. An absent option takes its fallback; a
wrong one is named, never dropped. Nothing here goes silently inert. The template controls above do
the opposite, and the bar carries this shape to every unit.

Each option reads the view section of the page's `.cfg` under its own name.

| option | kind | range or words | fallback |
|---|---|---|---|
| face | word | human, machine | human |
| frame | integer | 0 to 65535 | 0 |
| turn | integer | 0 to 359 | 30 |
| tilt | integer | -89 to 89 | 35 |
| zoom | integer | 0 to 1024 | 0 |
| pan_x | integer | -1048576 to 1048576 | 0 |
| pan_y | integer | -1048576 to 1048576 | 0 |
| z_scale | integer | 2 to 16 | 8 |
| spread | integer | 0 to 2048 | 0 |
| ghosts | integer | 0 to 8 | 0 |
| ghost_fade | integer | 0 to 224 | 48 |
| body | word | smooth, voxels, centroids | smooth |
| smooth_radius | integer | 1 to 8 | 3 |
| smooth_opacity | integer | 1 to 255 | 16 |
| body_opacity | integer | 0 to 255 | 160 |
| min_voxels | integer | 0 to 65536 | 0 |
| palette | word | lineage, okabe_ito, cell, volume | okabe_ito |
| glow | switch | on, off | on |
| slide | integer | 0 to 255 | 0 |
| walls | switch | on, off | on |
| wall_tone | integer | 0 to 255 | 110 |
| wall_opacity | integer | 1 to 255 | 220 |
| map | word | projection, slice | projection |
| slice | switch | on, off | on |
| slice_follow | switch | on, off | on |
| slice_z | integer | -1 to 65535 | -1 |
| window_low | integer | 0 to 65535 | 0 |
| window_high | integer | 1 to 65535 | 1024 |
| links | switch | on, off | on |
| tracks | switch | on, off | off |
| edges | switch | on, off | on |
| correct | switch | on, off | on |
| branched | switch | on, off | on |
| wrong | switch | on, off | on |
| no_link | switch | on, off | on |
| only_chosen | switch | on, off | off |
| labels | switch | on, off | on |
| ride | switch | on, off | off |
| rate | integer | 0 to 60 | 2 |
| step | integer | 1 to 64 | 1 |
| loop | switch | on, off | on |
| light | switch | on, off | on |
| lights | lights | up to four, each turn, tilt, strength | two, at 300/50/210 and 130/20/90 |
| sheer | integer | 20 to 100 | 90 |
| text_size | integer | 80 to 200 | 100 |
| theme | word | dark, light | dark |
| panels | words | counts, dims, lineage, legend, review, machine | counts |
| chosen | integers | 0 to 4294967294 | none |

## Each builder: its options, its template, its payload

The command options a builder exposes, the template it writes, and the top-level keys its payload
carries. Keys read statically from the payload the builder hands `json.dumps`, the literal and any
key added to it; the two sphere builders assemble theirs in a helper, and those keys are read from
its returned dict.

| builder | template | command options | payload top-level keys |
|---|---|---|---|
| build_blind_view | blind_view_template (absent) | --degree --count --check | degree, count, width, rank, blind, floor, rows, columns, seats, cells, arrows, spectrum |
| build_blob_view | voxel | none | depth, depthLabel, valueLabel, eyebrow, title, blurb, noteTitle, note, settings, schema, fields |
| build_block_view | block | --out | height, id, bytes, fields, values, windowShares, constants |
| build_chart_view | chart | none | title, xLabel, kind, blurb, series |
| build_earth_view | earth | --corpus --out | total, days, hours, weekdays, intervals, chi, nullMean, null95, p, regions |
| build_field_view | voxel | --value --depth --field --title --out | depth, depthLabel, valueLabel, eyebrow, title, blurb, note, settings, schema, fields |
| build_orrery_view | orrery | --bodies --frames --mode --degrees --tau --seed --out | mode, degrees, tau, span, frames, bodies, profiles, curve, watched, found, attenuation, settings |
| build_plot_view | voxel | none | depth, depthLabel, valueLabel, eyebrow, title, blurb, noteTitle, note, settings, schema, fields |
| build_room_view | room | --shell --core --things --seed --blob --out | shell, core, source, things, settings, schema |
| build_scope_view | scope | --block --out | height, nonce, id, spikes, rounds, spectrum, waveform, sigma0, sigma1 |
| build_sha_clock_view | room | --message --rounds --glow --seed --shell --core --sources --degrees --tau --out | shell, core, sources, source, things, clock, settings, schema |
| build_sha_pairs_view | pairs | --message --out | pairs, frames, digest, source |
| build_sha_room_view | room | --field --every --rounds --glow --seed --shell --core --source --out | shell, core, source, things, settings, schema |
| build_sha_sphere_view | sphere | --samples --rounds --place --tau --degrees --out | title, place, tau, bytes_read, symbols, grid, spectrum, null_spectrum, profiles, sources, read, settings, schema, floor |
| build_shadow_view | shadow | none | rounds, residue, inbit, outbit, word |
| build_sound_view | voxel | none | depth, depthLabel, valueLabel, eyebrow, title, blurb, noteTitle, note, settings, schema, fields |
| build_sources_view | sources | none | rounds, sources, order |
| build_sphere_view | sphere | --place --heat --depth --radius --degrees --tau --title --bytes --offset --out | title, place, heat, degrees, tau, bytes_read, symbols, grid, spectrum, null_spectrum, profiles, sources, read, settings, schema |
| build_spiral_view | spiral | --dir --out | arms, perArm, total, points, words, agreement, unanimousByChance |
| build_step_view | step | none | flipped, flippedWord, flippedBit, keys, message, schedule, rounds |
| build_survey_view | survey | --dump --out | samples, positions, worstAt, worstReach, sumZMillionths, histogram, sensitivity, words |
| build_sweep_view | voxel | none | depth, depthLabel, valueLabel, eyebrow, title, blurb, noteTitle, note, settings, schema, fields, swept |
| build_voxel_view | voxel | none | depth, depthLabel, valueLabel, eyebrow, title, blurb, noteTitle, note, settings, schema, fields |

## Each template: the keys its controls read

Every `DATA.<key>` a template reads, and whether the read is guarded. A guarded read asks before it
reads. An absent key takes a fallback and the control it drives goes inert and silent. An unguarded
read assumes the key. An absent one draws empty or throws, and that read is the gate `data_check`'s
to fail. The analysis is `data_check`'s own, and a key reads the same here and at the gate.

| template | guarded keys (inert when absent) | unguarded keys (the gate's to fail) |
|---|---|---|
| block | none | bytes, constants, fields, height, values, windowShares |
| chart | blurb, kind, title | series, xLabel |
| earth | none | chi, days, hours, intervals, null95, p, regions, total |
| orrery | found, settings | attenuation, bodies, curve, mode, profiles, span |
| pairs | none | digest, frames, pairs |
| room | clock, core, schema, settings, sources | shell, source, things |
| scope | none | height, id, nonce, rounds, sigma0, sigma1, spectrum, spikes, waveform |
| shadow | none | rounds, word |
| sources | order | rounds, sources |
| sphere | settings | grid, null_spectrum, place, profiles, read, sources, spectrum, symbols, tau, title |
| spiral | arms | agreement, points, total, unanimousByChance |
| step | keys | rounds |
| survey | histogram | positions, samples, sensitivity, sumZMillionths, words, worstAt |
| voxel | depthLabel, noteTitle, settings, title, valueLabel | blurb, depth, fields, note |

## The controls that go inert when a page does build

Cross the two tables above: a guarded template key that a builder's payload omits is a control that
is present and dead once that builder's page builds.

| builder and template | guarded key omitted | the control it leaves inert |
|---|---|---|
| build_field_view into voxel | noteTitle | the note's own heading |

Every other builder carries each guarded key that drives a control, the two sphere builders among
them: both supply the sphere template's `settings`, and `build_sources_view` supplies the sources
template's `order`. `build_room_view` and `build_sha_room_view` omit the room template's `clock` and
`sources`, and neither omission leaves a control dead. The page hides the clock panel without `clock`,
and `sources` drives no control. The row above is the only control left inert.

## Next

The shared control bar follows, designed from this survey. The WGSL raster arm is M16's unbuilt leg,
held to the same byte-for-byte contract as the device and host arms once it is built.
