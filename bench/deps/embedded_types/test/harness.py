#!/usr/bin/env python3
# embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.
"""embedded_types test harness: suite discovery and Unity runner generation.

  harness.py build [--tree T]                 configure if needed, then build
  harness.py test [--tree T] [--filter RE]    build, then run the suites
  harness.py suites [--strict]                every suite, its cases, and what will never run
  harness.py cases <dir>...                   what Unity will register, and what it will walk past
  harness.py runners gen <dir>... --unity <rb>   write <dir>/unity_runner.c

There are two build trees. Each carries its own flags here, and running one takes no remembered
shell invocation:

  build          the library, as it ships
  build-werror   the same, with EMBEDDED_TYPES_WERROR on

The second one matters because this library is headers a consumer compiles inside its own
translation unit. A warning it introduces is raised in the consumer's build and attributed to the
consumer's file. A diagnostic that only scrolls past here is one somebody else has to read.

Two environment variables, because a first build has nothing to infer them from:

  EMBEDDED_TYPES_BUILD_ROOT   where the trees are made, ROOT by default. Windows caps a full object
                              path at 250 characters. A checkout far enough down cannot build in
                              place at all. The cap is the compiler's, and a shorter prefix is the
                              only fix.
  EMBEDDED_TYPES_CMAKE_ARGS   extra configure arguments, split like a shell would. The generator and
                              the compiler are otherwise read off a tree that already built, and a
                              fresh clone whose first build is this one has no such tree.

A case Unity's generator does not collect is not an error to the generator. It is never registered,
and the suite passes while the case never ran. `cases` and `runners gen` both break that silence by
naming the near misses.

The same silence has a second shape. The generator reads case names out of the source text and does
not see a preprocessor conditional. A case defined inside an `#if` is declared and called by the
runner however that conditional went. Where it went the other way the suite fails to LINK. `suites`
reports every case sitting inside one.

The mechanisms here are generic. The paths and the two build trees are this project's.
"""

import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Where the build trees live. ROOT by default, because a tree beside the source is what anyone
# expects to find. EMBEDDED_TYPES_BUILD_ROOT moves them, and it is not a convenience. Windows caps
# a full object path at 250 characters. A checkout deep enough cannot build in place, and a git
# worktree under a temporary directory is the usual way to get that deep. The cap is the compiler's,
# and the only fix is a shorter prefix.
BUILD_ROOT = os.path.abspath(os.environ.get("EMBEDDED_TYPES_BUILD_ROOT", ROOT))

# Extra configure arguments, split like a shell would. borrowed_toolchain() reads the generator and
# the compiler off a tree that already built. A fresh clone whose first build is this one has no
# such tree. cmake's default generator is not always one that works on a given machine, and a first
# build with nothing to borrow from needs somewhere to read them from.
CMAKE_ARGS = os.environ.get("EMBEDDED_TYPES_CMAKE_ARGS", "")


def tree_path(tree):
    """Absolute path of build tree @p tree."""
    return os.path.join(BUILD_ROOT, tree)


# A two-way split. A suite is a directory holding exactly one .c with cases, and its generated runner
# sits beside it.
#
#   unit/test_<header>/        one per header in include/, asserting what that header alone states
#   integration/test_<name>/   more than one header together
#
# integration/ does not exist yet, and discover() skips a group that is not there. It is named
# because the first suite that crosses two headers has somewhere to go that is not unit/, where it
# would report a failure against a header it only borrowed.
UNIT = os.path.join(ROOT, "test", "unit")
INTEGRATION = os.path.join(ROOT, "test", "integration")
GENERATED_RUNNER = "unity_runner.c"

# What Unity's generate_test_runner.rb collects, and the shape a case has to have to be collected.
UNITY_CASE = re.compile(r"^[ \t]*void[ \t]+(test_\w+)[ \t]*\([ \t]*(?:void)?[ \t]*\)", re.M)
NEAR_MISS = re.compile(r"^[ \t]*void[ \t]+(\w+)[ \t]*\([ \t]*(?:void)?[ \t]*\)[ \t]*\r?\n[ \t]*\{", re.M)
NOT_A_CASE = ("setUp", "tearDown", "main", "suiteSetUp", "suiteTearDown")

