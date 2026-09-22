# Provenance: Authorship, Priority, And Terms

**Purpose:** Establish three separate claims about this work with three separate instruments, so each
one is checkable by a stranger with no secret and no cooperation from the author. Say which
instrument answers which claim, and say which proposed mechanisms do not work.
**Scope:** `maint/signing/`, `MANIFEST.tsv` and its signature, the public key, the timestamp proofs.
**Owner:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-10

## 1. Three Claims, Routinely Conflated

| claim | plain statement | instrument | secret needed to verify |
|---|---|---|---|
| authorship | this work is mine | a signature over a manifest | none, the public key verifies |
| priority | I held it before anyone else | a timestamp nobody can move | none, the chain verifies |
| terms | derivatives stay open | the AGPL | none, it is a license |

The three fail independently, and an instrument for one is worthless for the others. A signature
proves who, and its own date field is written by the signer, so it proves nothing about when. A
blockchain anchor proves when to the second and says nothing about who. A license governs copying
and says nothing about either.

Getting all three needs all three. The design is that short, and everything below is mechanics.

## 2. Authorship

The key is already in place: rsa4096, fingerprint

```
4F5C90B61FAAD427F7DCB150E603975E472D00FE
uid  Douglas Quigg (dstroy0) <dquigg123@gmail.com>
```

**Publish the public half everywhere.** A public key exists to be published, and publishing it
widely is how a key stays reachable for as long as anyone cares. Put it in the repository, on the keyservers,
in the archived copy, in the README. A verifier who has the public key and a signed manifest can
check authorship in one command, forever, with the author unreachable.

**Sign one small file deliberately.** The tree already has this shape: `MANIFEST.tsv` lists every file
with its digest and its size, and `MANIFEST.tsv.asc` signs the manifest. The comment in the manifest
states the rule outright, *sign this file, not the corpus*, and the rule is right. One signature over
a list of digests covers every byte the list names, and it stays one deliberate act by a person.

Signing everything separately and automatically is worse on two counts. It multiplies the number of
attestations without adding information, since the manifest already covers the bytes. And it turns a
human attestation into a build step, and at that point a signature stops meaning that somebody
looked.

## 3. Priority

**A signature cannot establish priority, including an honest one.** The timestamp inside a signature
is supplied by the signer's own clock. Anyone holding a key can produce a signature bearing any date
at all, and a self-signed date is therefore no evidence against a competing claim. This is the gap
the rest of this section closes.

**Anchor a digest into Bitcoin.** OpenTimestamps takes a SHA-256 digest, aggregates it into a Merkle
tree with other submissions, and commits the root in a transaction. The resulting proof file shows
the path from the digest to a block, and the block's position is secured by the accumulated proof of
work of the whole chain from that point forward. The consequence is the property priority needs:

* nobody can backdate it, the author included, because doing so means rewriting the chain
* nobody needs a key, a secret, or an account to create the proof or to check it
* the proof is a small file that lives beside the work and verifies offline against any full node

That is the correct use of the chain for this purpose, and it is the instrument that answers *no one
can be first ahead of me*. The digest goes on chain. Nothing else does.

**Add independent third-party records.** Each carries its own date, held by a body with no stake in
the claim:

* the Wayback Machine, for the published pages
* Software Heritage, which archives whole repositories including their history
* a Zenodo deposit, if a citable identifier is wanted

Three independent dated records plus a chain anchor is a strong priority position. A chain anchor
alone is already stronger than anything self-asserted.

## 4. Terms

The AGPL is doing real work and should stay. It keeps a derivative that is offered as a network
service obliged to offer its source, covering the gap the GPL leaves. That coverage is the reason to
pick it.

**What it does not do.** It is a copyright license, so it governs copying, modification and
distribution of the code. It does not establish who was first, because priority is a question about
dates and not about permissions. It does not stop an independent inventor, because copyright never
reached independent creation. And it has no bearing on whether a leaked key can be used to forge a
signature, because forging a signature is not a copyright act and no license term reaches it.

Viral copyleft protects the terms the code travels under. It is not a substitute for a dated record
and it is not a protection for a secret.

## 5. Mechanisms That Do Not Work

Three were proposed. Each is written out here with its failure, so none of them is reached for again
on the assumption it was never considered.

### 5.1 Embedding the private key in the library

