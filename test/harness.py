#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""
harness.py - the one entry point for anchor_sift's test suites.

test/test_matrix.json is the one source of truth: one env per suite, each naming the script that
builds and runs it. Every build and run is a tessera job: `run` hands each suite's script to
tessera_run, which admits it on the device's daemon, and the daemon decides what runs beside what.

    harness.py run                        every suite in the matrix
    harness.py run codegen_device cell    those suites alone
    harness.py run --report-out PATH      and write the run's summary as a Markdown table

Each suite's output goes to build/harness/<env>.log beside the repository. A suite passes when
its job exits 0, every "test exit N" line it printed is 0, and no check failed ("N checks, M
failed"). A suite that prints "not run:" and no check line is NOT RUN; one that prints no check
line and no exit line is NO CHECKS, which is reported, never read as a pass by silence.

An env holds:

    desc      what the suite proves
    script    the script, repository-relative, run under bash
    src       the sources it builds, as +<path> under src/
    tests     the test folders it runs, under test/
    env       settings the script runs under, NAME: VALUE
    wsl       true where the script runs under WSL, which takes its settings on the command line

Every change to the matrix goes through `harness.py env`, which splices the one env it changes
into the file as text, so a change is a minimal diff and nothing else in the file moves. A script
that must touch the table imports this module and calls splice_after, splice_replace or
splice_remove, then write_verified.
"""

import argparse
import concurrent.futures
import errno
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools import findroot  # noqa: E402

ROOT = findroot.root()
TABLE = findroot.at("test", "test_matrix.json")

LOCK_TIMEOUT_S = 120.0  # a writer that cannot get in by then reports rather than racing
LOCK_STALE_S = 300.0  # a lock older than this belonged to a run that died
LOCK_POLL_S = 0.05


# ---------------------------------------------------------------------------
# table locking
# ---------------------------------------------------------------------------


def lock_acquire(table):
    """Take the table's lock, or report why not. O_EXCL is the atomic part on both platforms."""
    lock = str(table) + ".lock"
    deadline = time.time() + LOCK_TIMEOUT_S
    while True:
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return lock
        except OSError as e:
            if e.errno != errno.EEXIST:
                raise
        try:
            if time.time() - os.path.getmtime(lock) > LOCK_STALE_S:
                os.unlink(lock)  # the holder is gone; take it on the next pass
                continue
        except OSError:
            continue  # it vanished between the test and the stat: retry
        if time.time() > deadline:
            return None
        time.sleep(LOCK_POLL_S)


def lock_release(lock):
    try:
        os.unlink(lock)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# text splicing: the table is edited as text so a write is a minimal diff
# ---------------------------------------------------------------------------


def env_span(text, name):
    """(pad, key_start, close) for an env: the indent it sits at, the index of its opening quote,
    and the index of its object's matching close brace.

    The brace scan steps over string literals. A desc is free text and may carry a lone brace,
    which a counter that reads every character would take for structure.
    """
    m = re.search(r'^([ \t]*)"%s"\s*:\s*\{' % re.escape(name), text, re.M)
    if not m:
        raise KeyError(name)
    depth = 0
    start = m.start() + len(m.group(1))
    i = text.index("{", m.start())
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return m.group(1), start, i
        i += 1
    raise KeyError(name)


def reindent(block, pad):
    return "\n".join(pad + l[2:] if l.startswith("  ") else pad + l.strip() for l in block.split("\n"))


def splice_after(text, anchor, name, entry):
    """Insert entry as text directly after the anchor env's closing brace."""
    pad, _, close = env_span(text, anchor)
    # the render opens with a line's end after its brace, which would leave a blank line ahead of the entry
    block = json.dumps({name: entry}, indent=2)[1:-1].strip("\n").rstrip()
    return text[: close + 1] + ",\n" + reindent(block, pad) + text[close + 1 :]


def splice_replace(text, name, entry):
    """Replace an env's whole `"name": {...}` in place, rendered at the indent it already sits at.

    The same render as splice_after, so an updated env and a new one are indented identically. The
    leading pad is dropped because the text kept ahead of key_start already carries it.
    """
    pad, key_start, close = env_span(text, name)
    block = json.dumps({name: entry}, indent=2)[1:-1].rstrip()
    return text[:key_start] + reindent(block, pad).lstrip() + text[close + 1 :]


def splice_remove(text, name):
    """Cut an env's whole `"name": {...}` out, taking the one comma that joined it to its neighbors.

    The comma sits after the close brace for every env but the last, where it sits before the key.
    Removing the wrong one, or neither, leaves the table unparseable.
    """
    pad, key_start, close = env_span(text, name)
    end = close + 1
    tail = text[end:]
    lead = len(tail) - len(tail.lstrip(" \t\r\n"))
    if tail[lead : lead + 1] == ",":
        end += lead + 1  # not the last env: take the comma that follows it, and the rest of its line
        while end < len(text) and text[end] in " \t\r":
            end += 1
        if text[end : end + 1] == "\n":
            end += 1
        # and its line from the start, so its indent does not stay behind ahead of the next env's
        return text[: key_start - len(pad)] + text[end:]
    head = text[:key_start]
    cut = len(head.rstrip(" \t\r\n"))
    if head[cut - 1 : cut] == ",":
        cut -= 1  # the last env: take the comma that preceded it
    return text[:cut] + text[end:]


def read_table(path):
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    return text, json.loads(text)


def write_verified(path, text, before, changed, expect):
    """Write only if the reparsed table matches `expect` for `changed` and is untouched elsewhere."""
    after = json.loads(text)
    for name, want in expect.items():
        if after["envs"].get(name) != want:
            print("the spliced env did not round-trip:", name)
            return 1
    for k in before["envs"]:
        if k in changed:
            continue
        if before["envs"][k] != after["envs"].get(k):
            print("collateral change in", k)
            return 1
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    return 0


# ---------------------------------------------------------------------------
# env add / update / remove / list
# ---------------------------------------------------------------------------


def src_filter(p):
    """A path in the matrix's own src spelling, whichever form it arrived in.

    The matrix writes a source as `+<path>`, and a caller reading the matrix passes it back already
    written that way. Wrapping a second time gives `+<+<path>>`, which names nothing.
    """
    p = p.strip()
    return p if p.startswith(("+<", "-<")) else "+<%s>" % p


def settings(pairs):
    """{NAME: VALUE} from NAME=VALUE arguments, or None and the one that is not written so."""
    out = {}
    for pair in pairs:
        name, sep, value = pair.partition("=")
        if not sep or not name:
            return None, pair
        out[name] = value
    return out, None


def locked(edit):
    """Run `edit(text, before)` under the table's lock; it returns the exit status."""
    lock = lock_acquire(TABLE)
    if not lock:
        print("could not take the table lock within %.0fs" % LOCK_TIMEOUT_S)
        return 1
    try:
        text, before = read_table(TABLE)
        return edit(text, before)
    finally:
        lock_release(lock)


def cmd_env_add(a):
    def edit(text, before):
        envs = before["envs"]
        if a.name in envs:
            print("env already present:", a.name)
            return 1
        if a.after not in envs:
            print("anchor env not found:", a.after)
            return 1
        if not os.path.isfile(os.path.join(ROOT, *a.script.split("/"))):
            print("no such script:", a.script)
            return 1
        values, wrong = settings(a.env)
        if values is None:
            print("not NAME=VALUE:", wrong)
            return 1
        entry = {"desc": a.desc, "script": a.script, "src": [src_filter(p) for p in a.src], "tests": list(a.tests)}
        if values:
            entry["env"] = values
        if a.wsl:
            entry["wsl"] = True
        text = splice_after(text, a.after, a.name, entry)
        rc = write_verified(TABLE, text, before, {a.name}, {a.name: entry})
        if rc == 0:
            print("added %s" % a.name)
        return rc

    return locked(edit)


def cmd_env_update(a):
    """Change an existing env. Every list option adds unless its --drop- twin removes."""

    def edit(text, before):
        envs = before["envs"]
        if a.name not in envs:
            print("env not found:", a.name)
            return 1
        entry = json.loads(json.dumps(envs[a.name]))  # a copy the splice is verified against

        def merge(key, add, drop, wrap=None):
            cur = list(entry.get(key, []))
            for v in drop:
                v = wrap(v) if wrap else v
                if v in cur:
                    cur.remove(v)
                else:
                    print("not present in %s.%s: %s" % (a.name, key, v))
            for v in add:
                v = wrap(v) if wrap else v
                if v not in cur:
                    cur.append(v)
            entry[key] = cur

        merge("src", a.src, a.drop_src, wrap=src_filter)
        merge("tests", a.tests, a.drop_tests)
        values, wrong = settings(a.env)
        if values is None:
            print("not NAME=VALUE:", wrong)
            return 1
        env = dict(entry.get("env", {}))
        for name in a.drop_env:
            if env.pop(name, None) is None:
                print("not present in %s.env: %s" % (a.name, name))
        env.update(values)
        if env:
            entry["env"] = env
        else:
            entry.pop("env", None)
        if a.desc is not None:
            entry["desc"] = a.desc
        if a.script is not None:
            if not os.path.isfile(os.path.join(ROOT, *a.script.split("/"))):
                print("no such script:", a.script)
                return 1
            entry["script"] = a.script
        if a.wsl is not None:
            if a.wsl:
                entry["wsl"] = True
            else:
                entry.pop("wsl", None)
        if entry == envs[a.name]:
            print("no change:", a.name)
            return 0
        text = splice_replace(text, a.name, entry)
        rc = write_verified(TABLE, text, before, {a.name}, {a.name: entry})
        if rc == 0:
            print("updated %s" % a.name)
        return rc

    return locked(edit)


def cmd_env_remove(a):
    """Cut envs out of the matrix. Their tests are not deleted: a test folder no env still names
    stops running, so that is refused unless --force."""

    def edit(text, before):
        envs = before["envs"]
        missing = [n for n in a.name if n not in envs]
        if missing:
            print("env not found:", " ".join(missing))
            return 1
        if len(envs) - len(set(a.name)) < 1:
            print("refusing to empty the table")
            return 1
        kept = {n: e for n, e in envs.items() if n not in set(a.name)}
        still_run = set()
        for e in kept.values():
            still_run.update(e.get("tests") or [])
        orphaned = []
        for n in set(a.name):
            for t in envs[n].get("tests") or []:
                if t not in still_run:
                    orphaned.append("%s (only in %s)" % (t, n))
        if orphaned and not a.force:
            print("these test folders would stop running - name them in another env first, or pass --force:")
            for o in sorted(set(orphaned)):
                print("   ", o)
            return 1
        if a.verbose:
            # Where each test folder still runs once these envs are gone
            covers = {}
            for n, e in kept.items():
                for t in e.get("tests") or []:
                    covers.setdefault(t, []).append(n)
            for n in sorted(set(a.name)):
                tests = envs[n].get("tests") or []
                print("%s (%d test folder%s)" % (n, len(tests), "" if len(tests) == 1 else "s"))
                for t in tests:
                    where = covers.get(t) or []
                    print("    %-52s %s" % (t, ("still in: " + ", ".join(sorted(where))) if where else "NOWHERE ELSE"))
        for n in set(a.name):
            text = splice_remove(text, n)
        left = [n for n in set(a.name) if n in json.loads(text)["envs"]]
        if left:
            print("still present after the splice:", " ".join(left))
            return 1
        rc = write_verified(TABLE, text, before, set(a.name), {})
        if rc == 0:
            print("removed %d env(s)" % len(set(a.name)))
        return rc

    return locked(edit)


def cmd_env_list(a):
    with open(TABLE, encoding="utf-8") as f:
        envs = json.load(f)["envs"]
    for name, e in envs.items():
        if a.verbose:
            print("%-32s %s" % (name, e.get("script", "")))
        else:
            print(name)
    return 0


# ---------------------------------------------------------------------------
# run: each env's script as a tessera job
# ---------------------------------------------------------------------------

TESSERA_RUN_CANDIDATES = (
    os.environ.get("HARNESS_TESSERA_RUN", ""),
    os.path.join(os.path.dirname(ROOT), "build", "tessera_host", "tessera_run.exe"),
    os.path.join(ROOT, "build", "tessera_host", "tessera_run.exe"),
    os.path.join(os.path.dirname(ROOT), "build", "tessera_host", "tessera_run"),
    os.path.join(ROOT, "build", "tessera_host", "tessera_run"),
)
SCRIPT_BUILD = os.path.join(os.path.dirname(ROOT), "build", "harness")
CHECKS_LINE = re.compile(r"(\d+) checks, (\d+) failed")
EXIT_LINE = re.compile(r"test exit (\d+)")


def find_tessera_run():
    for c in TESSERA_RUN_CANDIDATES:
        if c and os.path.isfile(c):
            return c
    return None


def script_bash():
    """The bash that runs a suite script, as a Windows path where tessera_run is a Windows program."""
    bash = shutil.which("bash")
    if bash and os.name == "nt":
        r = subprocess.run(["cygpath", "-m", bash], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    return bash


def wsl_path(path):
    """A Windows path as WSL mounts it: D:/a/b -> /mnt/d/a/b."""
    p = os.path.abspath(path).replace("\\", "/")
    if len(p) > 1 and p[1] == ":":
        return "/mnt/%s%s" % (p[0].lower(), p[2:])
    return p


def script_command(name, e, tessera):
    """The command line and the environment one env's suite runs under."""
    out = os.path.join(SCRIPT_BUILD, name)
    os.makedirs(out, exist_ok=True)
    env = dict(os.environ)
    env.update(e.get("env", {}))
    env["BUILD_OUT"] = out
    if "CYCLE_RECORD_CHECK" in env or "CYCLE_RECORD_REPORT" in env:
        cache = os.path.join(out, "cycle_cache")
        os.makedirs(cache, exist_ok=True)
        env["CYCLE_CACHE"] = cache.replace("\\", "/")
    script = os.path.join(ROOT, *e["script"].split("/"))
    if e.get("wsl"):
        # WSL takes no environment from here: the settings ride on the command line
        sets = " ".join(
            "%s=%s" % (k, wsl_path(v) if k == "BUILD_OUT" else v)
            for k, v in sorted(list(e.get("env", {}).items()) + [("BUILD_OUT", out)])
        )
        return ["wsl.exe", "bash", "-lc", "%s bash %s" % (sets, wsl_path(script))], env
    cmd = [
        tessera,
        "--processors",
        str(e.get("processors", 4)),
        "--name",
        "harness " + name,
        "--",
        script_bash(),
        script.replace("\\", "/"),
    ]
    return cmd, env


def script_run_one(name, e, tessera):
    """Run one env's suite. Returns (name, status, checks, failed, exit, log path, seconds)."""
    cmd, env = script_command(name, e, tessera)
    log = os.path.join(SCRIPT_BUILD, name + ".log")
    t0 = time.time()
    with open(log, "w", encoding="utf-8", errors="replace") as fh:
        rc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=fh, stderr=subprocess.STDOUT).returncode
    secs = time.time() - t0
    with open(log, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    checks = failed = 0
    for m in CHECKS_LINE.finditer(text):
        checks += int(m.group(1))
        failed += int(m.group(2))
    exits = [int(m.group(1)) for m in EXIT_LINE.finditer(text)]
    # a suite passes when the job exited 0, every "test exit" it printed is 0 and no check failed; a script that
    # built nothing and ran nothing prints no check line, which is reported, never read as a pass by silence
    if rc != 0 or failed or any(exits):
        status = "FAIL"
    elif checks == 0 and "not run:" in text:
        status = "NOT RUN"
    elif checks == 0 and not exits:
        status = "NO CHECKS"
    else:
        status = "PASS"
    return name, status, checks, failed, rc, log, secs


def script_report(path, results, secs):
    failed = sum(1 for r in results if r[1] not in ("PASS", "NOT RUN"))
    md = [
        "# Test Report",
        "",
        "**Generated:** " + time.strftime("%Y-%m-%d %H:%M:%S"),
        "",
        "**Command:** `harness.py run` over %d suites" % len(results),
        "**Result:** %d passed, %d not passed - %ds" % (len(results) - failed, failed, secs),
        "",
        "## Summary",
        "",
        "| Suite | Status | Checks | Failed | Exit | Duration |",
        "| :---- | :----- | -----: | -----: | ---: | -------: |",
    ]
    for name, status, checks, failed_checks, rc, _, run_secs in results:
        md.append("| `%s` | %s | %d | %d | %d | %ds |" % (name, status, checks, failed_checks, rc, run_secs))
    full = os.path.join(ROOT, *path.split("/")) if not os.path.isabs(path) else path
    with open(full, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(md) + "\n")


def cmd_run(a):
    with open(TABLE, encoding="utf-8") as f:
        table = json.load(f)["envs"]
    tessera = find_tessera_run()
    if not tessera:
        print("error: tessera_run not found (set HARNESS_TESSERA_RUN): every build and run is a tessera job")
        return 1
    names = a.envs or list(table)
    missing = [n for n in names if n not in table]
    if missing:
        print("not a suite in test/test_matrix.json: " + " ".join(missing))
        return 1
    os.makedirs(SCRIPT_BUILD, exist_ok=True)
    total = len(names)
    results = []
    t0 = time.time()
    # the daemon decides what runs beside what. The suites go to it together; -j bounds how many wait at once
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        futures = [pool.submit(script_run_one, n, table[n], tessera) for n in names]
        for i, f in enumerate(concurrent.futures.as_completed(futures), 1):
            name, status, checks, failed, rc, log, secs = f.result()
            results.append((name, status, checks, failed, rc, log, secs))
            print(
                "[%d/%d] %-34s %-9s %d checks, %d failed, exit %d, %.0f s" % (i, total, name, status, checks, failed, rc, secs),
                flush=True,
            )
            if status != "PASS" or a.verbose:
                print("    log: %s" % log)
    bad = sorted(r[0] for r in results if r[1] not in ("PASS", "NOT RUN"))
    print("\n%d/%d suites passed, %.0f s" % (total - len(bad), total, time.time() - t0))
    if bad:
        print("not passed: " + " ".join(bad))
    if a.report_out:
        script_report(a.report_out, sorted(results), int(time.time() - t0))
        print("Report written: %s" % a.report_out)
    return 1 if bad else 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _subcommands(parser):
    """{name: subparser} for a parser's one subparser group."""
    for action in parser._actions:
        if isinstance(action, argparse._SubParsersAction):
            return action.choices
    return {}


def cmd_help(a):
    """Every command's own help in one call, or one command's."""
    subs = _subcommands(build_parser())
    if a.command:
        if a.command not in subs:
            print("no such command: %s (try `harness.py help`)" % a.command, file=sys.stderr)
            return 2
        subs[a.command].print_help()
        for name, nested in sorted(_subcommands(subs[a.command]).items()):
            print("\n### harness.py %s %s" % (a.command, name))
            print(nested.format_help().strip())
        return 0
    print(__doc__.strip())
    for name in sorted(subs):
        print("\n" + "-" * 78)
        print("### harness.py %s" % name)
        print(subs[name].format_help().strip())
        for nested_name, nested in sorted(_subcommands(subs[name]).items()):
            print("\n  ### harness.py %s %s" % (name, nested_name))
            print(nested.format_help().strip())
    return 0


def build_parser():
    ap = argparse.ArgumentParser(
        prog="harness.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = ap.add_subparsers(dest="group", required=True)

    p = sub.add_parser("help", help="every command's help in one call, or one command's")
    p.add_argument("command", nargs="?")
    p.set_defaults(fn=cmd_help)

    env = sub.add_parser(
        "env",
        help="the test matrix",
        description="Every change to test/test_matrix.json goes through one of these, spliced in as "
        "text so the diff names only what changed.",
    ).add_subparsers(dest="cmd", required=True)

    p = env.add_parser("add", help="splice a new env into the matrix")
    p.add_argument("name")
    p.add_argument("--after", required=True, help="env to insert after")
    p.add_argument("--script", required=True, help="the suite's script, repository-relative")
    p.add_argument("--desc", default="")
    p.add_argument("--src", action="extend", nargs="+", default=[], help="sources it builds, under src/")
    p.add_argument("--tests", action="extend", nargs="+", default=[], help="test folders it runs, under test/")
    p.add_argument("--env", action="append", default=[], metavar="NAME=VALUE", help="a setting the script runs under")
    p.add_argument("--wsl", action="store_true", help="run the script under WSL")
    p.set_defaults(fn=cmd_env_add)

    p = env.add_parser("update", help="change an existing env")
    p.add_argument("name")
    p.add_argument("--script", default=None)
    p.add_argument("--desc", default=None)
    p.add_argument("--src", action="extend", nargs="+", default=[])
    p.add_argument("--drop-src", action="extend", nargs="+", default=[], dest="drop_src")
    p.add_argument("--tests", action="extend", nargs="+", default=[])
    p.add_argument("--drop-tests", action="extend", nargs="+", default=[], dest="drop_tests")
    p.add_argument("--env", action="append", default=[], metavar="NAME=VALUE")
    p.add_argument("--drop-env", action="append", default=[], dest="drop_env", metavar="NAME")
    p.add_argument("--wsl", action=argparse.BooleanOptionalAction, default=None)
    p.set_defaults(fn=cmd_env_update)

    p = env.add_parser("remove", help="cut envs out of the matrix")
    p.add_argument("name", nargs="+")
    p.add_argument("--force", action="store_true", help="remove even where a test folder stops running")
    p.add_argument("-v", "--verbose", action="store_true", help="print each env's test folders and where they still run")
    p.set_defaults(fn=cmd_env_remove)

    p = env.add_parser("list", help="print the envs the matrix defines")
    p.add_argument("-v", "--verbose", action="store_true", help="with each env's script")
    p.set_defaults(fn=cmd_env_list)

    p = sub.add_parser("run", help="run suites, each as a tessera job")
    p.add_argument("envs", nargs="*")
    p.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 4, help="how many suites wait on the daemon at once")
    p.add_argument("-v", "--verbose", action="store_true", help="print every suite's log path, not only the ones that did not pass")
    p.add_argument("--report-out", metavar="PATH", help="write the run's summary here")
    p.set_defaults(fn=cmd_run)
    return ap


def main():
    a = build_parser().parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
