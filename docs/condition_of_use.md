# The condition of use

**Purpose:** Say whose language the corpus holds, and the condition every tool for language from this work carries.
**Scope:** `examples/language/`, `theory/theory/Salishan/`

## Whose language this is

The largest language corpus, and the one everything else in the languages category is currently measured against, is Salishan speech, which was written down by a linguist or their transcriber in almost all cases.

**This work does not exist without the speakers.**

Every table in the Salishan corpus opens with the person who spoke, before the linguist who published and before anyone who read it into a file. Where a paper cites a published dictionary and never says who spoke, its entry says so. The [Salishan](https://github.com/dstroy0/orior/tree/main/theory/theory/Salishan) research paper carries that index, written speaker first.

The rationale is simple:

1. A linguist wrote the paper.
2. A person read the paper into a table.
3. Neither of those is whose language it is in almost every case.
4. Here, and for any derivative, you must list the person who was teaching us about their language first.
5. It's fair.
6. It acknowledges their contribution.
7. It makes performing meta-analysis about the language itself vs. the linguist or transcriptionist's style far less cumbersome over time.

!!! note "here, respect is identical to research efficiency"

## The condition

These tools read a language and can put one back. [`to_phonemes.py`](https://github.com/dstroy0/orior/blob/main/examples/language/1_represent/to_phonemes.py), [`encode_percussive.py`](https://github.com/dstroy0/orior/blob/main/examples/language/1_represent/encode_percussive.py) and the sound representation work do what they are named for, and [`regeneration_limit.py`](https://github.com/dstroy0/orior/blob/main/examples/art/4_measure/regeneration_limit.py) measures how much of a source a regeneration recovers. Saying otherwise would be a false claim about the code, and a safeguard resting on a false claim is not a safeguard.

Regeneration is faithful near the subject and escapes it with distance. Close to the center of mass of the subject the output is a copy. Move outward and it carries more, until at some distance it leaves the source distribution and is no longer that language. Past that it becomes obvious nonsense and nobody is fooled.

Immediately before that boundary is a narrow band where the output is still coherent and may already not be the language.

**Nothing here marks which side of it a result fell on.**

That band is where a native speaker belongs. The question there is _is this mine_, which is a question of anthropology, of philosophy, and for many communities of what is sacred. No amount of measurement turns it into a question an algorithm can answer.

!!! warning "Every tool for language that comes out of this work requires a human to review its output."

    That is a condition of use, not a recommendation. For a language with few remaining speakers, publishing a form drawn from outside the distribution as though it were the language is not a recoverable harm.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