**Proposed:** encrypt the private key and ship it inside the code, so signing works with nobody at
the keyboard.

**Why it fails.** For the library to sign unattended, the library must be able to decrypt the key
unattended, so whatever unlocks it ships alongside it. The result is obfuscation and not encryption.
An attacker holding the artifact runs offline with unlimited time and unlimited attempts, and the
target is the passphrase and never the 4096-bit modulus.

**What it costs when it fails.** The holder can sign anything as Douglas Quigg
<dquigg123@gmail.com>, with any date, forever. Every signature already made becomes deniable,
because a forgery is indistinguishable from a genuine signature by construction. Revocation
withdraws future trust and un-signs nothing, and a key committed once is in every clone and every
archive from then on.

The claim in section 3 depends on the key being held by one person. A shipped key removes the
authorship claim entirely, and it removes it retroactively.

### 5.2 A passphrase in an answer file

**Proposed:** an answer file directory holding the passphrase, so signing is unattended.

**Why it fails.** Identical to 5.1 with an extra step. Any process on the machine can then sign as
him. Section 6 has the version of the answer-file idea that works: it holds the digests awaiting
signature, and never the passphrase.

### 5.3 The key in a chain transaction

**Proposed:** put the key in a Bitcoin status message so it stays available.

**Why it fails.** This is 5.1 published to the most permanent medium that exists. Bitcoin is
immutable and globally replicated by design, so there is no deletion, no expiry and no
jurisdiction to appeal to. An encrypted key on chain is a fixed target that every future attacker
can grind against with better hardware than exists today, and the grinding is invisible.

**The instinct is right and the payload is wrong.** Putting something in the chain to make it
permanent and undeniable is the correct move, and section 3 is that move. Publish the digest.
Publish the public key. The private key goes nowhere.

### 5.4 The IP address and MAC as a provenance print

**Proposed:** record the machine's address so the work traces to a physical location and nobody can
claim precedence.

**Why it fails on its own terms.** A MAC address is a software setting and is changed with one
command. An IP address records whatever the path presented at the time and is not attached to a
person. Neither is evidence about *when*, and priority turns on when, so neither competes with a
chain anchor or an archive record.

**And it costs something.** It publishes the home network's identity to every reader of the artifact,
permanently, in exchange for a claim that a chain anchor already makes better. A dated record from a
third party outweighs a self-reported hardware address in any forum where the question is settled.

## 6. The Signing Queue

The answer-file idea, in the form that is safe and still saves the work.

```
maint/signing/
  pending.tsv        digests computed and awaiting a signature, one row per artifact
  signed.tsv         digests whose signature is in place, with the signature's own digest
  sign.ps1           one command, run by a person, that signs pending.tsv
  verify.py          checks every signature against the public key, and needs no secret
```

The division of labour is the point. Computing digests, assembling the queue, checking that every
listed file is present and unchanged, and verifying signatures after the fact are all keyless, so
they run unattended and on any machine. Signing is one command over one small file, run by the
person holding the key, with the passphrase going to the gpg agent's own prompt and never through a
file, an argument, an environment variable or a log.

**The two commands, for the record.**

```
gpg --detach-sign --armor --local-user E603975E472D00FE maint/signing/pending.tsv
ots stamp maint/signing/pending.tsv.asc
```

The first is authorship and needs him. The second is priority and needs nobody. Verification of both
needs nobody.

## 7. Losing The Key

The real answer to *what if I go headless*, since the proposals in section 5 were all aimed at this.

* **A revocation certificate, generated now, stored apart from the key.** Without one, a lost key
  cannot be retired and its identity stays live indefinitely.
* **A paper or metal backup of the secret key, offline, in a separate physical location.** This is
  the standard practice and it is not exotic.
* **Everything in sections 2 to 4 keeps verifying with the key gone.** Signatures already made
  verify against the published public key forever. Chain anchors verify against the chain forever.
  Archive records stand on their own. A lost key stops new attestations and invalidates none of the
  old ones.

The work is protected by records that are already published, and not by the key's continued
availability. That inversion lets the design survive its author.

## 8. Owed

* `maint/signing/` is specified above and not built. Nothing in it needs a secret, so it can be
  built and run unattended once the shell is available again.
* OpenTimestamps is not installed. It is a Python package and a small one.
* The public key is not yet published to a keyserver or committed to the repository.
* No revocation certificate exists.
