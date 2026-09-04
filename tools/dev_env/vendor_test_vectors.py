#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Vendor the published SHA-256 test vectors into test/vectors, with a manifest recording where each
# one came from and what it hashes to.
#
# Run this only to fetch or refresh. The committed files are consumed offline by `harness.py
# vectors`, so a run needs no network and the same bytes are tested every time. Refreshing is a
# deliberate act: run this, read the manifest diff, and say why the numbers moved.
#
#   Usage:  python tools/dev_env/vendor_test_vectors.py [--keep-archives]
#
# What lands, and why each is here rather than any other set:
#
#   nist_cavp_sha256{short,long}msg.rsp   the normative one shot tables
#   nist_cavp_sha256monte.rsp             100 checkpoints x 1000 chained rounds, the only published
#                                         case that catches state carried wrongly between blocks
#   nist_cavp_bit_sha256{short,long}msg   Len counts BITS, so most of these do not end on a byte and
#                                         they are the only vectors reaching mmgr_sha256_bits
#   nist_cavp_hmac_sha256.rsp             the [L=32] section, truncated tag lengths included
#   wycheproof_hmac_sha256.json           adversarial: modified tags that must NOT reproduce
#
# Only the SHA-256 parts are kept. The upstream archives carry five hash sizes and the bit oriented
# one is 37 MB; committing vectors for algorithms this tree does not have would be storage without
# evidence.

import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "test", "vectors")
CACHE = os.path.join(ROOT, "build", "vectors-cache")

NIST = "https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents"
BYTE_URL = NIST + "/shs/shabytetestvectors.zip"
BIT_URL = NIST + "/shs/shabittestvectors.zip"
HMAC_URL = NIST + "/mac/hmactestvectors.zip"

# ProtoCore already curated this subset from a pinned Wycheproof commit. Taken from there rather than
# refetched, so both trees test identical bytes and the provenance stays one story.
WYCHEPROOF_FROM = os.path.join(ROOT, "..", "..", "ProtoCore", "test", "vectors", "wycheproof_hmac_sha256.json")


def digest_of(path):
    """The SHA-256 of a file, as the manifest records it."""
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def fetch(url, name):
    """Download an archive into the build container, or reuse one already there."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.isfile(path):
        print("fetching %s" % url)
        # csrc.nist.gov answers 403 to a request with no User-Agent, which urllib omits by default.
        # Measured: the identical URL fetches fine under curl, which sends one.
        request = urllib.request.Request(url, headers={"User-Agent": "MMgr-vendor-test-vectors/1.0"})
        with urllib.request.urlopen(request) as response, open(path, "wb") as handle:
            handle.write(response.read())
    return path, digest_of(path)


def take_members(archive, stamp, url, members, prefix, what, manifest):
    """Copy whole members out of an archive and record each one."""
    zf = zipfile.ZipFile(archive)
    for member, name in members:
        target = os.path.join(OUT, prefix + name)
        with open(target, "wb") as handle:
            handle.write(zf.read(member))
        manifest["files"].append({
            "file": os.path.basename(target),
            "source": url,
            "archive_sha256": stamp,
            "member": member,
            "sha256": digest_of(target),
            "what": what,
        })
        print("  %-38s %s  %d KB"
              % (os.path.basename(target), digest_of(target)[:16], os.path.getsize(target) // 1024))


def take_hmac_section(archive, stamp, manifest):
    """Copy the [L=32] block of HMAC.rsp, which is the SHA-256 one of five hash sizes."""
    whole = zipfile.ZipFile(archive).read("HMAC.rsp").decode("utf-8", "replace")
    kept, taking = [], False
    for raw in whole.splitlines():
        line = raw.strip()
        if line.startswith("[L="):
            taking = (line == "[L=32]")
            if taking:
                kept.append(line)
            continue
        if taking:
            kept.append(raw)

    target = os.path.join(OUT, "nist_cavp_hmac_sha256.rsp")
    header = ("# Extracted from HMAC.rsp, the [L=32] section only, by tools/dev_env/vendor_test_vectors.py\n"
              "# Source %s\n# Archive sha256 %s\n\n" % (HMAC_URL, stamp))
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(header + "\n".join(kept) + "\n")

    manifest["files"].append({
        "file": os.path.basename(target),
        "source": HMAC_URL,
        "archive_sha256": stamp,
        "member": "HMAC.rsp [L=32]",
        "sha256": digest_of(target),
        "what": "NIST CAVP HMAC-SHA-256, truncated tag lengths included",
    })
    print("  %-38s %s  %d KB"
          % (os.path.basename(target), digest_of(target)[:16], os.path.getsize(target) // 1024))


def main():
    ap = argparse.ArgumentParser(description="vendor the published SHA-256 vectors")
    ap.add_argument("--keep-archives", action="store_true",
                    help="leave the downloaded zips under build/vectors-cache")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    manifest = {
        "note": "Published SHA-256 vectors, vendored. Refresh with tools/dev_env/vendor_test_vectors.py.",
        "consumed_by": "test/harness.py vectors",
        "files": [],
    }

    byte_zip, byte_stamp = fetch(BYTE_URL, "shabytetestvectors.zip")
    print("byte archive %s" % byte_stamp)
    take_members(byte_zip, byte_stamp, BYTE_URL,
                 [("shabytetestvectors/SHA256ShortMsg.rsp", "sha256shortmsg.rsp"),
                  ("shabytetestvectors/SHA256LongMsg.rsp", "sha256longmsg.rsp"),
                  ("shabytetestvectors/SHA256Monte.rsp", "sha256monte.rsp")],
                 "nist_cavp_", "NIST CAVP byte oriented SHA-256 vectors", manifest)

    bit_zip, bit_stamp = fetch(BIT_URL, "shabittestvectors.zip")
    print("bit archive %s" % bit_stamp)
    take_members(bit_zip, bit_stamp, BIT_URL,
                 [("shabittestvectors/SHA256ShortMsg.rsp", "sha256shortmsg.rsp"),
                  ("shabittestvectors/SHA256LongMsg.rsp", "sha256longmsg.rsp")],
                 "nist_cavp_bit_", "NIST CAVP bit oriented SHA-256 vectors, Len counts bits", manifest)

    hmac_zip, hmac_stamp = fetch(HMAC_URL, "hmactestvectors.zip")
    print("hmac archive %s" % hmac_stamp)
    take_hmac_section(hmac_zip, hmac_stamp, manifest)

    source = os.path.normpath(WYCHEPROOF_FROM)
    if os.path.isfile(source):
        with open(source, encoding="utf-8") as handle:
            doc = json.load(handle)
        target = os.path.join(OUT, "wycheproof_hmac_sha256.json")
        shutil.copyfile(source, target)
        manifest["files"].append({
            "file": os.path.basename(target),
            "source": doc.get("source"),
            "commit": doc.get("commit"),
            "member": doc.get("file"),
            "sha256": digest_of(target),
            "what": "Wycheproof HMAC-SHA-256, adversarial subset curated by ProtoCore",
        })
        print("  %-38s %s" % (os.path.basename(target), digest_of(target)[:16]))
    else:
        # Said out loud. A silently missing adversarial set is a gate that got weaker without anyone
        # deciding it should
        print("  SKIP wycheproof, no checkout at %s" % source)

    with open(os.path.join(OUT, "MANIFEST.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(manifest, indent=2) + "\n")

    if not args.keep_archives:
        shutil.rmtree(CACHE, ignore_errors=True)

    print("\n%d file(s) vendored, manifest at test/vectors/MANIFEST.json" % len(manifest["files"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
