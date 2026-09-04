# Anchor-sift on Salishan

**Purpose:** Apply the anchor-sift method to the Salishan papers: find the language, and decide what may join a pure corpus.
**Scope:** `tools/dev_env/Salishan/`

The method is in `../anchor-sift-method.md`. This is what happens when it is fed these papers.

## The idea

English is the target. What English does not account for is what we want.

That inverts the problem into the half that is resourced. Nobody has to know Nsyilxcən or Lushootseed to find it in a paper. English has to be known, and the residue is the language, a gloss, or a page of font damage.

## The flow

```
1  pure target corpus      one per language, from the hand-read papers
2  pure reference corpus   English, from the translations those readers marked
3  sift noise              screen a paper against the reference corpus
4  truthy against residue  measure the noise, and let section 3 say if it may be read
```

## What runs it

| Directory | Holds |
|---|---|
| `anchor_sift/` | the algorithm: squash, total variation, split-half, support and entropy |
| `corpus_script_extraction/` | the twelve hand-written readers and their repairs and checks |
| `anchor_sift_algorithmic_extraction/` | the sift applied to the papers with no reader, and `boundary_check.py` |
| `word_web/` | the forms of every hand extraction joined by concept, shape and context |

`anchor_sift.py` has nothing to tune and no per-language term. Everything else decides what to hand it.

## Results

Thirteen papers read by hand. Twelve have a reader written against them, and every token of those twelve is accounted for:

```
13 of 13 papers have a hand extraction
12 of 12 papers have every token of the language accounted for
2314 lines of known-pure target language, across six languages
```

The thirteenth, `1975_Hilbert_Hess`, is read and has no reader yet, so `reader_check` holds it ungraded instead of counting it. The six languages are the ones with a pure corpus on disk; two of the thirteen papers are in languages that have no anchor.

Seven anchors: six languages and English. 20 of the 21 pairs are readable, at distances 0.510 to 0.835 against split-half floors of 0.157 to 0.641. The pair that does not read is Lushootseed against Nsyilxcən, 0.620 apart with the Lushootseed anchor's own floor at 0.641.

That floor is not the resolution of the estimator at 219 lines, and treating it as one was an error. `self_distance` cuts a corpus at its midpoint, and a corpus is its papers concatenated in file order, so the cut lands on a paper boundary and reports the distance between whichever papers it separated. Lushootseed is two papers in two dialects and two orthographies, and the midpoint puts one on each side. Shuffling the corpus before the cut puts a mixture on both sides and the floor falls to 0.305. Every corpus moves the same way, by 1.35 to 3.64 times, and the unshuffled number is the larger every time. A resolution cannot rise when its sample grows, and this one does, which is what gives it away.

Read at the shuffled floors, all 15 pairs among the six languages separate, Lushootseed against Nsyilxcən included, and six of the 15 change verdict. The 21 above counts the same six languages plus English, which adds six more pairs.

The papers are a separate question and the anchor floors do not decide it. `language_check.py` prints the worst anchor D_self and then judges each paper against that paper's own split-half instead, which is the right thing to judge it against. Of the 106 papers naming a language the anchors know, 3 are readable and the distributions agree with the prose on all 3. Of the 103 that are not, 8 hold too small a sample to ask and 95 fail for one reason: the gap between the nearest anchor and the runner-up has a median of 0.0247, against a median paper floor of 0.3527. The gap is fourteen times inside the noise.

Sifted from the papers with no reader:

```
144 papers written to build/corpora/sifted
13190 lines nearer the language, 20361 residue for a person to look at
114 of the 144 carry the language their own front matter names
```

Admission on each corpus's own growth curve:

| Language | Pure | Candidates | Admitted | D_self before | after | Support after |
|---|---|---|---|---|---|---|
| nɬeʔkepmxcín | 451 | 339 | 339 | 0.3098 | 0.3196 | 1249 |
| St'át'imcets | 371 | 868 | 280 | 0.2768 | 0.3459 | 1520 |
| Nsyilxcən | 749 | 4898 | 1000 | 0.1571 | 0.1893 | 1322 |
| Lushootseed | 219 | 1262 | 1262 | 0.6411 | 0.4163 | 2377 |
| Comox | 426 | 1275 | 0 | 0.1956 | 0.1956 | 407 |
| Nuxalk | 98 | 1359 | 0 | 0.2536 | 0.2536 | 346 |

nɬeʔkepmxcín took every candidate and stayed where it was. Comox and Nuxalk refused all of theirs: tipping the whole set into Comox takes it from 407 cells to 2586 and its split-half distance from 0.196 to 0.457, which is a second distribution arriving instead of more of the first.

Lushootseed took all 1262 and its split-half distance fell from 0.641 to 0.416. The admission rule is a ceiling and nothing else, and a corpus sitting above the band it belongs in will admit whatever pulls it down. What was pulling it down here is now known: 0.641 is two dialects on opposite sides of the midpoint cut, and 1262 candidates dropped into the middle of them dilute that split without teaching the anchor anything. A falling floor was read as a corpus improving when it was a boundary being blurred.

Seven languages hold candidates and have no hand-read corpus to grow: Halkomelem 739, Montana Salish 136, Twana 72, Secwepemctsín 33, Straits 23, Squamish 17, Upper Chehalis 14.

## What it cannot do

Support is still climbing on every one of these corpora. None has seen its own alphabet. A candidate that looks nothing like a member is not thereby wrong, and resembling what is already there is the wrong test.

The sift finds candidates. It does not read them. The corpus is still hand extracted and verified in three passes, for line and for notation, and this exists to say where to look.

Growing the Lushootseed anchor does not unlock the 103 papers, and an earlier version of this document said it would. The 95 that are large enough to ask fail because a paper's residue sits almost the same distance from all six language anchors: the median gap between the nearest and the runner-up is 0.0247 and the median paper floor is 0.3527. Nothing about the anchors' own sizes moves those two numbers past each other.

What the 95 need is a measure that separates the anchors as seen from a mixed residue, which the byte pair distribution does not. `corpus-derivation.md` section 7 has the first thing that does: holding a concept fixed with the word web's gloss edge, flattening the pooled counts to maximum entropy, and testing one run at a time. That recovers a published dialect border inside Lushootseed at a corpus size where the whole-distribution comparison needs 2.9 times more text. It has not yet been turned on the 95, and that is the next thing to try.

Two dialects pooled into one anchor is still worth splitting, because it is what inflated the floor from 0.305 to 0.641 and it is the same defect in every corpus that holds more than one paper. Splitting it is a correction to the anchors, not a route to the 95.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
