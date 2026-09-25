# Scan, then sort

**Purpose:** The rule that orders the driver: every frame of every sample is scanned first, and sorting happens only at the end.
**Scope:** the driver's stages, S0 to S11 of [cell_tracking_table.md](cell_tracking_table.md).

Ruled by Doug, 25 September, and said more than once: "you scan everything and then you sort stuff. You don't need to sort it before you scan in all of the samples."

- The driver scans first: every frame of every sample gives points and fields that bound nothing (peaks as points, the drift, the entropy history).
- Sorting (linking, keeping, divisions, any partition into regions) happens only at the end, over the whole sample, and anything set-wide over every sample.
- Never partition a frame into regions (watershed/toboggan catchments, a max-tree cut) as it is read: that decides membership from one frame. Doug dislikes "basin" because the name, and the thing, bound the set.
- The score reads only node positions (7 µm) and edges, so regions are not needed for it.
- The driver's stages are the table "The driver: scan everything, sort at the end" in [cell_tracking_table.md](cell_tracking_table.md) (S1 to S11). OrganoidTracker's techniques (O1 to O22) and Hawkins et al. 2025's fates (H1 to H6) are mapped onto those stages there.
- The rule is Doug's.
