# Projects built on the engine

**Purpose:** How the projects that build on the engine take it. No edit here waits on them, and no build of theirs reads a tree in motion.
**Scope:** the RSNA knee project and the CASMI chemistry project, .

Ruled : the chemistry engine does not take precedence over the engine's own work, and a project built on the engine takes it as a git dependency.

- Engine source edits are never paused or held while one of them is building. A build that needs the tree to hold still uses a pinned checkout.
- A record-API shape change is announced before it lands in a commit, and GPU runs are scheduled by hand until tessera (the device-job scheduler) exists.
- Commits happen only when Doug decides, and the projects move their pins then.
