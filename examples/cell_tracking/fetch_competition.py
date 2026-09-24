#!/usr/bin/env python3

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "biohub_cell_tracking", "cell_tracking", "data")
COMPETITION = "biohub-cell-tracking-during-development"


def load_token():
    path = os.path.join(HERE, "API_TOKEN.txt")
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            if line.startswith("KGAT_"):
                os.environ["KAGGLE_API_TOKEN"] = line
            elif "KAGGLE_API_TOKEN" in line and ("=" in line):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
                if value and not value.startswith("$"):
                    os.environ["KAGGLE_API_TOKEN"] = value
    return "KAGGLE_API_TOKEN" in os.environ


def main():
    parser = argparse.ArgumentParser(description="Biohub cell tracking competition data.")
    parser.add_argument("--download", action="store_true",
                        help="actually transfer; without it nothing moves")
    parser.add_argument("--file", metavar="PATH",
                        help="one file by its path in the competition, instead of everything")
    args = parser.parse_args()

    if not load_token():
        print("no token found in API_TOKEN.txt")
        return 1

    from kaggle.api.kaggle_api_extended import KaggleApi
    api = KaggleApi()
    api.authenticate()

    listing = api.competition_list_files(COMPETITION)
    files = getattr(listing, "files", listing)
    total = 0
    rows = []
    for entry in files:
        size = int(getattr(entry, "totalBytes", 0) or 0)
        total += size
        rows.append((str(entry.name), size))

    print("%d files listed, %.2f GB" % (len(rows), total / (1024.0 ** 3)))
    for name, size in rows[:20]:
        print("  %-60s %10.2f MB" % (name, size / (1024.0 ** 2)))
    if len(rows) > 20:
        print("  ... %d more" % (len(rows) - 20))

    if not args.download:
        print("\nNothing transferred. Pass --download to fetch.")
        return 0

    if not os.path.isdir(OUT):
        os.makedirs(OUT)

    if args.file:
        print("\nfetching %s into %s" % (args.file, OUT))
        api.competition_download_file(COMPETITION, args.file, path=OUT, force=False, quiet=False)
    else:
        print("\nfetching everything into %s" % OUT)
        api.competition_download_files(COMPETITION, path=OUT, force=False, quiet=False)
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
