#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the measured ground-state electron configurations from the NIST Atomic Spectra Database.
#
#   Usage:  python maint/data/fetch/fetch_nist_ground_states.py [--refresh]
#
# The particle_physics oracle stage reads these. The ideal Madelung filling in
# representation/atom/element.py is the model, and this is the measurement it is held against: where a
# real atom fills against the order, chromium and the rest, the two disagree, and that disagreement is
# the aufbau exception the oracle reports.
#
# One request for the whole range covers it, so the archive is asked once. The NIST database is a
# public service run by people; a second run costs it nothing, and this caches, so no second run is
# needed. The tool refuses on an empty or truncated response instead of writing a short file that a
# later reader would take for the whole table.
#
# The database carries measured spectra to element 110. Elements 111 to 118 have no measured
# configuration, only predictions, so they are absent here, and the oracle reports them as
# unmeasured and does not invent a row for them.
#
# Source: NIST Atomic Spectra Database, Ground States and Ionization Energies, physics.nist.gov.

import io
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# Walk up to the repository instead of counting directories to it, and stop at the filesystem root.
# A directory that is its own parent would otherwise loop the walk forever.
ROOT = os.path.dirname(os.path.abspath(__file__))
while ROOT != os.path.dirname(ROOT) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
if not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    raise SystemExit("could not find src/engine above %s" % os.path.abspath(__file__))

CACHE = os.path.join(ROOT, "build", "nist")
GROUND_STATES = os.path.join(CACHE, "ground_states.csv")

ENDPOINT = "https://physics.nist.gov/cgi-bin/ASD/ie.pl"

# The query. spectra is the element range, format 2 is the comma-separated download, and the out flags
# ask for the atomic number, the element name and the ground shells, the full configuration this reads.
QUERY = (
    ("spectra", "H-Og"),
    ("units", "1"),
    ("format", "2"),
    ("order", "0"),
    ("at_num_out", "on"),
    ("el_name_out", "on"),
    ("shells_out", "on"),
    ("conf_out", "on"),
    ("e_out", "0"),
    ("submit", "Retrieve Data"),
)

# Below this the response cannot be the whole table, and a short read raises instead of caching.
LEAST_BYTES = 100000


def fetch(out):
    """Retrieve the ground-state table and cache it, or raise on a short or empty response."""
    address = ENDPOINT + "?" + urllib.parse.urlencode(QUERY)
    request = urllib.request.Request(address, headers={"User-Agent": "anchor_sift/particle_physics"})
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
    if len(body) < LEAST_BYTES:
        raise ValueError("response was %d bytes, below the %d a full table takes"
                         % (len(body), LEAST_BYTES))
    text = body.decode("utf-8", errors="replace")
    if "Ground Shells" not in text:
        raise ValueError("response carried no 'Ground Shells' header; the query surface changed")
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    with io.open(GROUND_STATES, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    out.write("  wrote %d bytes to %s\n"
              % (len(text.encode("utf-8")), GROUND_STATES.replace(os.sep, "/")))


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    refresh = "--refresh" in argv
    if os.path.isfile(GROUND_STATES) and not refresh:
        out.write("\n  already cached: %s\n  pass --refresh to fetch again.\n\n"
                  % GROUND_STATES.replace(os.sep, "/"))
        out.flush()
        return 0
    out.write("\n  fetching the NIST ground-state table, one request for H to Og\n")
    try:
        fetch(out)
    except (urllib.error.URLError, ValueError) as failure:
        out.write("  fetch failed: %s\n\n" % failure)
        out.flush()
        return 1
    out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
