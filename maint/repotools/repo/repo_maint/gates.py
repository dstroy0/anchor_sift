#!/usr/bin/env python3
# repotools-stamp: repo/repo_maint/gates.py 67d95bcad3094021
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The checks a commit has to answer, chosen per repository and run by one driver.

    gates.py                 run the gates this repository names, in order
    gates.py --list          what this repository runs, and where each tool resolved to
    gates.py --strict        promote every note to a refusal, the setting a cleanup pass wants
    gates.py <name> ...      run only the named gates

Four repositories on this machine each carried their own `pre-commit`, and between them they ran
three distinct checks and resolved the same tools four different ways. What differed was never the
logic. It was which tool, at which path, over which roots. All three of those are settings, so they
moved into `repotools.toml` and the logic became this file.

    [hooks]
    gates = ["docs_check", "fetch_check", "manifest"]

    [hooks.docs_check]
    roots = ["docs", "theory", "README.md"]

A MISSING TOOL STOPS THE RUN

Every one of the four hooks guarded its checker with some form of

    if [ -f "$TOOL" ]; then run_it; fi

and that shape is a defect wearing its most common costume. When a directory reorganization moved
one checker, its gate read as "not applicable" and turned itself off. Every commit for the rest of
that day passed without it, and nothing said so. A gate a repository asked for and this cannot find
is a refusal here, always, with the path it looked at printed.

TWO SEVERITIES, AND ONLY ONE REFUSES

