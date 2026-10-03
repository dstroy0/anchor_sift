# The Merkle DAG: obsignatio

**Purpose:** The theory of the engine's integrity layer: the dimensional Merkle DAG that commits to every compressed file, set and file, what it proves, what it costs, and where it stops.
**Scope:** `engine/base/obsignatio` (the BLAKE3 port and the level folds), the `.kcr` Merkle section, and the verify in `engine.cu`. The rows are M13 and A10 in [engine_table.md](engine_table.md). Statuses follow [README.md](README.md).

## Why a DAG and not a CRC

A CRC-64 is linear over GF(2): crc(a ⊕ b) = crc(a) ⊕ crc(b) ⊕ crc(0). So anyone can craft an edit that leaves it unchanged, it says nothing about where a fault sits, and two CRCs do not compose into a commitment on both. It still misses a random corruption only 2^−64 of the time, and it catches every burst of 64 bits or fewer; its failure is structure, not size.

A k-bit check of any kind misses a random corruption with probability 2^−k, whatever the function. A check smaller than 64 bits is therefore never stronger than CRC-64 against random flips, and no finite check is infinite. The Merkle DAG takes k = 256 at every node:
- a random corruption passes one node with probability 2^−256;
- a deliberate collision costs about 2^128 work.

What the DAG adds is structure. It is nonlinear, and no edit can be steered past it. A mismatch walks down to its place. Every subtree is hashed on its own, in parallel, and the parents fold them exactly.

## The node function

Every node is BLAKE3 in keyed mode, under a key derived once for its level (derive-key per level, dated context strings):

  K_ℓ = BLAKE3-derive-key-context("obsignatio aeterna 2026-09-23 " ‖ ℓ),  H_ℓ(m) = BLAKE3-keyed(K_ℓ, m)

The levels ℓ are row, plane, volume, lanes, chunk, stream, side stored, side inflated, side, members, sample, set, file and universal. Two nodes of different levels can only agree through a collision between two keyed BLAKE3 instances: domain separation is BLAKE3's own. A later change of format takes a new date, and old and new roots never meet.

BLAKE3 is itself a Merkle tree over 1 KiB chunks: its left subtree always holds the largest power of two of chunks that is smaller than the whole. On the device, pairing the nodes of each level and carrying the odd one up gives exactly that tree:
- n = 3 folds (c₀c₁)c₂;
- n = 5 folds ((c₀c₁)(c₂c₃))c₄;
- n = 7 folds ((c₀c₁)(c₂c₃))((c₄c₅)c₆).

So the level-parallel device fold and the host's stack fold are one function, proved equal on every length from 0 to 102,400 bytes.

## The compressed file's DAG

For a sample I of extent (T, Z, Y, X), lanes little-endian u16 in key order:

  ρ(t, z, y) = H_row(I[t, z, y, 0 … X−1])
  π(t, z) = H_plane(ρ(t, z, 0) ‖ … ‖ ρ(t, z, Y−1))
  υ(t) = H_volume(π(t, 0) ‖ … ‖ π(t, Z−1))
  Λ = H_lanes(υ(0) ‖ … ‖ υ(T−1))

