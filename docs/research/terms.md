# Terms used in the anchor sift research

**Purpose:** Read any document in this directory without guessing what a word means, and know which words are this work's own and which belong to a field.
**Scope:** `docs/research/anchor-sift.md`, `docs/research/anchor-sift-method.md`, `docs/research/anchor-sift-ledger.md`, `docs/research/Salishan/`, and the tools under `tools/dev_env/`

Most of the vocabulary here is standard and needs no legend. What follows is the part that does: words this work minted, and words it uses in a narrower sense than the field does. Each entry names the field's own term where one exists, because a reader arriving from outside should not have to learn a private dialect to check a number.

A term with no field equivalent is marked as such. That is a flag on the term and not a claim that the idea is new.

## Words this work minted

**anchor sift.** The construction the whole body of work rests on: place a small number of necessary conditions over a pattern, reject on any one of them, and pay the exact compare only on what survives. Nearest field terms are filtering, candidate generation, and necessary-condition prefilter, none of which names the whole shape. The name is kept because it reads correctly to someone who has done this kind of work and reads mostly correctly to someone who has not.

**contarget.** The corpus a target is measured against. The word is this work's own and has been replaced everywhere by **reference corpus**, which is the corpus linguistics term. The same thing is a negative class in classification and a background in signal detection. The entry stays here so an older note, a commit message, or a screenshot that still carries the word can be read.

**grain.** One named kind of damage a PDF extraction does, declared per paper so the error stays attributable. The five kinds are substitution, collapse, transposition, insertion and deletion, and `tools/dev_env/Salishan/corpus_script_extraction/repairs.py` holds the mechanism for the repairable ones. The field would call these error classes or a noise model. The word is this work's own.

**pure corpus, pure stream.** The output holding only target-language speech, with reconstructions, rejected forms, other languages and analysis lines held out. The field term is a clean or gold corpus. This work's word carries one extra commitment the field term does not: purity here is verified in two directions against a hand extraction, and `docs/research/Salishan/pure_corpus/README.md` says whose words are in it.

## Words used more narrowly than the field uses them

**anchor.** One offset carrying a necessary condition. The field uses the word for many things, including a fixed reference point in regular expressions, which is not this. Read it here as one probe in a cascade.

**cascade.** Successive anchors applied in order, each cutting the survivors of the last. Standard usage, listed because the depth $\log_2 N / H_2$ is quoted throughout and means the number of anchors before the survivor count reaches one.

**radix.** In `tools/dev_env/Salishan/anchor_sift_algorithmic_extraction/boundary_check.py` this names the per-run test that flattens pooled counts to maximum entropy and scores each run as its own binomial. It has nothing to do with a number base. The field would call it a per-feature standardized residual against a pooled null. The name is a poor one and is kept because the code carries it.

**squash.** The function in `tools/dev_env/Salishan/anchor_sift/anchor_sift.py` that reduces a text to a distribution over byte-pair cells. The field term is a feature histogram or a bigram distribution.

**self distance, D_self.** The distance between two halves of one corpus, used as the resolution floor any between-corpus reading has to clear. The field term is a within-class distance or a split-half estimate. Two documents here quote it as a floor, and `docs/research/Salishan/refs.md` records that cutting a corpus at its midpoint measures paper order instead of resolution, which is why the halves are sampled by alternating.

**rare half, frequent half.** The symbol inventory split at the median of its frequency distribution. Every departure-from-null figure in the ledger is quoted over the rare half unless it says otherwise.

**refutation distance.** How far into a pattern a mismatch is expected to appear, quoted as $m(1-2^{-H_2})$. The field would call it the expected verification depth.

**oracle.** A hand extraction that records what a paper holds, used as the control a reader is graded against. Standard software testing usage, listed because in a linguistics setting the word usually means something else.

## The reference, and what the field calls it

Every measurement here builds a reference by maximizing entropy under the constraints the object itself supplies, then reads the departure from it. Building a reference that way is **Jaynes's maximum entropy principle**, and it is why such a reference carries the constraints and no further assumption. Entropy is strictly concave and a count constraint is linear, so exactly one distribution satisfies it, which is where the finality of the answer comes from.

The departure is a distance from a measured state to its own maximum entropy state under a constraint, and thermodynamics calls that same quantity the **free energy above equilibrium**. `anchor-sift-ledger.md` records the correspondence as exact and cites Parrondo, Horowitz and Sagawa for it.

That correspondence does not carry down to the individual statistics, and assuming it does is a recorded error. **Relative entropy**, also called **Kullback-Leibler divergence** and written `D(p‖q)`, is the field's name for a distance between two distributions. The ledger records at Section 4.3.1 that the quantity governing an anchor measure's worth is not one of those. What the tools compute is a dispersion of gaps against a permutation null, or a standardized residual against pooled counts flattened to maximum entropy. Both are departures from a maximum entropy reference and neither is a relative entropy, and calling them one imports properties they do not have.

## Translations from the working vocabulary

The research was thought in one vocabulary and is written in another. This table holds the pairs, so a reader who meets the working phrasing in a note or a commit can find the claim it became, and so the renderings can be checked instead of taken on trust.

Two rows are corrections and not translations. They are marked, because in those the claim changed and not only the wording.

| working phrasing | as written here | note |
|---|---|---|
| ask the universe a question loaded with what you are certain of | maximizing entropy under the constraints the object supplies | Jaynes's principle |
| the constant we orbit | the null, or the reference distribution | |
| the delta, the departure | the distance from a state to its maximum entropy state under the same constraint | equal to the free energy above equilibrium |
| set, measured, observed | stipulated, estimated, supervised | a modeling choice, an estimate, ground truth |
| superposition, imaginary until measured | partition dependence | classical, and not the quantum sense |
| any medium is a point cloud of vectors and magnitudes | points carrying values, which is what the invariant is stated over | dimensions one to eight, no alphabet |
| an infinite sieve | a cascade of necessary conditions | sound by Proposition 1, incomplete by Proposition 2 |
| the nand of bits | functionally complete over necessary-condition filters | not over search generally, since a shift table is not a filter |
| escape velocity | the radius past which a reconstruction leaves the subject | kept, because the mechanism is stated beside it |
| **correction:** infinite information | finite, bounded by $\log N$ at any fixed scale | inexhaustible across scales, not unbounded at one |
| **correction:** entropy is the death of information | maximum entropy is the death of mutual information | Shannon entropy is at its maximum there, not its minimum |

## The two instruments

These are not synonyms and the ledger's rows are not interchangeable between them. Both are the same construction under Proposition 1.

**the shift agreement detector.** Reads a period or an offset by how often a shift agrees with itself. It has external ground truth three times over, from published cell edges in the Crystallography Open Database.

**the permutation null measure.** Reads a departure from the maximum entropy arrangement of the same multiset. It carries most of the findings in the ledger and has no positive control with an outside answer.

The library under `src/` carries Latin module names, including `impensa_ancorae_acus` for the anchor sift implementation. Those names belong to the library documentation and are out of scope here.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
