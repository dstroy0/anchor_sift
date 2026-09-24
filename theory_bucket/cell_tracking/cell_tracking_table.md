# The cell tracking table

**Purpose:** The micro n-body problem cell_tracking exists to solve, part by part. For each part: the physics we hold it to, what the program does about it today, what it wants to do, every hypothesis tried there with its result, and the next move.
**Scope:** the program: `cell_tracking/src/`, the rules in `cell_tracking/base.cfg`, the cell-specific modules still under `engine/` until they move (`bodies`, `score_sample`, `answer_key`, `measure/*`, `group_objects`, `link_objects`, `relate_frames`), the physics in `theory/thought_experiments/` (the harmonics source above all), and the numbers in [ledger.md](ledger.md). The machine the program runs on is a separate concern with its own table, [engine_table.md](engine_table.md); a row here names the machine rows (M1 to M12) it reads. Statuses follow [README.md](README.md). A hypothesis with no run in the ledger says so.

## Two tables, two concerns

The engine is the machine: exact arithmetic, the residual operator, the component tree, the moments, the one correlation operator, the marginal, the record machine, the files. The program is cell tracking: what a cell is, which body it is next frame, when it divides or dies. Each table is optimized on its own terms. They are optimized against each other only through the interface at the end of each table (what this program asks of the engine, what the engine offers). Merged, neither can be optimized on its own (Doug, 23 September). A second program, RSNA knee MRI, now runs on the same engine, and for that reason the machine must stay free of cells.

## The problem

A developing zebrafish tissue is an n-body system: cells are the bodies, suspended in a fluid medium, touching and adhering through their membranes, moving, dividing, dying, entering and leaving the volume. We see it only as 100 frames of a 64×256×256 volume, with each sample's own deterministic noise on top. From that we must recover every body, its state, its motion, which body it is in the next frame, and its lineage. Everything must be exact, and no number may be chosen.

The score pays for three things: nodes matched to key nodes within 7 µm, edges between matched nodes, and divisions (0.1 of the score). Every row below is judged by what it moves on that score.

## The table