The stored stream: chunk c holds the ℓ_c bits from offset o_c to o_{c+1} (the last chunk ends at the stream's bit count B). Each chunk is repacked to start at bit 0, least significant bit first, as the coder writes them:

  κ(c) = H_chunk(LE64(ℓ_c) ‖ bits_c),  Σ = H_stream(LE64(o_0 … o_{C−1}) ‖ LE64(B) ‖ κ(0) ‖ … ‖ κ(C−1))

The source's other bytes (the DICOM headers) are stored deflated. The side root commits to both forms (both):

  σ_s = H_side stored(deflated bytes),  σ_i = H_side inflated(inflated bytes),  σ = H_side(σ_s ‖ σ_i)

The member tables and names: μ = H_members(the six tables as LE64 words ‖ the names).

The sample's root commits to every section (every section):

  Ω = H_sample(LE64(extent, C, B, lane offset, members, side bytes, deflated bytes, name bytes, lane nodes) ‖ Λ ‖ Σ ‖ σ ‖ μ)

The set's root commits to every sample's in the order named: Θ = H_set(Ω_1 ‖ … ‖ Ω_n).

Every node is stored in the `.kcr` ("every floor of the tower"): the six roots, the TZY + TZ + T + 1 lane nodes, and the C chunk leaves. They sit right after the head. Both placements, after the head and at the end, were measured on the knee: the same 25,218,496 bytes, and a prove median of 76 ms each over 15 alternating runs. The Merkle DAG is made from the source before the stream is written. Writing it last gains nothing. Written first, it arrives in one forward read with the head.

## The witness

"we ingest seal and then witness pixel:pixel 1:1 once. then we have our hash and we know our input is verified and witnessed." Ingest hashes the source as read, writes the compressed file, reads it back and proves every node. Then it witnesses the compressed file against the source twice (keep both):
- the decoded voxels against the source lanes still on the device;
- a second, independent read of the source against the rebuilt volume, pixel for pixel.

The second read is the only step that catches a flip in the first read, which would otherwise be committed as the truth. After the witness the root stands for the input: every later check is hash against hash, and no source is needed again.

## What it proves

- **Locality.** A change at lane (t, z, y, x) changes exactly ρ(t, z, y), π(t, z), υ(t), Λ, Ω and Θ, and no other node, except with probability 2^−256 per node. A change inside chunk c's bits changes κ(c), Σ, Ω and Θ, and no other node. A mismatch therefore walks down to its row or chunk. **Proved:**
  - 9,234 single-lane flips of a 2 × 3 × 3 × 513 volume each change exactly their four path nodes;
  - 57,216 single-bit flips of a stream (every bit, padding included) each change exactly the leaf that holds them, or nothing when they sit outside every message.
- **End to end.** The lane nodes are taken from the source's lanes at ingest and compared against the lanes decoded from the file. A decoder fault shows as a row as well as a flip on disk.
- **Order of the check.** The stored bytes are checked first (κ, Σ, σ_s, μ). A flip on disk is named before anything decodes corrupted data. Then the side bytes inflate (σ_i, σ), then the file decodes (ρ … Λ), then Ω.
- **Tampering, on a real compressed file.** Single bits were flipped in copies of an RSNA knee compressed file (1 × 24 × 640 × 640, 2,400 chunks, 15,386 lane nodes). Every case refused the compressed file and named the place:

| flipped | named as |
|---|---|
| the extent word | the head's shape disagrees with the Merkle DAG's node counts |
| the stored sample root | one root |
| row node 5,120 | row t 0, z 8, y 0 |
| plane node 0 | one node above the rows |
| chunk leaf 1,200 | chunk 1,200 |
| a limb in the stream | chunk 1,234 and the stream root, before any decode |
| the deflated side bytes | the side's stored leaf |
| a member name | the members root |

  The untouched copy proved clean.

## What it costs

- **Nodes.** 32 bytes each: TZY + TZ + T + 1 lane nodes, C chunk leaves and 6 roots. The row level dominates: 32 bytes per row of 2X bytes, which is 16/X of the raw bytes. At X = 960 that is 1.7% of raw.
- **Measured on the knee** (re-ingested and hashed):
  - 1 × 34 × 960 × 960: 25,218,496 bytes against 23,927,904 under CRC-64. That is +1,290,592 bytes: 32,676 lane nodes and 7,650 chunk leaves, less the CRC words. 5.4% of the compressed file, 2.1% of raw.
  - The signed series, 1 × 24 × 640 × 640: 11,319,416 bytes against 10,750,104.

## Where it stops

- **The lifting transform spans all four axes**, and no single plane decodes on its own. A check without a full decode is possible only on the stored bytes: the chunk leaves, the stream root, the side's stored leaf and the members root. A decoded row can be checked only after a whole decode, though a mismatch still names its row.
- **An unkeyed root guards against accident, not against an author.** Whoever can rewrite a file can recompute its roots all the way up. Against a deliberate tamperer the universal root has to be anchored where they cannot write:
  - a signature over it, with the public key compiled in;
  - or a root published out of band.
  
  Doug's plan fuses the check into the engine's one swept cycle and injects the engine's own hash at compile time. The anchor is still open.

## The shared shape

The lane DAG folds x, then y, then z, then t: the same lattice, in the same order, that the lifting transform's levels lift and that the moments' DFS prefix sums (A3). The residual (A1) is a fold of one binomial step along each axis. The component tree (A2) is a fold of the level order. C (A4) is a fold of one count under a shift. The Merkle DAG is a fold of one keyed hash. Each is one lattice read once, with a different combining operator: a sum, a convolution, a level merge, an integer lift or a hash. Only the operator carries the meaning.

Of these operators, only the Merkle DAG's is not associative: H(H(a ‖ b) ‖ c) ≠ H(a ‖ H(b ‖ c)). Its tree shape is therefore fixed and written down, where a sum could be regrouped freely. That fixed shape makes a mismatch locatable (observation).

## What the engine shows about the wire and the witness

Doug's nine conjectures on the wire and the witness are kept verbatim, numbered as he gave them, in [wants.md](wants.md). What the engine shows that bears on them follows (a to g, checked). Derived unless marked.

- **(a) The Merkle DAG detects and locates a change; it does not restore the value.** Locality is proved ("What it proves"): a mismatch walks down to its row or chunk.
  - Derived: the Merkle DAG can confirm a guessed repair. With t unknown flips in a segment of m bits, a search tries C(m, t) candidates. The right one proves, and a wrong one passes with probability 2^−256. One flip in a row of 960 lanes (15,360 bits) is 15,360 hashes. That is a search, and the Merkle DAG holds no error-correcting code.
  - "All crystals fail" (point 1), read against Locality: a change fails its own path of nodes up to the set root Θ. Every other sample's root Ω still proves.
- **(b) Every compressed file is legal, and T carries no redundancy** ("Redundancy" in [two_crystals.md](two_crystals.md)). Rebuilding needs the source or the whole compressed file, and it fails closed: every tampered case in the table above was stopped and named.
- **(c) A CRC with the Merkle DAG as a locator.**
  - Erasure: a CRC of degree r with g(0) = 1 recovers any burst of at most r bits whose positions are known. The burst e at offset i leaves the syndrome x^i·e(x) mod g. g(0) = 1 makes x a unit mod g, and no nonzero e of degree below r is a multiple of g: the syndrome names e. At r = 64, a burst of up to 64 bits.
  - The Merkle DAG locates to a row or a chunk, not to bits. Inside the segment the burst's place is unknown, and that is burst correction: a linear code that corrects every burst of length b needs r ≥ 2b check bits ([Reiger 1960](#src:Reiger-1960); [Peterson and Weldon 1972](#src:Peterson-and-Weldon-1972)). A CRC-64 corrects bursts of at most 32 bits, and only with a generator chosen for it.
  - "We have the crc" (point 2) holds outside the `.kcr`: the `.bapx` segment table carries a CRC-64, and the entropy history carries `payload_crc` and `cloud_crc`. The `.kcr`'s CRC words were replaced by the Merkle DAG ("What it costs"). Adding one back is a format change, Doug's call.
- **(d) The set root is a joint function of every compressed file's root.** It changes on any change, except with probability 2^−256 per node. This is classical binding, and it involves no quantum entanglement (points 3 and 4). Θ over a set is built. The universal root is ruled and still unbuilt (below).
- **(e) The level as amplitude and the knf as phase** (points 6 and 7).
  - An exact pair is an exact complex amplitude when the pair is (re, im), as Gaussian rationals. A (magnitude, phase) pair is exact only with the phase an index k of a root of unity, ζ_N^k in ℤ[ζ_N].
  - The knf as phase is untested, and it is carried in [wants.md](wants.md).
  - An exact classical register holds a qubit's state vector exactly. `ask_state` (M21) carries a qubit exactly now. n qubits cost 2ⁿ amplitudes, and exact classical registers give no Bell violation between separated parts. "Classic qubit" fits the reading of an exact simulation with no rounding.
- **(f) Witnessing the wire** (point 8). A hash reads the value it commits to. An unknown quantum state cannot be copied ([Wootters and Zurek 1982](#src:Wootters-and-Zurek-1982)), and reading one disturbs it. A Merkle-witnessed wire is classical by construction.
- **(g) "Knows all noise from non noise"** (point 9). Exact equality catches any deviation from a committed state. The second, independent read of "The witness" guards the value before hashing. Past that, the Merkle DAG cannot say whether the committed value was the true signal: shot noise in the source is committed as the truth.
- **The words of point 2.**
  - The elevator clock: "The clock is the elevator", [noise_sieve_tower.md](noise_sieve_tower.md) §9 and §17. Every level of the lifting transform sits at a known offset.
  - The window identity: the identity line, one null draw a window (§18).
  - The locale: rules derived once at the top reach every locale (§1).
  - "Rebuildable", derived: from the whole compressed file, yes. T⁻¹ is exact, and the Merkle DAG proves the result. From a part, only the samples whose cone (reach L + 2 along a line) lies inside it.
  - "The spine" has no definition in the engine, and it is carried in [wants.md](wants.md) with Doug's question of point 5.

## The universal root (ruled, not built)

"ingest->seal kcr shards until we accumulate the grains to a lattice and the same goes for the output and any scheduling, we coalesce a universal hash for the state of the program". The plan:
- each `.kcr` is a shard hashed at ingest, and the shard roots fold into the set's lattice root Θ;
- outputs, schedules and kernels are hashed the same way;
- H_universal folds every file the engine touches, inputs read and outputs written, plus a hash of the engine itself ("our specific engine signature gets hashed and stops the program if its different"; "we do compile time injection for the engine hash").

The engine is deterministic. Rerunning the same input on the same engine must give the same universal root: the Merkle DAG doubles as a reproducibility proof, and a user who runs their own data hashes it themselves.