A finding a reader meets as a broken page refuses. A finding that reads wrong and works fine is
printed and lets the commit through, because a gate refusing a commit over a backlog somebody
inherited gets turned off inside a day, and the breaking findings go through with it.
"""

import os
import subprocess
import sys

_at = os.path.dirname(os.path.abspath(__file__))
while _at != os.path.dirname(_at) and not os.path.isdir(os.path.join(_at, "lib", "repotools")):
    _at = os.path.dirname(_at)
sys.path.insert(0, os.path.join(_at, "lib"))

from repotools import boot, config, fetch, findings  # noqa: E402


class GateMissing(Exception):
    """A gate the repository asked for whose tool could not be found.

    Its own class, because this is the failure the driver exists to make loud, and catching it
    alongside an ordinary error would let it be reported as a check that passed.
    """


def _resolve(cfg, name, settings, default_names):
    """Where a gate's tool is, searched in a stated order, raising when it is nowhere.

    The order is: the path the repository named, then the environment variable, then this file's
    own installation, then the toolkit checkout. Each is printed on failure, so the message says
    what was tried instead of only that something was absent.

    The installation is looked at before the toolkit because in a repository that fetched this
    file the two are different directories, and the fetched one is the copy the lock names. It
    used to be absent from the order entirely, and the toolkit candidate reached for a root that
    a fetch never installs: repo/repo_template and code/ are not in any fetch, so the walk ran to
    the filesystem root and raised out of the whole gate run. The first repository to fetch
    gates.py could not run it, and what it printed named a boot marker instead of a missing tool.
    """
    tried = []

    named = settings.get("tool")
    if named:
        full = named if os.path.isabs(named) else os.path.join(cfg.where, named)
        tried.append(full)
        if os.path.isfile(full):
            return full

    from_env = os.environ.get("REPOTOOLS_%s" % name.upper())
    if from_env:
        tried.append(from_env)
        if os.path.isfile(from_env):
            return from_env

    here = boot.installed_root(__file__)
    for candidate in default_names:
        full = os.path.join(here, candidate.replace("/", os.sep))
        tried.append(full)
        if os.path.isfile(full):
            return full

    toolkit = boot.find_toolkit_root()
    if toolkit and (toolkit != here):
        for candidate in default_names:
            full = os.path.join(toolkit, candidate.replace("/", os.sep))
            tried.append(full)
            if os.path.isfile(full):
                return full

    raise GateMissing(
        "gate %s: no tool found. Looked at:\n    %s\n"
        "  Name one under [hooks.%s] tool, or set REPOTOOLS_%s." % (name, "\n    ".join(tried), name, name.upper())
    )


def _roots_for(cfg, settings, fallback):
    """The roots a gate reads, from its own settings or from the repository layout.

    Absolute, and refused when every one of them is absent. A root that has moved contributes zero
    files and lets a run exit 0. A prose check once read 188 files instead of 317 that way, and
    reported success on every commit for a week.
    """
    listed = settings.get("roots")
    if not listed:
        return cfg.existing(fallback)
    return cfg.existing(tuple(os.path.join(cfg.where, one.replace("/", os.sep)) for one in listed))


# --- the gates ---------------------------------------------------------------


def gate_docs_check(cfg, settings, strict):
    """The prose checker, over this repository's prose roots.

    The checker itself is not fetched. It lives under the toolkit's `no_replicate_` tree and stays
    there, so a repository reaches it by path or by a sibling checkout. That is deliberate and it is
    still a refusal when it cannot be reached: an unreachable checker is an unchecked commit.
    """
    tool = _resolve(
        cfg,
        "docs_check",
        settings,
        ("no_replicate_/prose_detection/docs_check.py",),
    )
    roots = _roots_for(cfg, settings, cfg.docs_roots() + cfg.source_roots())
    argv = [sys.executable, tool] + list(roots) + (["--strict"] if strict else [])
    return subprocess.call(argv)


def gate_fetch_check(cfg, _settings, strict):
    """Every tool fetched from the toolkit, checked against the lock.

    A fetched file edited in this repository refuses. The toolkit is upstream, so an edit here
    exists in one tree and is lost by the next fetch. Where the edit is worth keeping it is promoted
    with `repotools adopt` and flows back out to every repository.
    """
    if not fetch.read_lock(cfg):
        print("  %s fetches nothing from the toolkit." % cfg.project_name())
        return findings.EXIT_OK
    # `strict` was dropped here, so --strict promoted notes in one gate and silently did nothing in
    # this one. A flag that works for part of what it documents is worse than one that works for none.
    report = findings.Report("fetched tools", strict=strict)
    fetch.check(cfg, report)
    return report.done()


def gate_manifest(cfg, settings, _strict):
    """A tree reconciled against its signed inventory, and the signature checked for staleness.

    Two closed repositories ran this with the tool reached through an `ANCHOR_SIFT` variable and a
    guessed sibling path. Both of those are settings now.
    """
    tool = _resolve(cfg, "manifest", settings, ("repo/repo_maint/corpus_manifest.py",))
    where = settings.get("root", ".")
    target = os.path.join(cfg.where, where.replace("/", os.sep))
    status = subprocess.call([sys.executable, tool, "--root", target])
    if status != 0:
        return status

    inventory = os.path.join(target, settings.get("inventory", "MANIFEST.tsv"))
    signature = inventory + ".asc"
    if not os.path.isfile(inventory):
        return findings.EXIT_OK
    if not os.path.isfile(signature):
        print("  %s is not signed yet." % cfg.rel(inventory))
        print("      gpg --armor --detach-sign %s" % cfg.rel(inventory))
        return findings.EXIT_BREAKING
    # A signature older than the inventory it covers says nothing about what is being committed.
    if os.path.getmtime(inventory) > os.path.getmtime(signature):
        print("  %s is newer than its signature." % cfg.rel(inventory))
        print("      gpg --armor --detach-sign --yes %s" % cfg.rel(inventory))
        return findings.EXIT_BREAKING
    return findings.EXIT_OK


def gate_command(cfg, settings, _strict):
    """An arbitrary command this repository names, for a check the toolkit does not carry.

    Present so a repository with one specific gate does not have to fork the driver to run it. The
    command is refused when it names nothing, because an empty command succeeds and reads as a pass.
    """
    argv = settings.get("argv")
    if not argv:
        raise GateMissing("gate command: [hooks.command] names no argv, so it would check nothing.")
    return subprocess.call(list(argv), cwd=cfg.where)


GATES = {
    "docs_check": gate_docs_check,
    "fetch_check": gate_fetch_check,
    "manifest": gate_manifest,
    "command": gate_command,
}


def run(cfg, names, strict):
    """Run the named gates in order and return the first refusal.

    Every gate runs even after one refuses, so a commit that has to be fixed is fixed once instead
    of once per gate. The exit code is the first refusal seen.
    """
    worst = findings.EXIT_OK
    for name in names:
        if name not in GATES:
            raise GateMissing(
                "gate %s: no gate by that name. This repository's [hooks] gates names it. "
                "Known gates: %s." % (name, ", ".join(sorted(GATES)))
            )
        print("\n  gate: %s" % name)
        status = GATES[name](cfg, cfg.gate(name), strict)
        if status != findings.EXIT_OK and worst == findings.EXIT_OK:
            worst = status
    return worst


def main(argv):
    cfg = config.load()
    strict = "--strict" in argv
    chosen = [one for one in argv if not one.startswith("-")] or list(cfg.gates())

    if not chosen:
        print("  %s names no gates under [hooks] gates, so nothing was checked." % cfg.project_name())
        print("  A repository opts in to each gate by naming it. Known gates: %s." % ", ".join(sorted(GATES)))
        return findings.EXIT_OK

    if "--list" in argv:
        for name in chosen:
            settings = cfg.gate(name)
            try:
                where = _resolve(cfg, name, settings, ("no_replicate_/prose_detection/%s.py" % name,))
            except GateMissing:
                where = "(resolved at run time)"
            print("  %-14s %s" % (name, where))
        return findings.EXIT_OK

    try:
        status = run(cfg, chosen, strict)
    except GateMissing as missing:
        print("\n  commit stopped: %s" % missing)
        print("  A gate this repository asked for could not be run. That is never a pass.")
        return findings.EXIT_BREAKING

    if status == findings.EXIT_OK:
        return findings.EXIT_OK

    print("\n  commit stopped by the gate(s) above.")
    print("  Fix them, or `git commit --no-verify` when you know why.")
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
