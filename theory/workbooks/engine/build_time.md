# Build time

**Purpose:** What the time a build takes is spent on.
**Scope:** every build and long run of the engine.

Doug, 23 September: "you wait a long time for builds you could be using to update the table during that time remember to background those runs and update paperwork during the build time, dont build just do maths".

- Every build and long run is started in the background.
- While it runs, the engine table, the theory documents and the build plan are brought up to date and the algebra is worked. Nothing sits in a wait loop.
- Documents are not compiled, so editing them during a build is safe; engine sources are still not edited until "driver exit".
