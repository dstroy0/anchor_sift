#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score this project's prose for machine register against a language model, and fail on anything
# that reads as machine written.
#
#   python maint/prose/api_gate.py --dry-run theory   what would be sent, and how much of it
#   python maint/prose/api_gate.py theory/millennium  score one book
#   python maint/prose/api_gate.py --bar 0.40 docs    score with the bar drawn somewhere else
#
# WHAT THIS ADDS TO docs_check
#
# docs_check.py holds 303 patterns, and every one of them was added here after somebody read a
# finding and wrote the phrase down. That loop cannot reach a habit nobody has noticed yet, and the
# list grows only as fast as somebody notices. This reads the passage whole and reports the register
# it carries, including phrases that are on no list.
#
# The two do not substitute for each other. docs_check names a token and a line and a writer can act
# on it directly. This returns a judgement, and a judgement has to be checked before it is acted on.
# Quoting one as the other is the error this project already made three times with its own two
# measures.
#
# THIS IS NOT AN INDEPENDENT WITNESS
#
# Stated here because the number looks like one. A model asked to score prose for machine register
# is being asked about its own output distribution, which is the library as its own oracle: precept
# one in this project's testing rules. An expectation derived from the thing under test proves
# nothing and passes forever.
#
# So a low score here is not evidence of anything. A high score is, because the instrument had every
# reason to return the opposite. Read the findings and never the passes.
#
# NO CREDENTIAL AND NO VENDOR IN THIS FILE
#
# The endpoint, the model name and the environment variable holding the key are read from
# ~/.config/prose_api.json or from the path in PROSE_API_CONFIG. None of the three is written here.
# A key committed once is a key in every clone, and a vendor name in a tracked file is a claim about
# this project that this project does not make.
#
#   {"endpoint": "...", "model": "...", "key_env": "NAME_OF_THE_VARIABLE", "extra_headers": {}}
#
# WHAT IT REFUSES TO SEND
#
# Sending text to an outside service publishes that text. The closed corpus and the private
# repositories beside this one never go, and there is no flag to make them. The hand extractions are
# the published papers' text and the speakers' words, and neither is this project's to hand over.
# docs_check reads them because that scan runs on this machine. This one does not run here.
#
# THE BAR IS DRAWN, NOT DERIVED
#
# 0.50. Fitting a bar to this tree would set it to whatever this tree already scores, and a bar
# placed that way passes the tree by construction. A threshold reasoned out of a distribution
# carries every variance source somebody forgot, and those all push one direction.

import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import docs_check

CONFIG = os.environ.get("PROSE_API_CONFIG") or os.path.join(
    os.path.expanduser("~"), ".config", "prose_api.json")

BAR = 0.50

# Characters per request. A whole book in one request gets one number for sixty pages, and a number
# that coarse names nothing a writer can repair.
CHUNK = 6000

# Under this a passage carries too little to read. Reported as unscored, never as a pass.
FLOOR = 400

TIMEOUT = 120

CLOSED = ("/private_repos/", "/salishan_corpus/", "/anchor_sift_citations/", "/no_replicate_/")

ASK = (
    "You are grading a passage of technical prose for one property only: whether it reads as "
    "written by a language model.\n\n"
    "Mark the register, not the subject. Dense, unusual, or difficult writing by a person is "
    "human. What marks a machine is the shape: balanced antithesis (X, not Y), a colon followed "
    "by elaboration, hedged summary clauses, inanimate things that speak or signal, tidy triples, "
    "reassuring wrap-up sentences, and phrases that carry rhythm without carrying a fact.\n\n"
    "Return only JSON, no other text:\n"
    '{\"score\": <0.0 to 1.0>, \"phrases\": [{\"text\": \"<exact quote from the passage>\", '
    '\"why\": \"<six words or fewer>\"}]}\n\n'
    "score is the probability the passage was machine written. Quote at most six phrases and "
    "quote them exactly as they appear, so they can be found in the file. Return an empty list "
    "where the passage reads as human.\n\n"
    "PASSAGE:\n"
)


def config():
    """Endpoint, model, key and headers, from the local file outside this tree."""
    if not os.path.isfile(CONFIG):
        raise SystemExit(
            "  api_gate: no config at %s\n"
            "  Write it with endpoint, model and key_env. Nothing here reads a key out of the\n"
            "  repository and nothing writes one into it." % CONFIG)
    with open(CONFIG, encoding="utf-8") as handle:
        held = json.load(handle)
    for name in ("endpoint", "model", "key_env"):
        if not held.get(name):
            raise SystemExit("  api_gate: %s is missing from %s" % (name, CONFIG))
    key = os.environ.get(held["key_env"])
    if not key:
        raise SystemExit("  api_gate: %s names an environment variable that is not set"
                         % held["key_env"])
    return held, key


