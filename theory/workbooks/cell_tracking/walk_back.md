# Walk back

**Purpose:** The rule every tracker stage is held to: it can be walked back to what it came from.
**Scope:** every stage of the driver ([cell_tracking_table.md](cell_tracking_table.md), its driver section).

Ruled by Doug, 25 September: "The whole point of the tracker is to track cells. If you can't walk back something you did you built it wrong."

- Every stage keeps what it came from: a point keeps its frame, voxel and exact level; a transform keeps its exact inverse; a link keeps its two points and its evidence; a choice in the sort keeps the options it passed over, with their weights.
- Nothing is deleted. What the sort does not keep is marked, and the mark can be walked back.
- A map that sends two readings to one (a clip, a rounding, a bin) cannot be walked back and is not built.
- What prompted it: OrganoidTracker's 1%/99% intensity clip was proposed for S0. It was replaced by a per-sample affine footing held as a pair, plus the set's cumulative count as the contrast; both are invertible.
- It is written into the driver section of [cell_tracking_table.md](cell_tracking_table.md).