# A conditional, and the two directives that end or invert one. #ifdef and #ifndef are both matched
# by ANY_IF, which is what makes the depth count right.
ANY_IF = re.compile(r"^[ \t]*#[ \t]*if")
ANY_ELSE = re.compile(r"^[ \t]*#[ \t]*el(se|if)")
ANY_ENDIF = re.compile(r"^[ \t]*#[ \t]*endif")


def runner_cases(path):
    """The cases Unity's generator will register in @p path, and the ones it will walk past."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    found = UNITY_CASE.findall(text)
    missed = [n for n in NEAR_MISS.findall(text) if n not in found and n not in NOT_A_CASE]
    return found, missed


def conditional_cases(path):
    """Every registered case in @p path whose definition sits inside a preprocessor conditional.

    Unity's generator reads case names out of the source text, so such a case is still declared and
    called by the runner. Where the conditional went the other way the definition is gone and the
    suite fails to LINK. A failed link is a build somebody has to read, and it is louder than a case
    that quietly never ran.

    A case whose body must vary by target puts the #if inside the case, where every arm still
    compiles into one definition the runner can reach.
    """
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    out = []
    depth = 0
    for line in lines:
        if ANY_ENDIF.match(line):
            depth = max(depth - 1, 0)
            continue
        if ANY_ELSE.match(line):
            continue
        if ANY_IF.match(line):
            depth += 1
            continue
        match = UNITY_CASE.match(line)
        if match and depth > 0:
            out.append(match.group(1))
    return out


def suite_source(suite_dir):
    """The one .c in a suite that holds its cases, or None."""
    if not os.path.isdir(suite_dir):
        return None
    for name in sorted(os.listdir(suite_dir)):
        path = os.path.join(suite_dir, name)
        if name.endswith(".c") and name != GENERATED_RUNNER and runner_cases(path)[0]:
            return path
    return None


def discover():
    """Every suite directory, which is any dir holding a .c with a collectable case."""
    out = []
    for base in (UNIT, INTEGRATION):
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            if any(f.endswith(".c") and f != GENERATED_RUNNER for f in filenames):
                if suite_source(dirpath):
                    out.append(dirpath)
    return sorted(out)


def find_ruby():
    """Ruby runs Unity's generator. A missing one is an error, never a silent skip."""
    return shutil.which("ruby")


def generate_runner(suite_dir, unity_rb):
    """Emit suite_dir/unity_runner.c from the one source that holds the cases."""
    candidates = [f for f in sorted(os.listdir(suite_dir)) if f.endswith(".c") and f != GENERATED_RUNNER]
    sources = [f for f in candidates if runner_cases(os.path.join(suite_dir, f))[0]]
    if not sources:
        for name in candidates:
            _, missed = runner_cases(os.path.join(suite_dir, name))
            if missed:
                raise SystemExit(
                    "runners: %s holds no case Unity's generator will register.\n"
                    "  It collects file-scope `void test_<name>(void)` and nothing else, so these\n"
                    "  are walked past and never run: %s\n"
                    "  Rename each to test_<name> - a case the generator skips costs coverage in\n"
                    "  silence, because the suite still passes."
                    % (os.path.relpath(os.path.join(suite_dir, name), ROOT), ", ".join(missed))
                )
        raise SystemExit("runners: no test case found in %s" % os.path.relpath(suite_dir, ROOT))
    # The generator takes one input file and emits one main(), so cases spread across several
    # sources cannot be registered from any single one of them.
    if len(sources) > 1:
        raise SystemExit(
            "runners: %s holds test cases in %d sources (%s).\n"
            "  Unity's generator registers one source per runner, so the rest would never run.\n"
            "  Put the cases in one file, or give each file its own suite directory."
            % (os.path.relpath(suite_dir, ROOT), len(sources), ", ".join(sources))
        )
    ruby = find_ruby()
    if not ruby:
        raise SystemExit("runners: ruby not found on PATH - install it (choco install ruby)")
    if not os.path.isfile(unity_rb):
        raise SystemExit("runners: Unity's generate_test_runner.rb not found at %s" % unity_rb)
    src = os.path.join(suite_dir, sources[0])
    out = os.path.join(suite_dir, GENERATED_RUNNER)
    subprocess.run([ruby, unity_rb, src, out], check=True)
    # Unity's generator opens its output in text mode, so on Windows every line lands CRLF while
    # .gitattributes holds this tree at "LF in the repository and LF in the working copy". The runner
    # is tracked, so that difference shows as a modified file after every build that regenerates one.
    # git normalizes the content it stores either way, so nothing was ever committed wrong; rewriting
    # the bytes here is what leaves the working copy as the build found it, on every platform. A
    # no-op where the generator already wrote LF.
    with open(out, "rb") as fh:
        written = fh.read()
    lf = written.replace(b"\r\n", b"\n")
    if lf != written:
        with open(out, "wb") as fh:
            fh.write(lf)
    # Report the near misses even on success: the runner is written, and these still never ran.
    found, missed = runner_cases(src)
    if missed:
        print(
            "runners: %s registered %d cases, and walked past %s - rename each to test_<name>"
            % (os.path.relpath(src, ROOT), len(found), ", ".join(missed)),
            file=sys.stderr,
        )
    return out


