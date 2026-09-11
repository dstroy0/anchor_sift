#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score this project's prose with an outside machine-text detector and fail on anything that reads
# as machine written.
#
#   python maint/prose/ai_detect.py --dry-run theory    what would be sent, and what it costs
#   python maint/prose/ai_detect.py theory/millennium   score one book
#   python maint/prose/ai_detect.py --bar 0.40 docs     score with the bar drawn somewhere else
#
# WHY AN OUTSIDE DETECTOR AT ALL
#
# docs_check.py was written in this repository, so it finds what somebody here already knew to ban.
# Its 303 patterns came from reading findings and adding the phrase that produced them, and that
# loop cannot reach a habit nobody has noticed yet. A detector trained somewhere else reads this
# prose without anybody here having tuned it.
#
# The two instruments disagree usefully. docs_check names a token and a line, and a writer can act
# on that. This returns a number over a whole file and cannot say what produced it.
# Neither replaces the other, and quoting one as the other is the error this project has already
# made three times with its own two measures.
#
# THE KEY IS NEVER IN THIS TREE
#
# Read from SAPLING_API_KEY, from the file named by SAPLING_API_KEY_FILE, or from
# ~/.claude/sapling.key. A key committed once is a key in every clone and in every archive built
# from one. Nothing here writes it, prints it, logs it, or puts it in a URL.
#
# WHAT IT REFUSES TO SEND
#
# Sending text to an outside service publishes that text. Two classes never leave this machine.
#
# The closed corpus and the private repositories beside this one. The hand extractions are the
# published papers' text and not this project's to redistribute, and the speakers' words are not
# this project's either. docs_check scans them because that scan runs locally. This one does not,
# and there is no flag to make it.
#
# Anything the run was not pointed at. Every path is printed before a single request goes out, and
# --dry-run stops at that point.
#
# THE BAR IS DRAWN, NOT DERIVED
#
# 0.50, the detector's own midpoint. It was not fitted to this tree. Fitting it here would set it to
# whatever this tree already scores, and a bar placed that way passes the tree by construction. A
# threshold reasoned out of a distribution carries every variance source somebody forgot, and those
# all push the same direction.
#
# THE BUDGET IS DRAWN TOO
#
# The free quota is 50,000 characters a day and 250,000 a month. This tree holds much more prose
# than that. A run over all of it cannot happen quietly. A run that would exceed
# the budget refuses to start and prints the overage. It never sends a part of what it was asked for
# and reports that as the answer: a partial scan presented as a scan is the failure mode this file
# exists to prevent.

import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import docs_check

ENDPOINT = "https://api.sapling.ai/api/v1/aidetect"

# Pinned. The detector's default moves when the vendor retrains, and a score that moves for that
# reason would read here as prose that changed. Bump this deliberately and rescore everything.
VERSION = "20251027"

# The detector's own midpoint. See the header on why this is not fitted to this tree.
BAR = 0.50

# Characters one run may send. Drawn under the 50,000 daily free quota with room for a second run
# the same day after a repair.
BUDGET = 40000

# The vendor accepts 200,000 characters per request and recommends at least 300. Below the floor a
# file is reported as too short to score, and calling that a pass would be a reading nobody took.
CHUNK = 20000
FLOOR = 300

# Seconds. A commit hook that hangs on a request costs more than one that refuses.
TIMEOUT = 60

# Responses, keyed by the hash of the exact text sent and the version that scored it. Under build/
# because it is disposable and nothing irreplaceable is reachable through it.
CACHE = os.path.join(docs_check.REPOSITORY, "build", "ai_detect")

# What never goes to an outside service. Matched against the absolute path with forward slashes.
CLOSED = ("/private_repos/", "/salishan_corpus/", "/anchor_sift_citations/", "/no_replicate_/")


def api_key():
    """The key, from the environment or from a file outside this tree. None where none is set."""
    held = os.environ.get("SAPLING_API_KEY")
    if held and held.strip():
        return held.strip()
    named = os.environ.get("SAPLING_API_KEY_FILE")
    for path in (named, os.path.join(os.path.expanduser("~"), ".claude", "sapling.key")):
        if path and os.path.isfile(path):
            with open(path, encoding="ascii", errors="replace") as handle:
                held = handle.read().strip()
            if held:
                return held
    return None


def closed(path):
    """Whether a path belongs to the closed corpus or a private repository beside this one."""
    walk = os.path.abspath(path).replace("\\", "/")
    return any(one in walk for one in CLOSED)


