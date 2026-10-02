# The conditions of use

**Purpose:** Say what this work can do to people and to what people hold, and the condition each use carries.
**Scope:** every tool, measurement and derivative that comes out of this work; `examples/`, `theory/`

The method reads anything that can be split into parts and counted. That includes people: what they speak, what they write, what a scan of their body holds, and what they keep closed. Each section below names one thing the work can do, what it cannot tell you, and what has to be true before you use it. Every condition here is a condition of use, not a recommendation.

Anyone may read, run and change this work under the AGPL. A product or service that keeps its source closed needs [the commercial license](https://github.com/dstroy0/orior/blob/main/LICENSES/LicenseRef-Commercial.txt), and an educator's exception is issued under [the educator's license](https://github.com/dstroy0/orior/blob/main/LICENSES/LicenseRef-Educational.txt). Section 7A of each makes every condition on this page a term of that license, beside Section 7 for language. Breaking one can end it at once.

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

## Language that comes back out

These tools read a language and can put one back. [`to_phonemes.py`](https://github.com/dstroy0/orior/blob/main/examples/language/1_represent/to_phonemes.py), [`encode_percussive.py`](https://github.com/dstroy0/orior/blob/main/examples/language/1_represent/encode_percussive.py) and the sound representation work do what they are named for, and [`regeneration_limit.py`](https://github.com/dstroy0/orior/blob/main/examples/art/4_measure/regeneration_limit.py) measures how much of a source a regeneration recovers. Saying otherwise would be a false claim about the code, and a safeguard resting on a false claim is not a safeguard.

Regeneration is faithful near the subject and escapes it with distance. Close to the center of mass of the subject the output is a copy. Move outward and it carries more, until at some distance it leaves the source distribution and is no longer that language. Past that it becomes obvious nonsense and nobody is fooled.

Immediately before that boundary is a narrow band where the output is still coherent and may already not be the language.

**Nothing here marks which side of it a result fell on.**

That band is where a native speaker belongs. The question there is _is this mine_, which is a question of anthropology, of philosophy, and for many communities of what is sacred. No amount of measurement turns it into a question an algorithm can answer.

!!! warning "Every tool for language that comes out of this work requires a human to review its output."

    For a language with few remaining speakers, publishing a form drawn from outside the distribution as though it were the language is not a recoverable harm.

## What is held closed

In many traditions a language or a story is held under restriction, open to some people and closed to the rest, and it cannot be separated from law and country. A repository serving a file is not permission to use what is in it, and the license on this code says nothing about it.

Use of that material needs the permission of the people who hold it, on their terms. Where their terms say no, the answer is no.

The method strips the meaning out of a text, and one instrument can then read a script nobody can read and a protein chain alike. Where a language is held as sacred, that step does not miss part of the thing. It mistakes what the thing is, and every number it returns would be about something else.

## People named by their writing

The reading finds a writer. Given seven people who each wrote English prose in one period, it puts a text with its own writer 77.4 percent of the time, against one in seven by chance. [`author_test.py`](https://github.com/dstroy0/orior/blob/main/examples/language/4_measure/author_test.py) runs it.

Pointed at a text with no name on it, that is a way to name a person who chose not to be named. Do not use it to name anyone who has not agreed to be named. A match is a measurement against a set somebody chose, and never a proof. The person it names wrongly carries the cost of that.

## Who made a thing

A departure from the null does not mean a person made the object. The gaps between primes depart from it, and a metal of one element packs into a lattice that no person arranged.

A reading here therefore cannot show that a text was written by a person, copied, or produced by a machine. Do not offer it as evidence that someone wrote, copied or generated anything.

## A patient and a scan

The engine reads medical images, DICOM among them, and it was measured on knee scans. A scan is a person.

Use only data you are allowed to hold, under the terms it was given under. The engine loses nothing from a DICOM file, the header included, and a header can carry the name of the patient and the date of the scan. Do not publish a scan, a header or a crystal that can name a patient. Nothing here is medical advice.

## Systems you do not own

The instruments measure SHA-256, the block header of a chain and number-theoretic transforms. One failure they found, a twiddle table taken without a proof that returned every coefficient wrong without saying so, is the failure a published fault attack uses to recover a key and forge a signature. The [twiddle proof](https://github.com/dstroy0/orior/tree/main/theory/theory/precision) names it.

Test only what you own or have permission to test. A finding in someone else's system goes to them first, in private. A finding in this one goes through [SECURITY.md](https://github.com/dstroy0/orior/blob/main/SECURITY.md).

Nothing here claims a weakness in SHA-256, and nothing from it should be published as though it did.

## Reporting a result

Report a result with its null, its positive control and the bar it was drawn against, and keep what killed a claim beside it. A number that leaves those behind reads as more than it is. For a reading about people, that is where the harm is done.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