# ------------------------------------------------------------------------------------------------
# Build trees
# ------------------------------------------------------------------------------------------------
# Each tree carries the flags that define it. Keeping them here means running one takes no
# remembered shell invocation.
TREES = {
    "build": {
        "what": "the library as it ships",
        "args": [],
    },
    "build-werror": {
        "what": "the same, with every warning an error",
        # This library is headers a consumer compiles inside its own translation unit. A warning it
        # introduces is raised in that build and attributed to that file. A diagnostic nobody has
        # to fix here is one somebody else has to read.
        "args": ["-DEMBEDDED_TYPES_WERROR=ON"],
    },
}


def run(cmd, quiet=True):
    """Run a command from the repository root and hand back its completed process."""
    if quiet:
        return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return subprocess.run(cmd, cwd=ROOT, text=True)


def borrowed_toolchain(skip):
    """Generator and compiler taken from whichever tree is already configured.

    cmake's default generator is not always the one that works on a given machine, and a tree that
    already built is proof of one that does. Reading it back keeps the toolchain path in one place.
    """
    keys = {
        "CMAKE_GENERATOR": "-G",
        "CMAKE_C_COMPILER": "-DCMAKE_C_COMPILER=",
        "CMAKE_MAKE_PROGRAM": "-DCMAKE_MAKE_PROGRAM=",
    }
    for tree in TREES:
        if tree == skip:
            continue
        cache = os.path.join(tree_path(tree), "CMakeCache.txt")
        if not os.path.isfile(cache):
            continue
        out = []
        with open(cache, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                name, sep, value = line.partition(":")
                if not sep or name not in keys:
                    continue
                value = value.partition("=")[2].strip()
                out += [keys[name] + value] if keys[name].endswith("=") else [keys[name], value]
        if out:
            return out
    return []


def configure(tree):
    """Configure @p tree if it is not there yet."""
    if os.path.isfile(os.path.join(tree_path(tree), "CMakeCache.txt")):
        return 0
    cmd = ["cmake", "-S", ".", "-B", tree_path(tree), "-DCMAKE_BUILD_TYPE=Debug", "-DEMBEDDED_TYPES_BUILD_TESTS=ON"]
    cmd += TREES[tree]["args"] + borrowed_toolchain(tree) + shlex.split(CMAKE_ARGS)
    completed = run(cmd)
    if completed.returncode != 0:
        sys.stderr.write(completed.stdout[-3000:] + completed.stderr[-3000:])
        print("configure of %s failed" % tree)
        return 1
    print("configured %s - %s" % (tree, TREES[tree]["what"]))
    return 0


def build(tree, jobs):
    """Build @p tree, reporting only what went wrong."""
    if configure(tree) != 0:
        return 1
    completed = run(["cmake", "--build", tree_path(tree), "-j", str(jobs)])
    if completed.returncode != 0:
        sys.stdout.write(completed.stdout[-4000:])
        sys.stderr.write(completed.stderr[-4000:])
        print("build of %s failed" % tree)
        return 1
    print("%s built" % tree)
    return 0


def ctest(tree, pattern):
    """Run @p tree's suites, and name the ones that failed."""
    cmd = ["ctest", "--test-dir", tree_path(tree), "--output-on-failure"]
    if pattern:
        cmd += ["-R", pattern]
    completed = run(cmd)

    for line in completed.stdout.splitlines():
        if "tests passed" in line or "tests failed" in line:
            print("  %s: %s" % (tree, line.strip()))
    if completed.returncode != 0:
        for line in completed.stdout.splitlines():
            if "(Failed)" in line or ":FAIL" in line:
                print("    " + line.strip())
    return completed.returncode


def cmd_build(parsed):
    return build(parsed.tree, parsed.jobs)


def cmd_test(parsed):
    if build(parsed.tree, parsed.jobs) != 0:
        return 1
    return 1 if ctest(parsed.tree, parsed.filter) != 0 else 0


def cmd_suites(parsed):
    unregistered = []
    conditional = []
    for suite_dir in discover():
        src = suite_source(suite_dir)
        found, missed = runner_cases(src)
        guarded = conditional_cases(src)
        name = os.path.relpath(suite_dir, ROOT).replace("\\", "/")
        unregistered += [(name, case) for case in missed]
        conditional += [(name, case) for case in guarded]
        note = "" if not missed else "   NOT REGISTERED: " + ", ".join(missed)
        note += "" if not guarded else "   INSIDE AN #if: " + ", ".join(guarded)
        print("%-46s %2d cases%s" % (name, len(found), note))

    if unregistered:
        print("\n%d definitions look like cases and will never run:\n" % len(unregistered))
        for suite, case in unregistered:
            print("   %-40s %s" % (suite, case))
        print(
            "\n  Unity's generator collects file-scope `void test_<name>(void)` and nothing else.\n"
            "  Rename each to test_<name>. The suite passes either way, which is the problem."
        )

    if conditional:
        print("\n%d cases sit inside a preprocessor conditional:\n" % len(conditional))
        for suite, case in conditional:
            print("   %-40s %s" % (suite, case))
        print(
            "\n  The generator does not see the conditional, so the runner declares and calls each\n"
            "  of these however it went. Where it went the other way the definition is gone and the\n"
            "  suite fails to link.\n"
            "\n"
            "  Move the #if inside the case, so every arm compiles into one definition."
        )

    if not unregistered and not conditional:
        print("\nevery case is registered, and none is compiled away by a conditional")
        return 0
    return 1 if parsed.strict else 0


def cmd_cases(parsed):
    for suite_dir in parsed.suite:
        src = suite_source(suite_dir)
        if not src:
            print("%s: no collectable case" % suite_dir)
            continue
        found, missed = runner_cases(src)
        guarded = set(conditional_cases(src))
        print("%s" % os.path.relpath(src, ROOT).replace("\\", "/"))
        for name in found:
            print("   %-12s %s" % ("registered" if name not in guarded else "CONDITIONAL", name))
        for name in missed:
            print("   WALKED PAST  %s" % name)
    return 0


def cmd_runners_gen(parsed):
    for suite_dir in parsed.suite:
        out = generate_runner(suite_dir, parsed.unity)
        print("wrote %s" % os.path.relpath(out, ROOT).replace("\\", "/"))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    # The whole build is three small suites, so parallelism buys little and a low default keeps the
    # machine usable while it runs.
    parser = sub.add_parser("build", help="configure if needed, then build")
    parser.add_argument("--tree", default="build", choices=sorted(TREES), help="which build tree")
    parser.add_argument("--jobs", type=int, default=2, help="build parallelism")
    parser.set_defaults(fn=cmd_build)

    parser = sub.add_parser("test", help="build, then run the suites")
    parser.add_argument("--tree", default="build", choices=sorted(TREES), help="which build tree")
    parser.add_argument("--filter", help="only suites matching this regex")
    parser.add_argument("--jobs", type=int, default=2, help="build parallelism")
    parser.set_defaults(fn=cmd_test)

    parser = sub.add_parser("suites", help="every suite, its cases, and what will never run")
    parser.add_argument("--strict", action="store_true", help="exit non-zero on a finding, for a CI gate")
    parser.set_defaults(fn=cmd_suites)

    parser = sub.add_parser("cases", help="what Unity will register, and what it will walk past")
    parser.add_argument("suite", nargs="+")
    parser.set_defaults(fn=cmd_cases)

    parser = sub.add_parser("runners", help="Unity runner generation")
    psub = parser.add_subparsers(dest="sub", required=True)
    gen = psub.add_parser("gen", help="write a suite's unity_runner.c")
    gen.add_argument("suite", nargs="+")
    gen.add_argument("--unity", required=True, help="path to Unity's auto/generate_test_runner.rb")
    gen.set_defaults(fn=cmd_runners_gen)

    parsed = ap.parse_args()
    return parsed.fn(parsed)


if __name__ == "__main__":
    sys.exit(main())
