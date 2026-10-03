# The engine's ideas, stated so they can be decided

This research paper collects the ideas behind the engine that have a form a proof or a measurement can decide. Each chapter states one idea precisely, sets it against the literature it belongs to, says what the idea does not give, and names the test that would settle it. What the engine builds and measures is recorded in the [engine workbook](#src:Quigg-engine-workbook). A chapter says so where a part is built and does not claim a part that is not. The engine's claims that have no such form yet are kept as wants in the same workbook.

| file | what it holds |
| --- | --- |
| [sensor_noise.md](sensor_noise.md) | the four noise sources of an image sensor, how their variances combine, and how averaging frames separates the fixed pattern from the rest |
| [threshold_search.md](threshold_search.md) | search for a hash below a threshold in a 2^120 keyspace, its expected cost, and what folding schemes compress and what they do not |
| [state_vectors.md](state_vectors.md) | the cost of simulating a quantum circuit classically, and why a deterministic interpretation leaves that cost where it is |
| [dwell_and_entropy.md](dwell_and_entropy.md) | how long a bit holds its value against the entropy rate of its sequence, derived for renewal processes, and the bench that would measure it |
| [self_reproduction.md](self_reproduction.md) | von Neumann's self-reproducing automaton, and what a compiler that compiles itself does and does not show |
| [learning_a_ruleset.md](learning_a_ruleset.md) | the limits on learning a machine's rules from probes, and what compression can and cannot say about a stream's source |
| [identity.md](identity.md) | identity written into an instance at spawn, and a hash-chained record of its series, with what each proves |
