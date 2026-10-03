# Learning a machine's rules from probes

## The limits

A machine's rules can be learned by asking it questions and reading its answers. Three results bound what that can find.

**Membership and equivalence queries.** A learner that can ask whether a given input is accepted, and whether a conjectured machine is correct, receiving a counterexample when it is not, learns any finite automaton in time polynomial in the number of its states and the length of the longest counterexample, by the algorithm of [Angluin](#src:Angluin-1987).

**Test suites in place of counterexamples.** A learner with no source of counterexamples checks its conjecture with a test suite. A suite of the W-method kind detects every wrong machine only up to an assumed bound on the number of the target's states, as [Vasilevskii](#src:Vasilevskii-1973) and [Chow](#src:Chow-1978) showed. A machine with more states than the bound can pass the suite and still differ.

**Positive examples alone.** No class of languages that holds every finite language and at least one infinite language can be identified in the limit from positive examples alone, as [Gold](#src:Gold-1967) proved.

A ruleset learned by probing a machine that holds state is therefore exact only up to a stated bound on its states. The learner has to state that bound, and has to be able to ask about inputs the machine rejects.

## Likeness of a stream to its source

The algorithmic mutual information between a stream $s$ and a machine's own rules $r$, $I(s : r) = K(s) - K(s \mid r)$, measures how much shorter $s$ becomes when the rules are given. A compressor gives a computable stand-in: the length of $s$ compressed with $r$ as a dictionary, against its length without it, as in the compression distance of [Li et al.](#src:Li-2004).

A permutation null declares a stream structured when it compresses better than shuffled copies of itself. Every structured stream passes that test, whatever produced it. A test that a stream came from the same source as $r$ needs structured streams from other sources to compare against, and likeness measures only likeness: two instances of one program are alike and still two. Telling one instance from another needs the identity of the next chapter.

## Status

The engine holds instruction rulesets for its device and checks them with membership queries, each of 55 forms answering 65,536 cases against the host's exact integers, and with probes of illegal operations, as the [engine workbook](#src:Quigg-engine-workbook) records. Probing a transport, a bus or a protocol's framing, each of which holds state and would need a stated bound on its states, is not built. No likeness test against foreign streams is built.
