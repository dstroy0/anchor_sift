#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Pull text from Common Corpus into build/corpora, for the language measurements in
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_modern_corpora.py [documents per language]
#
# Every English corpus measured so far came from Project Gutenberg, so the collision entropy constant
# of 3.800 bits could belong to that source's formatting instead of to the language. Two of the twelve
# texts already turned out to be layout: their commonest symbol held a quarter of the corpus because
# they were set with short lines. A second source with different conventions is what tests the constant.
#
# The shards are 430 MB of Parquet each and the row data needed is a small fraction of one. Parquet
# carries a footer holding the byte offset of every row group, so an HTTP range reader can fetch the
# footer, then fetch one row group, and skip the rest. That is what HttpRanged exists for.

import io
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")

TREE = "https://huggingface.co/api/datasets/PleIAs/common_corpus/tree/main/common_corpus_1"
BLOB = "https://huggingface.co/datasets/PleIAs/common_corpus/resolve/main/%s"
AGENT = {"User-Agent": "MMgr-research/1.0"}

# Enough symbols for the halving ladder, which needs eight windows of 4096
FLOOR = 8 * 4096


class HttpRanged(io.RawIOBase):
    """A read only file over HTTP, serving seeks with range requests.

    Parquet is read back to front: the footer gives the schema and the offset of each row group, so a
    reader that can seek fetches a few kilobytes of footer and then only the row group it wants. Without
    seeking the whole 430 MB would have to arrive to reach the first row.
    """

    def __init__(self, url):
        self.url = url
        self.position = 0
        request = urllib.request.Request(url, method="HEAD", headers=AGENT)
        with urllib.request.urlopen(request, timeout=120) as response:
            self.length = int(response.headers["Content-Length"])

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET:
            self.position = offset
        elif whence == io.SEEK_CUR:
            self.position += offset
        else:
            self.position = self.length + offset
        return self.position

    def read(self, size=-1):
        if size < 0:
            size = self.length - self.position
        if size <= 0:
            return b""
        last = min(self.length, self.position + size) - 1
        headers = dict(AGENT)
        headers["Range"] = "bytes=%d-%d" % (self.position, last)
        request = urllib.request.Request(self.url, headers=headers)
        with urllib.request.urlopen(request, timeout=180) as response:
            block = response.read()
        self.position += len(block)
        return block

    def readinto(self, buffer):
        block = self.read(len(buffer))
        buffer[:len(block)] = block
        return len(block)


def first_shard():
    request = urllib.request.Request(TREE, headers=AGENT)
    with urllib.request.urlopen(request, timeout=120) as response:
        items = json.load(response)
    for item in items:
        if item.get("path", "").endswith(".parquet"):
            return item["path"]
    return None


def main():
    import pyarrow.parquet as pq

    wanted = int(sys.argv[1]) if len(sys.argv) > 1 else 4000

    path = first_shard()
    if path is None:
        print("no parquet shard listed")
        return 1

    handle = HttpRanged(BLOB % path)
    reader = pq.ParquetFile(handle)
    print("  %s\n  %d row groups, %d rows, columns %s"
          % (path, reader.num_row_groups, reader.metadata.num_rows,
             ", ".join(reader.schema_arrow.names)))

    names = set(reader.schema_arrow.names)
    text_column = "text" if "text" in names else None
    lang_column = None
    for candidate in ("language", "lang", "language_code"):
        if candidate in names:
            lang_column = candidate
            break
    if text_column is None:
        print("  no text column, columns are %s" % ", ".join(sorted(names)))
        return 1

    columns = [text_column] + ([lang_column] if lang_column else [])
    table = reader.read_row_group(0, columns=columns)
    texts = table.column(text_column).to_pylist()
    langs = table.column(lang_column).to_pylist() if lang_column else ["unknown"] * len(texts)

    gathered = {}
    for text, lang in zip(texts, langs):
        if not text:
            continue
        key = str(lang or "unknown").lower()[:12]
        bucket = gathered.setdefault(key, [])
        if sum(len(part) for part in bucket) < wanted * 1000:
            bucket.append(text)

    os.makedirs(OUT, exist_ok=True)
    kept = 0
    for key, parts in sorted(gathered.items()):
        # Line endings are kept. Folding them here would decide, at ingest, that layout is noise, and
        # for a source file it is the authored layer: a language that ignores its own whitespace carries
        # indentation only because a person put it there. Whichever treatment a measurement wants can be
        # applied downstream, where normalize_symbols.py takes keep-layout, and nothing is lost by
        # storing the text as it arrived. Documents are joined by a newline for the same reason.
        body = "\n".join(parts)
        if len(body) < FLOOR:
            continue
        target = os.path.join(OUT, "cc_%s.txt" % key)
        with open(target, "w", encoding="utf-8", newline="") as out:
            out.write(body)
        print("  cc_%-14s %d characters from %d documents" % (key, len(body), len(parts)))
        kept += 1

    print("  %d corpora written" % kept)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