| part | the physics we hold it to | does today | wants | tried, and what it gave | status | next |
|---|---|---|---|---|---|---|
| **1. The bodies** | A body is what stands above the medium, whole; the field carves its boundary, and no gradient is tuned. | The program takes the machine's component tree (M3) and one cut: the level with the most components, proved against the forest's count. `grow_leaves` makes the leaves. `group_objects` joins leaves into objects by touch in one frame, transitively; on today's bodies nothing touches; every object is one body (row 6). Since the split (23 September), the slide and the overlap are machine operators over probes and probe links (M3). The program turns key cells and divisions into probes and links and grades the census itself, in `cell_tracking/src/slide/slide_score.cu`. That file is rewritten to the probe interface and is **not yet compiled or hooked in**: it hooks into score_sample's frame loop, and score_sample has to move to cell_tracking first. | One node per cell. 44b6 is estimated at about 260 cells a frame and 6bba at about 700; the tree gives far more pieces. | Every node: **measured**, 5.8 M nodes against 880,906 estimated, score 0.279. The 400 largest a frame: **measured**, 0.661 on the 25 44b6. `stands`: **measured**, 0.12 on the older dump (38,114 nodes kept). `merge_split`: on by default, no A/B. `dish`, `cohere`, `accrue`, `agree`: no run in the ledger. The slide (`--slide`, 23 September, before the split), **measured**. Every level where the key cells' sharing changes is found by bisection over the levels. Each probe's component count is proved against the tree's count at that level: 0 of 26,454 differ. On 6bba_48816121, the cut holds 931 of 935 key cells, and 50 are alone on their leaf. At each frame's best single level, 903 are alone; at some level of their own chain, 925. The most-components level sits low in the tree: many small pieces, with the cells merged into a few giant blobs. Frame 0: the cut is at level 84,314 of 1,135,213; all 4 key cells are alone from 1,045,988 (204 components) down to 463,871. The overlap at the same residual (`--overlap`, 23 September), **measured**. Frames t and t+1 are cut at the same exact residual r. At the drift, each component's distinct partners are counted from the exact (earlier root, later root) pairs; mutual is the AND, both ends with exactly one. The sampled r values are each frame's key-partition events and its cut. On 6bba_48816121 (99 pairs, 3,615 cuts), the earlier frame's cut has 61,679 components, of which 15,979 overlap exactly one and 6,688 are mutual (11%). The best mutual over each pair's cuts sums to 13,783. Mutual peaks high in the tree, at 150 to 200 components a frame with 70–80% of them mutual. Frame 0→1 at level 1,045,988: 204 components and 144 mutual; at the cut: 329 and 29. On 44b6_0113de3b, the cut has 39,507 components and 7,962 mutual (20%). The event census (23 September), **measured**. It classes every component: 1→1 move, 1→2, 2→1, 1→0 and 0→1. Mutual counted from either side agrees on every cut. On 6bba_48816121 at the cut, about 70% of the components have no partner at all. Of the key's 5 divisions, 0 are parted at the most-components cut. At each pair's best sampled cut, 5 are present, 3 have their daughters apart, 2 are parted (the parent's component overlaps both daughters' components) and 1 is caught as 1→2. Daughters separate only where the parent is gone, and one global drift misses daughters that move apart. Key cells per leaf (`--box-history`, 23 September), **measured**. On 6bba_48816121, 881 of the 931 key nodes that land on a leaf share it with another key node, on 110 leaves. Up to 13 key cells sit on one leaf of 779,789 voxels, and every key division's parent sits on a leaf of 652,575 to 1,004,159 voxels whose box is the whole 64×256×256 view. On 44b6_0113de3b, 0 of 52 share. So ℓ* cuts 6bba into a few giant components that hold many cells each. The 6bba edge scores (856/918 on this sample) count leaf-to-leaf links, and most of those leaves hold many cells; they are not per-cell tracking. | built; the node count is the score's lever; on 6bba the cut holds many cells a leaf | Bodies, not pieces, as the nodes: row 2's fingerprint and row 9's entropy decide membership. Hook `slide_score.cu` in once score_sample moves. The machine's LCA identity (M3, theory) gives every level where two key cells part without bisection: one query per neighboring pair of key cells. |
| **2. Each body's intrinsic state: its spherical harmonics** | Every body has unique harmonics because of intrinsic physical differences (mass density, membrane elasticity, aspect ratio). Cells are oblate; ℓ = 1 (dipole) and ℓ = 2 (quadrupole) dominate. Up to ℓ = 2 the harmonics carry exactly what the moments carry: ℓ = 0 the mass, ℓ = 1 the index sums, ℓ = 2 the six second moments. | The machine accumulates every body's exact moments (M4). `grow` carries them to `TreeFrame.sums` and `.moments`. `coherence` exports them to the viewer. The print (`fingerprint_program`, 52 steps) writes each body's ℓ ≤ 2 fingerprint as a record: the mass band and six signed golden bands of K′/m², K′ = sₐs_b(m·M − SₐS_b) scaled by `voxel_pm` over its common unit. `print_pair` weighs two prints against each other. **The linker (E8 in the equation below) does not read the print yet.** The sums are also read by `parallax`, `arc` (`track_bend`), `velocity`, `division` and the export. | The print in the linker's pool, to tell a cell from its neighbor. ℓ > 2 needs the body's surface: theory. Oblate spheroidal harmonics in place of spherical: theory. | The print: **measured**, 81,807 bodies of 44b6_0113de3b in 11.7 ms, CRC-64 `590f3a2c386647e3` twice, 0 differ from the host. Linking by it: see row 7 (`--print-match`). | built, read only by `--print-match` | Put the print into E8's pool: waits on Doug (build plan, Waiting on Doug 3). |
| **3. The medium: the fluid the bodies sit in** | The wide term is the medium's scattering, its turbidity, the fluid's mean entropic flux. It is noise to us and is subtracted whole, in exact two's complement; the medium resolves to zero (phase cancellation). | The program hands the machine's residual (M2) one smooth order and one background order per axis, {2, 34, 34} and {6, 96, 96} (`SMOOTH_ORDERS`, `BACKGROUND_ORDERS`, track.h). **They are a debt** (23 September): they came from `n = 4(σ/v)²` rounded to even, with two chosen scales, σ = 6/5 µm (smooth) and 2 µm (background) (`for_anchor_sift/stripped/src/exact_track.py`). The rounding and the chosen σ both break the rules. | Orders read from the data, per sample, with nothing rounded. Doug's rulings, 23 September: the per-axis coherence reading gives an exact integer period P in voxel steps, and **order = period** (n = P). Flatten takes a smooth and background pair per sample (not built). The medium's physics now has an exact form (M2's heat identity): the residual is 4^m times what m explicit heat steps of the medium remove from the smoothed field; "the medium's mean entropic flux" is literally the subtracted term. | The key against the passes, and the unit sweeps: see M2 (proved exact; the sweeps 2× faster). | orders chosen and rounded (debt) | Build the per-axis coherence reading (machine, M2's next), then orders per sample. Whether the tracker runs the unit sweeps by default (`--unit-sweep`) is Doug's call. |
| **4. Microfluidics: the medium's flow** | The field moves as a whole (drift) and each body moves on top of it; the whole moves first. Mitosis and lysis change the fluidics for a great distance around them: a division or a lysis sends a hydrodynamic disturbance through the surrounding tissue. Oblate bodies shed predictable dipole waves when they deform, snap or throw out a pseudopod. | Bulk drift only: the machine's drift (M5, `shift_agreement`) gives the one lag that best carries this frame's set bits onto the next frame's, `lag_to_next` (the demon's eyes). Nothing reads a local flow, a disturbance or a wave. | The disturbance field around each event read from the residual; an event far off is felt where it arrives. Overlapping disturbances untangled by their harmonic coefficients, each traced back to its origin, retrograde. | `motion_check` (drift run twice, every count compared): built, no disagreement recorded. `keep_view` (no drift removed): no run in the ledger. | drift built; flow theory | Build plan C3: each body's departure from the drift (v*_b − d_t), summed over its contacts and weighted by mass, then traced back toward the division and lysis events it came from. |
| **5. Each body's motion** | A body's velocity is the time derivative of its dipole. Its next place is predicted from that before any overlap is counted, and the dipole axis points back to where the motion started: v_origin = −∇(∂C₁ₘ/∂t). | The climb (M5, `climb_machine`): each body climbs from the drift to its own lag, one step in 26 directions at a time, by how many of its voxels agree, until no step helps. `--velocity` writes the dipole's change per body as a record beside the climb (see the verdicts). **`EngineBody.velocity` exists and nothing writes it; the linker does not read the velocity record.** | Velocity from the dipole's change across frames, used to predict each landing, and checked against the climb. | `sticky`, `mass` (land where most of the body lands), `spiral` (golden spiral offsets beyond the climbed lag), `arms` (the same climb at gaps 2 to n; bodies too close one frame on have parted later): all built, no run in the ledger. `--velocity` (the `velocity` record program): the dipole's change is written per body as an exact rational, (S′m − Sm′)/(m·m′) per axis, beside a truthy verdict that the climbed lag stands on a lattice point next to it. **Measured** on 44b6_0113de3b, device equal to the host on every lane: of 35,755 bodies with a climbed forward, the climb and the dipole agree on all three axes for 8,720 (z 22,660, y 13,227, x 13,306); the last change predicts the next climb for 752 of 35,966. On 6bba_48816121, 6bba_09961292 and 6bba_cdcfe533, **measured**: the check agrees on all axes for 2,144 of 21,366, 22,027 of 60,714 and 5,466 of 29,252; the prediction for 201 of 21,724, 2,666 of 58,840 and 497 of 28,743; 0 differ from the host. | climb built; dipole velocity built and measured on four samples | The leaves are pieces (818 a frame against about 260 cells); a piece's dipole moves with the cut, not the cell: measure the same on bodies, and on the 25. |
| **6. Protein interactions: contact and adhesion** | Cells touch and adhere through membrane proteins; bodies in contact move together and pull on each other. The membrane is a scale of the problem (`membrane_pm`, 4 nm, the bilayer's thickness). | **No two bodies touch on today's engine** (corrected 23 September). The bodies are the separate components of the cut at ℓ*, and two components cannot share a face without being one. So `grow_leaves` holds no touching pairs (`joined_count` = 0), and `group_objects`, `sticky`, `web` and `--contact-side` have nothing to read. The joined leaf pairs came from the older basin engine. The volume faces each body touches (`touches`) are recorded. `voxel_pm` is read by the print, `division` and `contact_side`. `membrane_pm` and `species` are read into the `.cfg` and written back out, **with no reader**. | Contact as a force-free constraint: bodies adhered in one frame stay adhered unless the data parts them. The membrane scale in place of any voxel count. Membership never by touch alone (row 9). | `sticky`, `web`: built, no run in the ledger. Grouping by touch: **measured** on the older basin engine to chain up to 2,256 pieces into one object at the widest; on today's engine every object is one body. `--contact-side` on 44b6_0113de3b and three 6bba: **measured**, 0 touching pairs on every sample, because there are none. | contacts not held on today's bodies; adhesion theory | What "touching" is for components of a cut is Doug's to define: for example, the component tree's next level down, where two bodies first join, or a gap of the membrane's width. The tree gives the first of these exactly: two bodies first join at the level of their LCA (M3). Until then the no-crossing verdict (built, `--contact-side`) has no pairs. B3's deformation waits on C1: the membrane deforms; a body and its match overlap only in part. What stays inside the match under every jitter is the body's internal constituents, and their shift is the velocity and vector. |
| **7. Correspondence: which body it is next frame** | Identity is the limit of coherence: a body is who it is because its coherence carries on, not because of a tag. One-to-one where bodies are one-to-one. | The overlap triples (M5, `body_overlap`) count shared positive voxels per pair at the drift. `pick` keeps the branch sharing the most, `unbound` takes the nearest center by the swept vector (the jitter step it meets at over its magnitude), and `resolve` rejoins reconverging branches by union-find. The machine's one-to-one matching (M7, `heaviest_matching`) is wired in by `--print-match`: the `print_pair` record program weighs every candidate (the overlap triples and the climbed forward) by how far its seven-band print lies from the body's, and the heaviest one-to-one set rewrites the forwards. `--marginal` writes each body's exact context-aware probability P(b → b′ \| G) = Z_{b→b′}/Z over its local set, with the machine's marginal (M6) and the program's weights (see the verdicts). It reads the triples and the null, and the linker does not read it yet. **Measured** (internal count): 98.4% of 6,358 edges on the 25 44b6, 97.0% of 3,873 on five 6bba. | Link each body to the one whose fingerprint agrees (row 2), one-to-one by `heaviest_matching` on fingerprint cost. | Under the metric: **measured**, 87.1% hit on 44b6 (10.9% land on a neighbor, 5.75 µm) and 78.5% on 6bba (19.6%, 6.7 µm). `--print-match` on 44b6_0113de3b: **measured**, 56,927 pairs swept at once in 217 to 245 us, 31,130 of 80,697 leaves matched one to one, 19,113 forwards changed, edges unchanged at 38/12 of 50, because base.cfg's `unbound` linker picks by overlap weight and center cost and reads the forward only as one more candidate. `--marginal` on 44b6_0113de3b (with the floor's null): **measured**, 34,297 bodies asked in 50 to 58 ms (30,444 in their context, 3,853 alone, 8 too wide), 123,538 options, device equal to the host. Of 49 key edges asked, the most probable in context is the truth for 16 and "no link" for 27. The heaviest candidate alone is the truth for 38, and the climb's forward for 35. Where a target wins, it is the truth 16 times of 22. The null's weight dominates: it is the null climb's held count, which the climb maximizes, while T is counted at the drift. Putting the two on one footing is Doug's to set. With Doug's transform (`--box --marginal`, the links weighed by T*, C at each body's own climbed lag): **measured**, 51,214 bodies asked in 240 ms, 195,658 options, device equal to the host. Of 49 key edges, the most probable in context is the truth for 19 and "no link" for 24; the heaviest candidate alone gets 37 and the climb's forward 35. "No link" is weighed by the best of the floor's null draws (max_k h⁰_k). Whether "the null draw's fraction" means the best draw, each draw as its own outcome, or something else is Doug's. No run in the ledger for `share`, `cast`, `parallax`, `arc`, `settle`, `damp`, `vote`, `mutual`, `forest`, `merge_target`, `forward_only`, `focus` or `tower`. | built; losses are neighbors | Row 2's test. The marginal's local set G is one hop today (the sources competing for b's candidates, and their candidates). M6's factorization says the exact marginal over the whole frame equals the marginal over b's connected component of the support graph, and over nothing smaller: take G as that component, and the probability is the global one exactly (theory). |
| **8. The null: is a correspondence real** | A null is the field-noise reading, not an empty return: the same body climbed toward a frame where no correspondence can exist. A body is real where it stands above that reading. The arm is fired where the observer's cloud is densest, not swept. | Null draws (`--null`), held against each body's own climb in the edge and node rows. With a floor laid down, there is one draw per floor on the identity line (frame `g·11 + f mod 11`), ordered by the window-overlap cloud (M8), least overlap first. `--marginal` weighs each body's "no link" by its best null draw. | Nodes kept only where they stand above their null (`above_null` in `maint/score_submission.py`). | Aimed against swept, same samples and same count: to be measured. `above_null` on the current engine, **measured** 23 September on the two samples with a floor (`--null 1 --run floor`, `maint/score_submission.py`'s scorer: nodes matched by position within 7 µm, the score's node-count factor). 44b6_0113de3b: all 81,807 nodes 0.027942 (edge jaccard 0.036, 2 of 50 key edges), `stands` 277 nodes 0, `above_null` 7,890 nodes 0.039606 (jaccard 0.037). 6bba_48816121: all 62,650 nodes 0.002323, `stands` 123 nodes 0, `above_null` 1,012 nodes 0.001149. The tracker's own tally, by leaf identity, calls 38 of 44b6_0113de3b's 50 key edges correct, where the position-matched scorer finds 2. The two measures disagree, and the submission is graded by position. Edge by edge on 44b6_0113de3b: 11 of the 100 key-node ends have a centroid within 7 µm. The rest are 7 to 15 µm from the nearest one, because the key cell's leaf is a multi-cell blob (up to 24,481 voxels, about 3,000 for one cell) or a piece (3 to 357 voxels). The loss is the cut (row 1), not the link. | built | Run both on the 25: it is a node-count lever with no chosen number. |
| **9. Division: mitosis** | A split is a boundary discontinuity, judged over the whole sample and not the moment. One body's fingerprint becomes two whose masses add to it and whose dipoles part along the parent's quadrupole axis. The local entropy bumps and settles into two lows. | `assign_bodies` (only when node rows are asked for) marks a body SPLIT when nothing lands on it and its back landing is a body that went elsewhere, and gives it that body's id as parent. `--division` writes the mass and axis verdicts for every parent and two pieces whose backward climbs land on it (the `division` record, 100 steps). `assign_bodies` does not read them yet, and there is no entropy check. | Two linked children confirmed by mass conservation, the parent's ℓ = 2 axis, and an entropy bump that settles. | Divisions matched: **measured**, 0 on the older dump. The division term earns 0 today. `--division` on 44b6_0113de3b: **measured**, 142,649 triples in 13.8 ms, mass conserved on 3,356, split along the long axis on 99,155, both on 2,452, 0 differ from the host. That sample's key holds no division. Of the 199 keys, 87 hold any, at most 5 (6bba_48816121). On 6bba_48816121, 6bba_09961292 and 6bba_cdcfe533: **measured**, 326,836, 85,146 and 99,724 triples, each in 1 to 3 ms, 0 differ from the host. The keys hold 13 divisions. Only 3 put the parent and both children on three separate leaves, and 2 of those are among the triples. Mass holds on 1 of the 2, the axis on 2, both on 1. Why the rest are lost, **measured**: 10 of the 13 have both children on one leaf. One frame after the split, the cut at ℓ* has not separated the daughters. On 6bba_48816121 (`--box-history`), the parent and daughters of all 5 of its divisions are on leaves of 0.65 to 1.0 M voxels whose box is the whole view (row 1). None has a node off every leaf, and none falls outside consecutive tracked frames. On the 3 with three separate leaves, 4 of the 6 children climb back to their parent. So the loss is the cut (row 1), not the climb. | fate built; mass and axis verdicts built and measured | The daughters inside one leaf are likely separate components higher in the same component tree. One cut level for the whole frame cannot hold both a just-divided pair and everything else. That is row 1's selection (Ultrack's one node per nested chain; build plan, Waiting on Doug 5). The census's 1→2 class (M3) is the set of sources a division arrangement would add to the marginal (row 7). Then build plan C2 (the entropy bump). |
| **10. Death: lysis** | An uncontained dissipation: the entropy bump rises into the floor and does not settle, and the body bleeds into the background. | `assign_bodies` marks VANISHED (nothing onward, not at a face), ABSORBED (landed in a body another carried) and MERGED. Nothing tells a lysis from a missed detection. | A lysis told from a vanishing by its bump rising into the floor. | The box history (C2's measurement): **proved** on 44b6_0113de3b (81,807 boxes × 9 windows × 16 bits, 0 of 11,780,208 differ from walking every box, 5.4 s) and 6bba_48816121 (0 of 9,021,600, 6.3 s). Every key division's parent on 6bba_48816121 sits on a leaf whose box is the whole view (row 1); its history is the view's, and a bump cannot be read there. | measured, no verdict | Build plan C2. `--box-history` holds each body's box (`climb_machine_extents`) and gathers its flips per window and bit from one running-sum key a window and bit, by 8 corners. The verdict (a bump that rises and settles, or rises and stays) waits on row 1's cut and on Doug: which bits, and how the windows (11 transitions) meet a one-frame event. |
| **11. Entering and leaving the volume** | Bodies cross the volume's faces; a body that appears at a face entered, one that disappears at a face left. | ENTERED and LEFT from `touches` (the volume faces a body meets). | Nothing further now. | none | built | none |
| **12. The noise floor: what is not a body** | The noise is deterministic, constant and unique per sample: shot, thermal and read, fixed pattern, quantization. It is read, never modeled. Entropy separates it: what decays to maximum entropy is floor −4, and what holds low and moves is a body. | The machine's entropy history (M8) with its window-overlap cloud; the `.cfg`'s `floor` lays it down first. | Every departure from the floor placed; only those places are asked about (the demon's waveform collapsing onto U \| U). The four noise keys imprinted and stamped over the set in one cycle. | Anchors: **measured**, bits 0 to 4 in about 46% of frames everywhere, anchors in bits 6 to 11, none common to every sample. History: **measured**, bits 0 to 3 at 499 to 500 per mille in 19 of 25. A constant region in 6 samples: measured, cause unknown. Direction: measured, each sample's own. | measured | Build plan C4 (waits on Doug's design), then membership by entropic direction (rows 1, 9, 10). |
| **13. A body's edge** | The edge is what stays with the body under every jitter of the view; what falls in and out is the floor at its boundary, set aside and not averaged. | The jitter sweep (`LINK_SWEEP_STEPS`, a box a voxel wide doubling out past the view) exists and is used only to score a link's disagreement. The jitter core (M5, `climb_machine_core`, `--core`) is built and measured. | Every boundary voxel scrubbed under the sweep; a body's edge and mass are its own and not one frame's cut. | The core per width on 44b6_0113de3b, **measured**. Proof: the width-0 core mass equals C at the climbed lag on 35,755 of 35,755 forward climbers. Of 161,708 climbers (both sides, adjacent frames), 72,186 reach width 0, 33,827 width 1, 22,884 width 2, 10,230 width 3, 606 width 4 and 2 width 5. Core mass is 90,205,526 / 36,098,925 / 6,542,528 / 307,434 / 4,956 / 2. Which axis ends each core is not yet measured. Mutual pairs whose core displacement lies within half a voxel of the climbed lag on every axis: 10,003 of 16,176 at w=0, 4,409/10,410 at w=1, 2,578/8,727 at w=2, 456/3,413 at w=3, 15/117 at w=4. The deeper the core, the less its motion is the lag's. 49.6 s, with D3 sharing the GPU. | core built and measured | Build plan C1 (Doug, 22 September: every width, kept per width, between frames): a voxel of a body stays at width w when every offset in the box of half-width w around the climbed lag lands it inside the match. Mass, sums and moments re-summed per width; the print is summed over the edge that stays. |
| **14. Size: growth and division by ratio** | Sizes spread on a golden ladder, since growth and division scale by ratios. | The machine's golden ladder (M11, `band_of`), read by `damp`, by `group_objects`, by the residual survey, by the print and by `division` (mass conserved is β(m_c + m_s) = β(m_p)). `--mass-band` (`band_or_count`) compares the bands instead of the counts wherever two sizes are compared: `group_objects`, `arm_landing`, `focus_links`, `assign_bodies` and `track_bend`. Exact sums stay counts, since a band there would round (Doug, 22 September). | A size read on the ladder instead of any count. | `damp`: no run in the ledger. `--mass-band`, D3 on the first 25 (23 September): identical to counts on every one of the 24 that ran both sides, with 6,134 edges and 5,176 correct / 227 wrong / 2 none / 729 missed. It is identical by construction: on the scored path every reader is gated off. `track_bend`, `arm_landing` and the scorer's member choice compare within one object's members, and every object is one leaf. `group_objects` needs joined pairs, and there are 0. `focus_links` needs `--focus`; `assign_bodies` needs nodes output. The 25th, 44b6_551a5dba, loaded in the counts run and then failed its .kcr CRC in the bands run and on every read since, with the file's mtime unchanged (for Doug). | built, inert | Live only once objects hold more than one leaf, or once bodies touch (row 6). |
| **15. The whole state, once** | The field's state is a set of bodies at every time, and one exact file holds all of it. | The machine holds the field (M9: `.kcr`, `.knf`, `flatten`, `.kcs`). No file holds the bodies' fingerprints. | A file kind for the bodies and their ℓ ≤ 2 fingerprints, written once; linking reads bodies and not voxels. | See M9. | field held by the machine; bodies' prints not held | With row 2. |

## The tracker's equation

The tracker, written out as the one function it computes, stage by stage, from the code as it runs under `cell_tracking/base.cfg` (`pick`, `unbound`, `merge_split`, `resolve`, `climb: machine`). Every quantity is an exact integer unless a line says otherwise. Each stage names the code, and the machine operator it reads (M-rows and A-sections of [engine_table.md](engine_table.md)); the algebra can be worked on the formula and checked against the code.

### Notation

- t is a frame, x = (z, y, x) a voxel of the view Ω = [0, D) × [0, H) × [0, W), and I_t(x) the frame's 16-bit reading.
- w = (w_z, w_y, w_x) = (16, 1, 1) are the axis weights (`AXIS_WEIGHTS`, track.h). ‖v‖²_w = 16v_z² + v_y² + v_x². They equal σ∘σ, with σ = voxel_pm / gcd(voxel_pm) = (1,625,000, 406,250, 406,250) / 406,250 = (4, 1, 1), the same σ `contact_side` and the print already scale by (see the low fruit below).
- [·] is 1 when its statement holds and 0 otherwise.
- β(n) is n's rung on the golden ladder (A-section A9).

### E1. The residual (row 3): the machine's A1

  R_t = 2^g · (B_s ∗ I_t) − B_b ∗ (B_s ∗ I_t), with the program's orders s and b (row 3's debt). The positive set is P_t(x) = [R_t(x) > 0].

### E2. The bodies (row 1): the machine's A2 and A3, then `grow_leaves`

- The cut is ℓ*_t = min { ℓ : C_t(ℓ) = max C_t }, the lowest level with the most components (A2). The choice of one level for the whole frame is the program's.
- The bodies B_t are the components at ℓ*_t, with mass m_b, index sums S_b, second moments M_b, peak p_b and touches (A3). The centroid is carried as the pair (S_b, m_b) and never divided.

### E3. The drift (row 4): A4, `shift_agreement`

  d_t = argmax_v Σ_x P_t(x) · P_{t+1}(x + v)

### E4. The climb (row 5): A4, `climb_machine`

For each body b of frame t, A_b(v) = Σ_{x∈b} P_{t+1}(x + v). The climb starts at v₀ = d_t, steps to the neighbor u (26 of them) with the largest A_b(u) while A_b(u) > A_b(v_k), ties to the least ‖u‖²_w, and stops at v*_b.

- The forward is f(b) = L_{t+1}(p_b + v*_b), the body of t+1 under the peak, or none.
- The climb's held score is h(b) = A_b(v*_b).
- The backward runs the same from t+1 to t, starting at −d_t, and gives back(b′) and its lag v*_{b′}.

### E5. The null (row 8): the same climb toward a frame where no correspondence exists

  h⁰_k(b) = A_b^{(t → t_k)}(v*),  one draw k per floor on the identity line when a floor is laid down

### E6. The overlap triples (row 7): A4, `body_overlap`

  T(b, b′) = |{ x : L_t(x) = b, L_{t+1}(x + d_t) = b′ }|,  kept where T > 0

### E7. The objects (row 6): `group_objects` (`merge_split`)

  b ~ b′ ⇔ b, b′ touch ∧ ( O_{t−1}(back(b)) = O_{t−1}(back(b′)) ∨ f(b) = f(b′) ≠ none )

The objects O_t are the transitive closure of ~, one frame after another. **On today's bodies, E7 changes nothing**: two components of one cut cannot share a face; `grow_leaves` writes no touching pairs and every object is one body ("largest 1" on every run).

### E8. The link (row 7): `link_objects_unbound`

For an object O of t and each object Q of t+1 that O's triples or forwards reach:

  W(O, Q) = Σ_{b∈O} Σ_{b′∈Q} T(b, b′)

A forward that reaches Q enters the pool with weight 0.

  κ(b, b′) = min over the four pairings (lag or lead) of  ( s ≪ 40 ) | ( Σ_a w_a (ℓ_a + ℓ′_a)²  mod 2⁴⁰ )

- ℓ is b's forward lag and ℓ′ is b′'s backward lag; ℓ + ℓ′ is how far the round trip misses.
- s = min { j ≤ 12 : 2^j ≥ max_a |ℓ_a + ℓ′_a| } is the jitter step it meets at.
- K(O, Q) is the least κ over the member pairs that reach Q.

  Links(O) = { Q : W(O, Q) = max_Q′ W(O, Q′) ∧ K(O, Q) = min over those Q of K }

The link is the heaviest overlap. The round-trip cost only breaks ties.

### E9. Reconvergence (row 7): `resolve`

When O has two links whose single-link chains meet again at one node, every pair of nodes along the two chains is joined (union-find). The nodes are the classes that result.

### E10. Fate (rows 9 to 11): `assign_bodies`

- SPLIT: nothing lands on the body, and its back landing is a body that went elsewhere. That body becomes its parent.
- VANISHED, ABSORBED, MERGED, ENTERED and LEFT come from the landings and `touches`.

### The verdicts built beside the path (records on the machine's record engine, M10; truthy: zero false, nonzero true; AND is a product, OR a sum)

These are written for every body, pair or triple in one sweep each, device equal to the host. **They do not enter E8 yet.**

- **The print** (row 2, `fingerprint`), per body: β(m) and the six signed golden bands of K′ / m², where K′ = s_a s_b (m M − S_a S_b) is scaled by `voxel_pm` over its common unit.
- **The print cost** (row 7, `print_pair`), per pair: the distance between two prints. The ceiling 1,275 is a body against itself.
- **Velocity** (row 5, `velocity`), per body and its forward, and per axis:
  - Δ_a = (S′_a m − S_a m′) / (m m′), held as the pair (numerator, m m′)
  - R_a = L_a · m m′ − (S′_a m − S_a m′)
  - c_a = COMPARE(m m′, |R_a|), and the verdict V_a = c_a (c_a + 1). It is nonzero exactly when |Δ_a − L_a| < 1, the climbed lag standing on a lattice point beside the dipole's change.
  - V = V_z V_y V_x.
- **Division** (row 9, `division`), per parent p and two pieces c, s whose backward climbs land on p:
  - D_mass = 1 − |COMPARE(β(m_c + m_s), β(m_p))|
  - D_axis = [3 Δᵀ K_p Δ ≥ tr(K_p) |Δ|²], where Δ = S_c m_s − S_s m_c
  - D = D_mass · D_axis
- **Contact side** (row 6, `contact_side`, two passes), per touching pair A, B of frame t whose forwards A′, B′ both exist:
  - pass 1: N = σ ∘ (S_A m_B − S_B m_A) per pair, where σ_a = voxel_pm_a / gcd(voxel_pm);
  - pass 2 reads two pass-1 records: dot = N · N′, c = COMPARE(dot + 1, 1) = sign(dot);
  - kept = c (c + 1) and crossed = c (c − 1).

  dot is (c_A − c_B)·(c_A′ − c_B′) in physical space times the positive m_A m_B m_A′ m_B′ / gcd²; its sign is exact. Two membranes cannot pass through one another; a real pair keeps its side. dot = 0 includes A′ = B′, the pair landing on one body.
- **The marginal** (rows 7 and 8), the machine's A5 with the program's weights: ω(b″, b′) = T(b″, b′) (or T*, below) and ω(b″, none) = max_k h⁰_k(b″). P(b → b′ | G) = Z_{b→b′} / Z. Every source's weights share its own mass as denominator; the masses cancel, and Z and every Z_{b→·} are exact integers compared by cross-multiplying, with no temperature, no energy and no calibration. OrganoidTracker 2.0's P(A | G) is the same sum over exp(−E/T) of calibrated network energies.

### The whole, in one line

  Tracks = Resolve( Links( W(T(B(R(I)), d)), K(v*(B, d), v*(B′, −d)) ), Objects(B, f, back) )

This reads from the inside out:
1. the residual R;
2. its bodies B at the cut ℓ*;
3. the drift d between frames;
4. the overlap T at the drift and the climbed lags v*;
5. the objects from touch and shared landings;
6. the link, by the heaviest W and then the least K;
7. the reconverging chains joined.

The records (print, velocity, division, marginal) are functions of the same B, v* and T. How they enter W and K is Doug's to set (Waiting on Doug, item 3, in the build plan).

### The tracker's stages as reads of the machine's one operator (Doug, 23 September: "we are repeating the same operation close to 10 times")

Almost every stage above is the machine's correlation C (A4) followed by a different reduction:

| stage | the read of C |
|---|---|
| E2 moments m, S, M | `C_{t,t}[a, a](0)` weighted by 1, x, x xᵀ |
| E3 drift d | argmax_v Σ_{a,b} `C_{t,t+1}[a, b](v)` |
| E4 climb A_b(v) | Σ_{b′ ∪ ∅} `C_{t,t+1}[b, b′](v)`, climbed to a local maximum v*_b from d |
| E4 landing by mass | argmax_{b′} `C_{t,t+1}[b, b′](v*_b)` |
| the backward climb | the same box transposed: `C_{t+1,t}[b′, b](−v)` = `C_{t,t+1}[b, b′](v)` |
| E5 null h⁰ | Σ_{b′ ∪ ∅} `C_{t,t_k}[b, b′](v*)`, in a null frame |
| E6 overlap T | `C_{t,t+1}[b, b′](d)` |
| the transform T* | `C_{t,t+1}[b, b′](v*_b)`, so Σ_{b′} T* + T*(b, ∅) = h(b) |
| E8 link weight W | Σ over each object's members of T |
| C1 jitter core, every width | S_w[b, b′] = Σ_{‖u‖∞ ≤ w} C_{t,t+1}[b, b′](v*_b + u): nested boxes around v*_b |
| contact κ_w (row 6) | Σ_v (B_w ⋆ B_w)(v) · `C_{t,t}[A, B](v)`: the box's autocorrelation, a tent, over the frame's own box |
| the slide and the census (row 1) | C at pairs of levels, a rectangle sum of the own-node table (A2) |
| velocity, division, print | the moments above, read in pairs and triples |

What it replaces today: the drift computed once (`shift_agreement`, over every v, by an exact NTT); the climb again per body (27 shifts a step); the overlap again at the drift; the landing again (`land_mass`); the null again per draw; the core and contact each another pass; the census again per sampled cut. The machine's box (`--box`) proved the climb, the null and the overlap are reads of the one C (engine table, M5). The window of shifts is the open design choice, and it is the program's to name in its request: the machine holds no scale.

### Doug's transforms, 23 September

- **The null's exact transform.** The link's weight is the climb's own functional split by the target it lands on:

  T*(b, b′) = |{ x ∈ b : P_{t+1}(x + v*_b) ∧ L_{t+1}(x + v*_b) = b′ }|;  Σ_{b′} T*(b, b′) + T*(b, ∅) = A_b(v*_b) = h(b)

  where ∅ is a positive voxel in no body (R > 0 below the cut). In the marginal, ω(b, b′) = T*(b, b′) and ω(b, none) = max_k h⁰_k(b). Both are counts of the same body's voxels under the same operator, and the masses still cancel.
- **Contact** (row 6). Each body has an assigned boundary. At width w, κ_w(A, B) = |{ x : d_A(x) ≤ w ∧ d_B(x) ≤ w }|, where d_A(x) = min_{y∈A} ‖x − y‖∞. It is nonzero exactly where the two boundaries overlap at w: the truthy contact, its size the magnitude.
- **The jitter core** (C1, rows 13 and 6). The match b′ = f(b) has D_{b′}(y) = min_{z∉b′} ‖y − z‖∞. A voxel x of b stays at width w when D_{b′}(x + v*_b) > w. Built and proved: the width-0 core is `C[b, b′](v*_b)`, exactly, on every forward climber of 44b6_0113de3b. The widths end at 5 there; the data sets where they end, and the view bounds them at (shortest extent + 1)/2.
- **The cut** (row 1). ℓ* slides through every level of the component tree, to the top, and each nested chain keeps the node that stays coherent between frames. One level for the whole frame is replaced by one node per chain.

### Low fruit in the tracker's algebra (23 September)

Each item is algebra on the equation above, exact, **theory until built**. What it replaces is named.

1. **One scale vector.** w = σ∘σ with σ = voxel_pm / gcd(voxel_pm): the link's norm (E4, E8), the print's scale and the contact side's σ are the same vector. `AXIS_WEIGHTS` becomes derived, not written in, and any geometry (another microscope, the MRI's 0.3 mm against 3.5 mm) gets its weights exactly: the machine's `decimal_double` (A0) turns a spacing's decimal string into an exact integer, and the gcd makes them coprime integers. Replaces the constant `{16, 1, 1}`.
2. **The marginal over the component.** The exact frame-wide marginal factors over the connected components of the support graph (A5). b's probability is exact when G is b's whole component, and today's one-hop G is exact only when the component is one hop wide. Replaces the one-hop set; the "too wide" bodies (8 on 44b6_0113de3b) are the components past `MARGINAL_ARRANGEMENTS_MOST`, which the machine's permanent on the component (A5) measures instead of guessing.
3. **Divisions as arrangements.** A division is a source that takes two targets. The census's 1→2 class (A2) is exactly where that arrangement is needed; the marginal gains a two-target outcome only on those sources, and the rest keeps today's injective sum.
4. **The slide by LCA.** Two key cells share a component at level r exactly when r ≤ level(LCA). Ordered by the tree's DFS order, k key cells need k − 1 LCA levels to give their partition at every level at once (A2). Replaces the bisection over levels.
5. **The overlap at every level from one count.** The census at every sampled cut is one own-node pair table summed over DFS ranges (A2). Replaces a recount per cut.
6. **Contact is an LCA level.** Row 6's "where two bodies first join" is level(LCA(A, B)), exact, with no gap to choose.

## Where the tracker is not yet exact, or holds a chosen number

| where | what | in code |
|---|---|---|
| the residual's orders | {2, 34, 34} and {6, 96, 96} come from two chosen scales (6/5 µm, 2 µm) and n = 4(σ/v)² **rounded to even**. Doug, 23 September: no rounding, anywhere; order = period from the per-axis coherence reading, per sample | `SMOOTH_ORDERS`, `BACKGROUND_ORDERS`, track.h; `exact_track.py` |
| w = (16, 1, 1) | equals σ∘σ with σ = voxel_pm / gcd(voxel_pm) = (4, 1, 1) exactly, but it is written in as a constant, not derived from `voxel_pm` | `AXIS_WEIGHTS`, track.h |
| κ's lead | (mine ± behind/2) / behind rounds by truncating division when frames are more than one apart; it is exact on consecutive frames (behind = 1), which is every frame today | `leaf_disagreement`, relate_frames.cu |
| κ's magnitude | kept mod 2⁴⁰; it wraps silently above 2⁴⁰ | `LINK_MAGNITUDE_BITS` 40 |
| s | the jitter steps stop at 12, a chosen number | `LINK_SWEEP_STEPS` 12 |
| the marginal's set | one frame step and one hop; the exact marginal needs the whole support component (low fruit 2). Every target is taken once; a division is not an arrangement yet (low fruit 3). The bound of 2¹⁶ arrangements is OrganoidTracker's, not measured here | `MARGINAL_ARRANGEMENTS_MOST` |
| the null in the marginal | ω(b, none) is the best null draw's held count, a count of the body's voxels like T, but T is counted at the drift and h⁰ at the climbed null lag | `score_best_null`, score_sample.cu |
| `cohere` (off in base.cfg) | a mean motion is divided by truncating division | group_objects.cu |
| the cut | one level (the most components) for the whole frame | `max_tree_objects` as the program calls it |
| `RUN_PART_ROOM` | 16, not measured | track_driver.cu |

## What the program asks of the engine, and what it offers

The interface through which the two tables optimize against each other.

| the program asks | the engine's row | state |
|---|---|---|
| probes and probe links, not key cells: the slide's partitions and the overlap's census | M3 | built (engine side); `slide_score.cu` not hooked |
| the component tree's LCA levels and DFS order, to replace bisection (low fruit 4, 6) | M3 | theory |
| one own-node pair table at the drift, summed over DFS ranges (low fruit 5) | M3, M5 | theory |
| a per-axis coherence reading that returns an exact integer period (order = period) | M2 | theory |
| a smooth and background pair per sample in flatten | M9 | ruled, not built |
| the permanent over a whole support component, and its size | M6 | theory |
| exact spacings from decimal strings, for σ | M1 | built (`decimal_double`) |
| a file for the bodies and their prints | M9 | theory |

What the program offers the engine: nothing in the machine may know it. The measurements above are the engine's test load (44b6, 6bba), and the proofs the program runs (device equal to host, 0 lanes differ) are the machine's regression.

## What to work toward, in order

The order is the build plan's (`memory/build_plan.md`), as of 23 September:

1. **Built as records beside the path:** the print (row 2); the print cost with one-to-one matching (row 7, `--print-match`); velocity (row 5, `--velocity`); division mass and axis (row 9, `--division`); the exact marginal (rows 7 and 8, `--marginal`); contact side (row 6, `--contact-side`); sizes on the ladder (row 14, `--mass-band`). They do not enter E8, the link, yet. How they enter W and K is Doug's to set.
2. **Move the cell-specific modules** to cell_tracking: `score_sample` and `coherence` moved 23 September, to `cell_tracking/src/`, and `vis_png` to `view/`. Then hook `slide_score.cu` into the frame loop (row 1).
3. **Rows 6 and 13 (B3 with C1).** The jitter core per width.
4. **Rows 9 and 10 (C2).** The entropy bump that settles (division) or stays (lysis).
5. **Row 4 (C3).** Local flow from each body's departure from the drift.
6. **Row 3.** Orders per sample from the period reading, replacing the rounded debt; **row 12 (C4, waits on Doug).**
7. **D3.** Every want A/B on the 25, `above_null` (row 8) included, written into the ledger and this table.
