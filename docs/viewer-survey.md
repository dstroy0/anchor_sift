# The room viewer, measured before it is split

The case for modularizing the room viewer, as counts instead of impressions, together with the
argument for what has to exist before the split and the measurement that changed my own answer.

Everything below is from `tools/view/room_view_template.html` and the builders that share it.

## What the file is

| | room | voxel | sphere |
|---|---|---|---|
| lines | 4511 | 2130 | 774 |
| size | 211 KB | 86 KB | 29 KB |
| script tags | 2 | 2 | 2 |
| of those, modules | 0 | 0 | 0 |
| top-level declarations | 355 | 0 | 50 |
| top-level functions | 102 | 0 | 24 |
| duplicate top-level names | 0 | 0 | 0 |
| banner-marked sections | 38 | 0 | 16 |
| frame-loop sites | 3 | 4 | 3 |

No script carries `type="module"`, so every declaration at the top of the room viewer's script is a
property of one hoisted scope, and any of the 355 is reachable from any of the 102 functions.
Nothing there is private, so nothing is known to be safe to move.

Two numbers say the split is not a rewrite. The duplicate count is zero, so no name has to be
renamed to make modules possible. And 38 banner-marked sections already name the decomposition in
comments: the boundaries, the engine arms, the beam and what it scatters from, the operation clock,
the boundary reconstruction, the panels, the callouts, the redraw. Whoever wrote those wrote the
module list.

**A number in an earlier version of this page was wrong.** It read 750 top-level declarations and
144 duplicate names. The pattern allowed six spaces of indentation and was counting declarations
inside functions, and the duplicates were nested scopes doing their job. Counting at column zero
inside the script body gives 355 and zero. The corrected figures are the ones above.

## What has to exist before the split

**A frame-loop checker, and it is not enough on its own.** A split of 355 declarations across 38
sections is likelier to drop a value than to stop the loop. A checker answering *did it die* passes
a page whose loop turns over data it no longer has.

**The first one manufactured the failure it reported, and that sharpens the argument instead of
weakening it.** The watchdog advanced its turn counter from `requestAnimationFrame` and ran its
check on `setTimeout`. A background tab stops the first and not the second, and a page opened in a
tab that was not visible therefore completed one turn and was declared dead on schedule. The report then
latched: the failure set a flag and the guarded turn opened by returning on that flag, so the loop
never ran again even once the tab came forward. What Douglas saw was a frozen viewer with a red
banner, frozen by its own watchdog.

It was repaired in the room template and the compact copies: a thrown error is fatal, slowness
reports once and stops nothing, a hidden document is not judged at all and re-arms on
`visibilitychange`, and a loop reaching two turns withdraws a warning raised while it was hidden.

So the precondition is not *a* frame-loop checker. It is one that has been run against a page it
should pass, in the conditions a reader will actually open it in, because a split inheriting this
watchdog would have inherited a checker that reports a failure it caused. That is the same shape as
the letter and the topology in `docs/arm-records.md`: the quantity reported was not the quantity
intended, and a cheap counting check settles which is in hand.

The engine proved that at cost: `build_sha_room_view.py` supplies no `clock` key, the page parsed
cleanly, the loop was watched and running, the server returned 200, and the viewer's clock controls
did nothing. Every gate in the tree passed it.

**The second checker is harder than it looks, and this is the part worth reading before writing
it.** The obvious form scans the template for every `DATA.<key>` read and fails a build whose
payload lacks one. Run over the current tree that reports three builders, and at least one of the
three is correct as written.

| builder | template | keys the payload lacks |
|---|---|---|
| `build_room_view.py` | room | `clock`, `sources` |
| `build_sha_room_view.py` | room | `clock`, `sources` |
| `build_field_view.py` | voxel | `noteTitle` |

Every read of both room keys is guarded. `DATA.clock` appears as `if (DATA.clock && ...)`, as
`DATA.clock ? DATA.clock.hold : 0.62`, as `var CLOCK = DATA.clock || null`, and `DATA.sources`
appears once as `Math.min(12, DATA.sources || 2)`. A room built without a clock is a supported mode
and the fallbacks are deliberate.

So key presence is neither necessary nor sufficient. Not necessary, because a guarded optional key
may be absent by design. Not sufficient, because the failure that actually happened was not a
missing reference: the guards worked, the defaults applied, and what shipped was a live page with
inert controls. A checker built on presence alone would have flagged `build_room_view.py`, which is
fine, and it would still need an argument for why the same absence is a defect in the builder beside
it.

The check that catches the real failure is a different one: for each builder and template pair,
report which optional features end up inert, so that a build states *this page has no clock* out
loud instead of shipping a dead control. That is a report, not a gate, and it fails only where a
feature the builder's own name promises comes out inert.

The three rows above are candidates and not verdicts. They were found by matching payload keys as
string literals in the builder source, and a key supplied through a variable would read as missing.
`build_room_view.py` and `build_sha_room_view.py` were opened and confirmed: both pack exactly
`shell`, `core`, `source`, `things` and `settings`.

## What the split kills first

`OCT_SIGNS` is a hardcoded two-by-two-by-two sign loop carrying the comment *the arms are fixed*.
That comment is now false. `docs/arm-records.md` defines an arm as a weight function over the
placement and an arm set as a matrix whose rank is what the reading carries, and the eight sign
octants are one instance of that with rank 8, blind in 248 of 256 directions. The loop asserts they
are the only instance. That one is the engine's, tied to T12 in the transform table.

## Vectorizing

Not surveyed here, and it should follow the split instead of leading it. The reason is the same as
above: a vectorized inner loop that drops a term is a picture that still draws, and no checker in
this tree reads a picture.

## Ownership

The survey and the correction to its own declaration count are this document's. The failing page,
the frame-loop checker and the second checker are the engine's. The request to modularize and
vectorize is Douglas's.
