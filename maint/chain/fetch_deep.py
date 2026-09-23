"""Fetch a deep header corpus, for the integration the shallow one cannot support.

A thousand blocks is seven days. Header statistics - pool conventions, clock offsets - are
stationary over far longer than that, so they are exactly the case where integrating longer pays:
the estimate sharpens as the square root of the count for as long as the thing being measured holds
still, and firmware conventions hold still for months.

Two leads came out of the thousand-block corpus below the bar and neither can be settled there:

    blocks whose timestamp reverses carry a lower rolled version   -2.09 sd
    the shape of the clock-offset population                        31 reversals is too few

Twenty thousand blocks is twenty times the count, so a real effect grows by the square root of
twenty, about 4.5, and a spurious one does not. That is the whole design: the same statistic, more
of it, and the two outcomes are not alike.

Read only, and self-verifying: every header field is kept so a block can be rebuilt and hashed
against its own recorded id without trusting the source.

    python maint/chain/fetch_deep.py
    python maint/chain/fetch_deep.py --blocks 50000

Output: one JSON array at maint/chain/blocks_deep.json, newest first.
"""

import argparse
import json
import os
import time
import urllib.error
import urllib.request

API = "https://blockstream.info/api"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "blocks_deep.json")

KEEP = ("height", "id", "version", "previousblockhash", "merkle_root",
        "timestamp", "bits", "nonce", "difficulty", "mediantime")


def get(path, attempts=6):
    """GET a path, retrying on transient failure with a widening pause.

    A 429 is not a transient failure, it is the server asking for less. It gets its own much longer
    pause, because retrying a rate limit at the same cadence that caused it only earns another one.
    The first run of this fetcher stopped at 6980 blocks by treating a 429 as an ordinary error.
    """
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(
                API + path, headers={"User-Agent": "Mozilla/5.0 BTC-kat/0.1"})
            with urllib.request.urlopen(request, timeout=25) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as error:
            if error.code == 429:
                pause = 30 * (attempt + 1)
                print("[~] rate limited, waiting %ds" % pause, flush=True)
                time.sleep(pause)
                continue
            if attempt == attempts - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
        except (urllib.error.URLError, TimeoutError):
            if attempt == attempts - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
    return None


def main():
    parser = argparse.ArgumentParser(description="Fetch a deep header corpus.")
    parser.add_argument("--blocks", type=int, default=20000)
    parser.add_argument("--from-height", type=int, default=0,
                        help="start walking down from this height instead of the tip, for "
                             "fetching a historical window such as the 2021 migration.")
    parser.add_argument("--pause", type=float, default=0.35,
                        help="seconds between requests. Raise it if the source rate limits.")
    parser.add_argument("--out", default=OUT,
                        help="where to write, so a historical window does not overwrite the "
                             "recent corpus.")
    given = parser.parse_args()

    tip = int(get("/blocks/tip/height"))
    start = given.from_height if given.from_height else tip
    print("[*] chain tip %d, walking down from %d, collecting %d"
          % (tip, start, given.blocks), flush=True)

    collected = {}
    height = start
    started = time.time()
    misses = 0

    # /blocks/:start_height returns that block and the nine below it.
    while len(collected) < given.blocks and height > 0:
        try:
            batch = get("/blocks/%d" % height)
        except Exception as error:
            misses += 1
            print("[!] failed at height %d: %s" % (height, str(error)[:60]), flush=True)
            if misses > 12:
                print("[!] too many failures, stopping with what is collected", flush=True)
                break
            height -= 10
            continue
        if not batch:
            break

        for block in batch:
            collected[block["height"]] = {key: block.get(key) for key in KEEP}

        lowest = min(block["height"] for block in batch)
        height = lowest - 1
        # The first run had no pause here at all, which is what earned the rate limit at 6980.
        time.sleep(given.pause)
        if len(collected) % 2000 < 10:
            rate = len(collected) / max(time.time() - started, 1e-9)
            print("[*] %6d blocks, at height %d, %.0f/s" % (len(collected), lowest, rate),
                  flush=True)

    ordered = [collected[key] for key in sorted(collected, reverse=True)]
    ordered = [block for block in ordered if block["previousblockhash"]]

    with open(given.out, "w") as handle:
        json.dump(ordered, handle, separators=(",", ":"))

    if not ordered:
        print("[!] nothing collected", flush=True)
        return 1
    print("[+] wrote %d blocks to %s (%.1f MB)"
          % (len(ordered), given.out, os.path.getsize(given.out) / 1048576.0), flush=True)
    print("    heights %d .. %d" % (ordered[-1]["height"], ordered[0]["height"]), flush=True)
    print("    span %.1f days" % ((ordered[0]["timestamp"] - ordered[-1]["timestamp"]) / 86400.0),
          flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
