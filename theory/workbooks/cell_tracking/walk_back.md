# Walk back

**Purpose:** The rule every tracker stage is held to: it can be inverted to what it came from.
**Scope:** every stage of the driver ([cell_tracking_table.md](cell_tracking_table.md), its driver section).

Ruled: "The whole point of the tracker is to track cells. If you can't walk back something you did you built it wrong."

- Every stage keeps what it came from: a point keeps its frame, voxel and exact level; a transform keeps its exact inverse; a link keeps its two points and its evidence; a choice in the linking pass keeps the options it passed over, with their weights.
- Nothing is deleted. What the linking pass does not keep is marked, and the mark can be inverted.
- A map that sends two readings to one (a clip, a rounding, a bin) cannot be inverted and is not built.
- An example: OrganoidTracker's 1%/99% intensity clip sends many readings to one and fails the rule. S0 holds a per-sample affine normalization as a pair instead, plus the set's cumulative count as the contrast, and both are invertible.
- It is written into the driver section of [cell_tracking_table.md](cell_tracking_table.md).