def closed(path):
    """Whether a path belongs to the closed corpus or a private repository beside this one."""
    walk = os.path.abspath(path).replace("\\", "/")
    return any(one in walk for one in CLOSED)


def body(path):
    """One file's prose as (text, offsets), offsets[i] holding the source line of character i.

    The extraction is docs_check's, so both gates read the same words. A .tex arrives with its
    markup blanked, a source file with its code blanked, and a page as itself.
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


def ask(passage, held, key):
    """One request. Returns the parsed judgement, or raises SystemExit naming what went wrong."""
    payload = {
        "model": held["model"],
        "max_tokens": 900,
        "messages": [{"role": "user", "content": ASK + passage}],
    }
    headers = {"content-type": "application/json", "authorization": "Bearer " + key}
    headers.update(held.get("extra_headers") or {})
    request = urllib.request.Request(held["endpoint"],
                                     data=json.dumps(payload).encode("utf-8"),
                                     headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as handle:
            answer = json.loads(handle.read().decode("utf-8"))
    except urllib.error.HTTPError as failed:
        detail = failed.read().decode("utf-8", "replace")[:400]
        raise SystemExit("  api_gate: HTTP %d. %s" % (failed.code, detail))
    except urllib.error.URLError as failed:
        raise SystemExit("  api_gate: the endpoint could not be reached. %s" % failed.reason)

    text = ""
    for part in answer.get("content") or []:
        if isinstance(part, dict) and part.get("type") == "text":
            text += part.get("text", "")
    text = text.strip()
    opens = text.find("{")
    closes = text.rfind("}")
    if opens < 0 or closes < opens:
        raise SystemExit("  api_gate: the endpoint returned no judgement. %s" % text[:200])
    return json.loads(text[opens:closes + 1])


def main():
    argv = sys.argv[1:]
    dry = "--dry-run" in argv
    bar = BAR
    if "--bar" in argv:
        at = argv.index("--bar")
        if (at + 1) >= len(argv):
            raise SystemExit("  api_gate: --bar wants a number between 0 and 1")
        bar = float(argv[at + 1])

    skip = {"--dry-run", "--bar", str(bar)}
    named = [one for one in argv if (one not in skip) and not one.startswith("-")]
    if not named:
        raise SystemExit("  api_gate: name a file or a directory. There is no default root, "
                         "because the whole tree is more prose than one run should send.")

    roots = [one if os.path.exists(one) else os.path.join(docs_check.REPOSITORY, one)
             for one in named]

    refused = []
    reading = []
    for path in sorted(docs_check.walk_markdown(roots)):
        if closed(path):
            refused.append(path)
            continue
        text, offsets = body(path)
        reading.append((path, text, offsets))

    for path in refused:
        print("  NOT SENT  %s" % os.path.relpath(path, docs_check.REPOSITORY).replace("\\", "/"))
    if refused:
        print("  %d file(s) held back. The closed corpus does not go to an outside service.\n"
              % len(refused))

    want = sum(len(text) for _path, text, _offsets in reading if len(text) >= FLOOR)
    short = sum(1 for one in reading if len(one[1]) < FLOOR)
    requests = sum(len(chunks(text)) for _path, text, _offsets in reading if len(text) >= FLOOR)
    print("  %d file(s) to score, %d too short, %d characters in %d request(s)"
          % (len(reading) - short, short, want, requests))

    if dry:
        print("  --dry-run, nothing was sent")
        return 0

    held, key = config()

    over = 0
    scored = 0
    for path, text, offsets in reading:
        shown = os.path.relpath(path, docs_check.REPOSITORY).replace("\\", "/")
        if len(text) < FLOOR:
            print("  short %s: %d characters, under the %d floor, not scored"
                  % (shown, len(text), FLOOR))
            continue

        total = 0.0
        weight = 0
        phrases = []
        for piece in chunks(text):
            judged = ask(piece, held, key)
            total += float(judged.get("score", 0.0)) * len(piece)
            weight += len(piece)
            for one in judged.get("phrases") or []:
                quote = (one.get("text") or "").strip()
                if not quote:
                    continue
                at = text.find(quote)
                line = offsets[at] if (0 <= at < len(offsets)) else 0
                phrases.append((line, quote, (one.get("why") or "").strip()))
        score = (total / weight) if weight else 0.0
        scored += 1

        mark = "OVER " if score >= bar else "     "
        print("  %s %s: %.2f over %d characters" % (mark, shown, score, len(text)))
        for line, quote, why in sorted(phrases):
            print("        %s:%d  %s   (%s)" % (shown, line, quote[:90], why))

        if score >= bar:
            over += 1

    print("\n  %d file(s) scored, %d at or over %.2f" % (scored, over, bar))
    if scored == 0:
        print("  Nothing was scored, so nothing passed.")
        return 2
    return 1 if over else 0


if __name__ == "__main__":
    raise SystemExit(main())
