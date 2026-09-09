# Whose words these are

**Purpose:** Say whose language this corpus holds and where the tables are kept, for a reader who came looking for them here.
**Scope:** the closed Salishan corpus, and `tools/maintain/private_sync.py`, which brings it into a checkout.

These languages belong to the people who speak them. None of this work exists without them, and the conditions the speakers set are recorded per table and hold wherever this corpus is used.

## Where the tables are

Twenty tables, 12,338 rows, read off published papers by hand. Every row is a form transcribed out of somebody's paper, so the tables are those papers' text and not this work's to redistribute. They are held in a closed repository along with the papers themselves, and go to anyone who has the papers and asks.

The speaker list, table by table, opens the Salishan book:

```sh
sh tools/book/build_theory.sh Salishan
```

That chapter is written from `corpus_script_extraction/paper_config.py`, the only place a speaker's name is typed.

## Reaching them from a checkout

```sh
python tools/maintain/private_sync.py
```

The tables land in `build/oracles` and the papers in `build/papers`, each one checked against the SHA-256 recorded in the corpus inventory. A clean run means the bytes under `build/` are the bytes the corpus owner signed. Point `ANCHOR_SIFT_PRIVATE` at the corpus if it does not sit beside this checkout.

Everything here that does not read a paper or a table runs without it.

## What stays in the open

The derivations. The ledger, the bound on how wrong the corpus could be, the checks, and the code are all in this repository, and they are what the work has to say. The tables are the evidence those numbers were measured over. The inventory publishes a hash of each one, which ties a figure here to exact bytes without republishing them.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
