#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out what the public part of the novel collection will serve, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/philologic_probe.py
#
# The collection splits into a public part and a restricted one, which is what a shelf of novels still in
# copyright has to look like. The public part is everything published before 1923 and is out of copyright,
# and it is served by a search system that answers in a machine readable form.
#
# What is needed for the question is several works by each of several writers, with the language held
# fixed so only the writer changes. So the first thing to ask is what the collection holds and how it is
# indexed, and whether a work can be had whole or only searched inside. Nothing is downloaded here.

import io
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}
BASE = "https://artflsrv04.uchicago.edu/philologic5/chicago_novel_corpus_pre1923"

TRIES = (
    ("what the database says of itself", "/reports/bibliography.py?report=bibliography&format=json"),
    ("its stated shape", "/scripts/get_table_of_contents.py"),
    ("a listing of works", "/reports/bibliography.py?report=bibliography&format=json&start=0&end=5"),
    ("what fields it indexes", "/scripts/get_term_list.py?field=author&query=a*"),
)


def ask(url):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read(300000), response.geturl()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for label, path in TRIES:
        url = BASE + path
        out.write("  %s\n      %s\n" % (label, path[:100]))
        try:
            blob, final = ask(url)
        except urllib.error.HTTPError as refused:
            out.write("      refused with %s\n\n" % refused.code)
            continue
        except Exception as trouble:
            out.write("      failed: %s\n\n" % str(trouble)[:90])
            continue

        text = blob.decode("utf-8", errors="replace")
        out.write("      answered with %d bytes\n" % len(blob))
        try:
            payload = json.loads(text)
        except Exception:
            out.write("      not machine readable, begins: %s\n\n" % text[:200].replace("\n", " "))
            continue

        if isinstance(payload, dict):
            out.write("      keys: %s\n" % ", ".join(sorted(payload)[:18]))
            results = payload.get("results")
            if isinstance(results, list) and results:
                out.write("      %d results, first one carries: %s\n"
                          % (len(results), ", ".join(sorted(results[0])[:18])))
                first = results[0]
                for key in sorted(first)[:12]:
                    out.write("        %-18s %s\n" % (key, str(first[key])[:80]))
            for key in ("results_length", "total_results", "doc_count"):
                if key in payload:
                    out.write("      %s: %s\n" % (key, payload[key]))
        out.write("\n")
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