def body(path):
    """One file's prose as (text, offsets), offsets[i] holding the source line of character i.

    The extraction is docs_check's, so both instruments read the same words. A .tex arrives with its
    markup blanked, a source file with its code blanked, and a page as itself. Runs are joined the
    way docs_check joins them, since a sentence wrapped across two lines is one sentence.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    said = docs_check.prose_only(path, lines)

    held = []
    offsets = []
    for text, where in docs_check.runs(said):
        if held:
            held.append("\n\n")
            offsets.extend([where[0]] * 2)
        held.append(text)
        offsets.extend(where)
    return "".join(held), offsets


def chunks(text):
    """The text split for the request limit, cut at a paragraph break where one is near enough."""
    held = []
    at = 0
    while at < len(text):
        stop = min(at + CHUNK, len(text))
        if stop < len(text):
            broke = text.rfind("\n\n", at + (CHUNK // 2), stop)
            if broke > at:
                stop = broke
        held.append(text[at:stop])
        at = stop
    return held


def cached(text):
    """The stored response for this exact text, or None."""
    digest = hashlib.sha256(("%s\n%s" % (VERSION, text)).encode("utf-8")).hexdigest()
    path = os.path.join(CACHE, digest + ".json")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    return None


def store(text, answer):
    digest = hashlib.sha256(("%s\n%s" % (VERSION, text)).encode("utf-8")).hexdigest()
    os.makedirs(CACHE, exist_ok=True)
    with open(os.path.join(CACHE, digest + ".json"), "w", encoding="utf-8") as handle:
        json.dump(answer, handle)


def detect(text, key):
    """One request. Returns the parsed response, or raises SystemExit naming what went wrong."""
    held = cached(text)
    if held is not None:
        return held, 0

    payload = json.dumps({"key": key, "text": text,
                          "sent_scores": True, "version": VERSION}).encode("utf-8")
    request = urllib.request.Request(ENDPOINT, data=payload,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as handle:
            answer = json.loads(handle.read().decode("utf-8"))
    except urllib.error.HTTPError as failed:
        detail = failed.read().decode("utf-8", "replace")[:300]
        if failed.code == 429:
            raise SystemExit("  ai_detect: quota or rate limit reached. %s" % detail)
        raise SystemExit("  ai_detect: HTTP %d from the detector. %s" % (failed.code, detail))
    except urllib.error.URLError as failed:
        raise SystemExit("  ai_detect: the detector could not be reached. %s" % failed.reason)

    store(text, answer)
    return answer, len(text)


def worst(answer, text, offsets, how_many=4):
    """The highest scoring sentences, as (score, line number, sentence)."""
    held = []
    for one in answer.get("sentence_scores") or []:
        sentence = (one.get("sentence") or "").strip()
        if not sentence:
            continue
        at = text.find(sentence)
        line = offsets[at] if (0 <= at < len(offsets)) else 0
        held.append((float(one.get("score", 0.0)), line, sentence))
    held.sort(reverse=True)
    return held[:how_many]


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    bar = BAR
    if "--bar" in argv:
        at = argv.index("--bar")
        if (at + 1) >= len(argv):
            raise SystemExit("  ai_detect: --bar wants a number between 0 and 1")
        bar = float(argv[at + 1])
    budget = BUDGET
    if "--budget" in argv:
        at = argv.index("--budget")
        if (at + 1) >= len(argv):
            raise SystemExit("  ai_detect: --budget wants a character count")
        budget = int(argv[at + 1])

    skip = {"--dry-run", "--bar", "--budget", str(bar), str(budget)}
    named = [one for one in argv if (one not in skip) and not one.startswith("-")]
    if not named:
        raise SystemExit("  ai_detect: name a file or a directory. There is no default root, "
                         "because the whole tree is larger than a day's quota.")

    roots = []
    for one in named:
        roots.append(one if os.path.exists(one) else os.path.join(docs_check.REPOSITORY, one))

    refused = []
    reading = []
    for path in sorted(docs_check.walk_markdown(roots)):
        if closed(path):
            refused.append(path)
            continue
        text, offsets = body(path)
        if len(text) < FLOOR:
            reading.append((path, text, offsets, "short"))
            continue
        reading.append((path, text, offsets, "score"))

    for path in refused:
        print("  NOT SENT  %s" % os.path.relpath(path, docs_check.REPOSITORY).replace("\\", "/"))
    if refused:
        print("  %d file(s) held back. The closed corpus does not go to an outside service.\n"
              % len(refused))

    want = sum(len(text) for _path, text, _offsets, kind in reading if kind == "score")
    short = sum(1 for one in reading if one[3] == "short")
    print("  %d file(s) to score, %d too short to score, %d characters to send"
          % (len(reading) - short, short, want))

    if dry:
        print("  --dry-run, nothing was sent")
        return 0

    if want > budget:
        print("  ai_detect: %d characters is over the %d budget by %d. Nothing was sent."
              % (want, budget, want - budget))
        print("  Name fewer files, or raise it with --budget once the quota can carry it.")
        return 2

    key = api_key()
    if not key:
        print("  ai_detect: no key. Set SAPLING_API_KEY, or put it in ~/.claude/sapling.key.")
        print("  Nothing here reads a key out of the repository and nothing writes one into it.")
        return 2

    over = 0
    scored = 0
    sent = 0
    for path, text, offsets, kind in reading:
        shown = os.path.relpath(path, docs_check.REPOSITORY).replace("\\", "/")
        if kind == "short":
            print("  short %s: %d characters, under the %d floor, not scored" % (shown, len(text),
                                                                                 FLOOR))
            continue

        pieces = chunks(text)
        total = 0.0
        weight = 0
        lines = []
        for piece in pieces:
            answer, billed = detect(piece, key)
            sent += billed
            total += float(answer.get("score", 0.0)) * len(piece)
            weight += len(piece)
            lines.extend(worst(answer, text, offsets))
        score = (total / weight) if weight else 0.0
        scored += 1

        mark = "OVER " if score >= bar else "     "
        print("  %s %s: %.2f over %d characters" % (mark, shown, score, len(text)))
        if score >= bar:
            over += 1
            lines.sort(reverse=True)
            for one, at, sentence in lines[:4]:
                print("        %.2f at line %d: %s" % (one, at, sentence[:110]))

    print("\n  %d file(s) scored, %d at or over %.2f, %d characters sent" % (scored, over, bar,
                                                                             sent))
    if scored == 0:
        print("  Nothing was scored, so nothing passed.")
        return 2
    return 1 if over else 0


if __name__ == "__main__":
    raise SystemExit(main())
