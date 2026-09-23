"""Fetch block headers WITH the pool that mined them, as a labelled KAT corpus.

`fetch_blocks.py` keeps the header fields and drops everything else, which is right for verifying
hashes and wrong for asking who produced them. Pool attribution is not in the header at all: it
lives in the coinbase transaction's tag, in plaintext, and the explorer resolves that tag against a
public list of known pool signatures. This keeps the resolved name alongside the header.

The distinction matters for what the corpus can answer. Without labels, an emitter has to be
inferred from the header itself, and an inference that fails leaves you unable to say whether the
signature is absent or whether the inference was bad. With labels the question is supervised: given
the pool, do named pools separate on header fields at all?

Read only. Hits mempool.space's public API, which needs no key and carries no account data. The
header fields are kept so the corpus stays self-verifying: every block can still be rebuilt and
hashed against its recorded id without trusting the explorer.

Note that the label is the explorer's attribution, not a fact carried by the chain. A pool that
does not tag its coinbase, or tags it in a way the list does not know, is reported as unknown. That
is a property of the labelling and the analysis has to allow for it.

    python maint/chain/fetch_labelled.py
    python maint/chain/fetch_labelled.py --blocks 4000

Output: one JSON array at maint/chain/blocks_labelled.json, newest first.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://mempool.space/api"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "blocks_labelled.json")


def get(path, attempts=4):
    """GET a path, retrying on transient failure with a widening pause."""
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(
                API + path, headers={"User-Agent": "BTC-kat/0.1"})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode())
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as error:
            if attempt == attempts - 1:
                raise
            time.sleep(2 * (attempt + 1))
    return None


def pool_of(block):
    """The explorer's attribution for this block, or None where it could not resolve one."""
    extras = block.get("extras") or {}
    pool = extras.get("pool") or {}
    name = pool.get("name")
    return name if name else None


def main():
    parser = argparse.ArgumentParser(description="Fetch labelled block headers.")
    parser.add_argument("--blocks", type=int, default=2000,
                        help="how many blocks to collect, newest first. Default 2000.")
    given = parser.parse_args()

    tip = get("/blocks/tip/height")
    print("[*] chain tip height %d" % tip, flush=True)

    collected = {}
    height = tip
    unlabelled = 0

    # /v1/blocks/:height returns that block and the fourteen below it, so this walks down in strides.
    while len(collected) < given.blocks and height > 0:
        try:
            batch = get("/v1/blocks/%d" % height)
        except Exception as error:
            print("[!] failed at height %d: %s" % (height, error), flush=True)
            break
        if not batch:
            break

        for block in batch:
            name = pool_of(block)
            if name is None:
                unlabelled += 1
            collected[block["height"]] = {
                "height": block["height"],
                "id": block["id"],
                "version": block["version"],
                "previousblockhash": block.get("previousblockhash"),
                "merkle_root": block["merkle_root"],
                "timestamp": block["timestamp"],
                "bits": block["bits"],
                "nonce": block["nonce"],
                "difficulty": block.get("difficulty"),
                "pool": name,
            }

        lowest = min(block["height"] for block in batch)
        height = lowest - 1
        if len(collected) % 300 < 15:
            print("[*] %d blocks, down to height %d" % (len(collected), lowest), flush=True)
        time.sleep(0.12)

    ordered = [collected[key] for key in sorted(collected, reverse=True)][:given.blocks]
    ordered = [block for block in ordered if block["previousblockhash"]]

    with open(OUT, "w") as handle:
        json.dump(ordered, handle, indent=1)

    if not ordered:
        print("[!] nothing collected", flush=True)
        return 1

    named = {}
    for block in ordered:
        key = block["pool"] or "(unattributed)"
        named[key] = named.get(key, 0) + 1

    print("[+] wrote %d blocks to %s" % (len(ordered), OUT), flush=True)
    print("    heights %d .. %d" % (ordered[-1]["height"], ordered[0]["height"]), flush=True)
    print("    %d distinct pool labels" % len(named), flush=True)
    for name, count in sorted(named.items(), key=lambda kv: -kv[1])[:14]:
        print("      %-26s %5d" % (name, count), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
