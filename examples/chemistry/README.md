# Chemistry

**Purpose:** Read the building block and the rule the anchor_sift way, valence as a necessary
condition and the bond length as an oracle, using the primitives already in the tree.
**Scope:** `examples/chemistry/`

| stage | script | what it answers |
|---|---|---|
| `5_sift` | `valence_is_a_necessary_condition.py` | whether the octet refuses no real molecule and prunes the rest, and whether a shuffle of the same atoms loses it |

Stages one through four and six are not present yet, and the reason is a boundary, not an omission.

## One stage is here because one stage runs on what exists

The sift proposition is domain blind: any subset of a pattern's points is a necessary condition, so
no selection rule loses a true occurrence, and the converse fails, so every survivor is confirmed.
Valence is that proposition in chemistry. Every atom of a real molecule closes its octet, so the
octet refuses no molecule and prunes arrangements, and the error is one directional. That runs today
with `reference.shuffles` for a drawn null and needs no new engine part, which is why stage five is
the one present.

The script reads two routes and shows them able to disagree. The per-atom octet is the strong one; the
handshake sum, that the valences add to twice the bond count, is weaker and passes on a mis-wired
peroxide the octet refuses. It carries a positive control, eight real molecules that close every
atom, and a negative control, arrangements the octet must refuse, because a pass proves only that the
check is wired to say yes until something it should decline is declined. The null is drawn by
permuting which element sits at which atom over the same bond graph: most permutations put an element
where its valence does not fit the degree, so the real assignment sits above the band the shuffles
occupy. No number here is a value; each is a departure from that band.

## Why the other stages wait

They wait on a boundary the engine is holding. The element ledger, the proton count, the electron set,
the Pauli behavior behind the shell counts and the periodic recurrence, is the atomic structure, and
it is authored once by the atomic-structure subject in a shared `representation/atom` home. Chemistry
consumes it and does not transcribe it, because a second element table is a second source of truth for
a fact chemistry did not establish. Stages one through four need a molecule reader,
`representation/structure` beside the protein and crystal readers, that reads atoms as points carrying
element vectors and bonds as the vectors between them. Stage six needs `oracle/chemistry`, the bond
lengths held as facts apart from the language family trees, which the oracle README already reserves a
directory for. Those are coordinated additions, not this subject's to write alone, and until they
land the remaining stages would be transcriptions of the plan rather than the state.

What each stage will do, and the predictions each makes, is stated in `theory/chemistry` before the
readers exist, in the design-only posture the exact-arithmetic chapter of the image-transforms book
uses.

## Running one

```
python examples/chemistry/5_sift/valence_is_a_necessary_condition.py
```

It reads no file and reaches no network. The molecules and their valences are in the script, a
seven-element bonding map that is chemistry's layer and not the element ledger.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
