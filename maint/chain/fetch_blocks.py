"""Fetch recent block headers from a public explorer and write them as a KAT corpus.

Read only. Hits mempool.space's public API, which needs no key and carries no account data. Each
response gives the fields a header is built from, so the corpus can be verified offline afterwards
without trusting the explorer's own hash: we rebuild the 80 byte header, hash it ourselves, and
compare against the id the explorer reported. A disagreement means either our algorithm or their
record is wrong, and the test says which.

Output: one JSON array at tools/blocks.json, newest first.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://mempool.space/api"
WANTED = 1000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocks.json")


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


def main():
    tip = get("/blocks/tip/height")
    print(f"[*] chain tip height {tip}", flush=True)

    collected = {}
    height = tip

    # /v1/blocks/:height returns that block and the 14 below it, so this walks down in strides.
    while len(collected) < WANTED and height > 0:
        try:
            batch = get(f"/v1/blocks/{height}")
        except Exception as error:
            print(f"[!] failed at height {height}: {error}", flush=True)
            break
        if not batch:
            break

        for block in batch:
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
            }

        lowest = min(block["height"] for block in batch)
        height = lowest - 1
        if len(collected) % 150 < 15:
            print(f"[*] {len(collected)} blocks, down to height {lowest}", flush=True)
        time.sleep(0.12)

    ordered = [collected[key] for key in sorted(collected, reverse=True)][:WANTED]
    # A block whose parent hash is missing cannot be chain-linked by the verifier, so drop it here
    # instead of letting it look like a hashing failure later.
    ordered = [block for block in ordered if block["previousblockhash"]]

    with open(OUT, "w") as handle:
        json.dump(ordered, handle, indent=1)

    if ordered:
        print(f"[+] wrote {len(ordered)} blocks to {OUT}", flush=True)
        print(f"    heights {ordered[-1]['height']} .. {ordered[0]['height']}", flush=True)
    else:
        print("[!] nothing collected", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
