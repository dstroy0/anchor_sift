# Build it right first

**Purpose:** The rule against building an interim version already known to need redoing.
**Scope:** every build of the cell program.

Ruled by Doug, 25 September: build it right from the first build, and stop building it wrong. His analogy: a contractor who builds it wrong, gets paid, then gets paid again to renovate.

- If the right design is known (or Doug has just ruled it), build that directly. Do not build, prove or run a stopgap on the old path to "validate the pipeline first" and then redo it.
- What prompted it: after Doug approved the cumulative-count contrast and pointed out that the engine's integers can be any width, a build of the scan on the 16-bit residual was under way, to be redone for the wide input. That build was stopped.
- Work out the whole design against the rules (walk back, scan-then-sort, no chosen numbers, any width) before writing code, so the first build is the one that stays.
