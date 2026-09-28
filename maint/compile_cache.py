# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The build's compile cache: each source nvcc is given is compiled once to an object, and a later build of the same
tree with the same flags links that object instead of compiling it again.

    compile_cache.py key <root> ...           prints the tree's key
    compile_cache.py nvcc <real nvcc> <argument> ...

`key` is what the objects of a build depend on besides their flags: the committed files, the uncommitted changes and
the untracked files of each root that is a git checkout, or the commit a pinned export was taken from (its .pinned
file), and the toolkit's version. build_stamp.sh computes it once a build and exports it as COMPILE_CACHE_KEY. It
also writes, beside the objects, the roots and the headers whose names two of the roots' headers share.

`nvcc` stands in for nvcc. Each .cu, .c or .cpp among the arguments is compiled alone with `-c` and every other
argument but the output, into COMPILE_CACHE_DIR under a name made from the key, those arguments and the source's path;
the ones not there yet are compiled COMPILE_CACHE_JOBS at a time (4 by default, what a harness job reserves). The
call is then made again with each source replaced by its object, which only links. nvcc compiles each source of a
call apart without -rdc, so the objects are the ones it would have made. A call that asks for anything else (-E, -M,
-x, -rdc, -dc, -dlink, -ptx, -cubin, -fatbin, -lib, -shared, --version, no source) goes to nvcc as it is, and so does
every call when COMPILE_CACHE_KEY or COMPILE_CACHE_DIR is unset.

An include folder inside the roots is left out of an object's name unless one of the shared-name headers lies under
it: every other header there has one file of its name, so it is found as the same file from any set of folders, and
the suites, each naming its own folders, link the same engine objects. An object one build is compiling is waited
for by another (its .lock), for up to COMPILE_CACHE_WAIT seconds (900 by default), before that one compiles it too.
"""

import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import time

SOURCES = (".cu", ".c", ".cpp")
HEADERS = (".h", ".cuh", ".hpp")
VALUED = {"-o", "-I", "-L", "-l", "-D", "-U", "-gencode", "-Xcompiler", "-Xlinker", "-Xptxas", "-Xnvlink", "-ccbin",
          "-arch", "-code", "-include", "-isystem", "-std", "--output-file", "--compiler-bindir"}
LINK_ONLY = {"-l", "-L", "-Xlinker", "-Xnvlink"}
FOLDERS = {"-I", "-isystem"}
BYPASS = {"-E", "-M", "-MM", "-MD", "-MMD", "-x", "-rdc", "-dc", "-dlink", "-ptx", "-cubin", "-fatbin", "-lib",
          "-shared", "--shared", "--version", "-V", "--preprocess", "--relocatable-device-code", "--device-c",
          "--device-link", "--lib", "-run", "--run", "-dryrun", "--dryrun"}


def git(root, *arguments):
    return subprocess.run(["git", "-C", root] + list(arguments), capture_output=True, check=True).stdout


def same_path(path):
    return os.path.normcase(os.path.abspath(path))


def key(roots):
    digest = hashlib.sha256()
    headers = {}
    for root in roots:
        digest.update(b"root\0" + os.path.abspath(root).encode() + b"\0")
        pinned = os.path.join(root, ".pinned")
        if os.path.isfile(pinned):
            with open(pinned, "rb") as handle:
                digest.update(b"pinned\0" + handle.read())
            for folder, _, names in os.walk(root):
                for name in names:
                    if name.lower().endswith(HEADERS):
                        headers.setdefault(name, set()).add(same_path(os.path.join(folder, name)))
            continue
        digest.update(git(root, "ls-files", "-s"))
        digest.update(git(root, "diff", "HEAD", "--binary"))
        for path in git(root, "ls-files", "-o", "--exclude-standard", "-z").split(b"\0"):
            if path:
                digest.update(path + b"\0")
                with open(os.path.join(root, path.decode()), "rb") as handle:
                    digest.update(hashlib.sha256(handle.read()).digest())
        for path in git(root, "ls-files", "-co", "--exclude-standard", "-z").split(b"\0"):
            name = os.path.basename(path.decode())
            if name.lower().endswith(HEADERS):
                headers.setdefault(name, set()).add(same_path(os.path.join(root, path.decode())))
    real = shutil.which("nvcc")
    if real:
        digest.update(subprocess.run([real, "--version"], capture_output=True).stdout)
    answer = digest.hexdigest()
    folder = os.environ.get("COMPILE_CACHE_DIR", "")
    if folder:
        os.makedirs(folder, exist_ok=True)
        shared = sorted(path for paths in headers.values() if len(paths) > 1 for path in paths)
        lines = ["root " + same_path(root) for root in roots] + ["shared " + path for path in shared]
        written = os.path.join(folder, answer + ".roots")
        partial = "%s.%d.part" % (written, os.getpid())
        with open(partial, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        os.replace(partial, written)
    return answer


def split(arguments):
    """(the flags a source compiles with, the output or None, [(index, source)]), or None where the call is not a
    plain compile-and-link of sources. The compile flags leave out the output, the other files and what only the
    link reads (-l, -L, -Xlinker)."""
    flags = []
    output = None
    sources = []
    at = 0
    while at < len(arguments):
        argument = arguments[at]
        name = argument.split("=", 1)[0]
        if name in BYPASS or argument.startswith(("-M", "--generate-dependencies")):
            return None
        if argument in VALUED and at + 1 < len(arguments):
            if argument in ("-o", "--output-file"):
                output = arguments[at + 1]
            elif argument not in LINK_ONLY:
                flags += [argument, arguments[at + 1]]
            at += 2
            continue
        if not argument.startswith("-"):
            if argument.lower().endswith(SOURCES):
                sources.append((at, argument))
        elif name in ("-o", "--output-file"):
            output = argument.split("=", 1)[1]
        elif not argument.startswith(("-l", "-L")):
            flags.append(argument)
        at += 1
    return (flags, output, sources) if sources else None


def named_flags(flags, folder, cache_key):
    """The flags an object's name is made from: an include folder inside the roots is left out where no shared-name
    header lies under it. Without the roots file every flag is kept."""
    try:
        with open(os.path.join(folder, cache_key + ".roots"), encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return flags
    roots = [line[5:] for line in lines if line.startswith("root ")]
    shared = [line[7:] for line in lines if line.startswith("shared ")]

    def plain(include):
        path = same_path(include)
        inside = any(path == root or path.startswith(root.rstrip(os.sep) + os.sep) for root in roots)
        under = path.rstrip(os.sep) + os.sep
        return inside and not any(header.startswith(under) for header in shared)

    kept = []
    at = 0
    while at < len(flags):
        if flags[at] in FOLDERS and at + 1 < len(flags):
            if not plain(flags[at + 1]):
                kept += flags[at:at + 2]
            at += 2
            continue
        if flags[at].startswith("-I") and len(flags[at]) > 2 and plain(flags[at][2:]):
            at += 1
            continue
        kept.append(flags[at])
        at += 1
    return kept


def main():
    if sys.argv[1] == "key":
        print(key(sys.argv[2:]))
        return 0
    real = sys.argv[2]
    arguments = sys.argv[3:]
    cache_key = os.environ.get("COMPILE_CACHE_KEY", "")
    folder = os.environ.get("COMPILE_CACHE_DIR", "")
    parts = split(arguments) if cache_key and folder else None
    if parts is None:
        return subprocess.run([real] + arguments).returncode
    flags, output, sources = parts
    compile_only = "-c" in flags
    if compile_only and (len(sources) != 1 or output is None):
        return subprocess.run([real] + arguments).returncode
    extension = ".obj" if os.name == "nt" or sys.platform in ("msys", "cygwin") or real.lower().endswith(".exe") \
        else ".o"
    compile_flags = [f for f in flags if f != "-c"]
    name_flags = named_flags(compile_flags, folder, cache_key)
    wait = float(os.environ.get("COMPILE_CACHE_WAIT", "900"))
    os.makedirs(folder, exist_ok=True)

    def object_of(source):
        name = hashlib.sha256("\0".join([cache_key, same_path(source)] + name_flags).encode()).hexdigest()
        return os.path.join(folder, os.path.splitext(os.path.basename(source))[0] + "_" + name[:24] + extension)

    def build(source):
        target = object_of(source)
        lock = target + ".lock"
        began = time.monotonic()
        held = False
        while not os.path.isfile(target):
            try:
                os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
                held = True
                break
            except FileExistsError:
                if time.monotonic() - began > wait:
                    break
                time.sleep(1.0)
        try:
            if os.path.isfile(target):
                return 0
            partial = "%s.%d.part%s" % (target, os.getpid(), extension)
            status = subprocess.run([real, "-c"] + compile_flags + [source, "-o", partial]).returncode
            if status == 0 and os.path.isfile(partial):
                os.replace(partial, target)
                return 0
            if os.path.isfile(partial):
                os.remove(partial)
            return status or 1
        finally:
            if held:
                os.remove(lock)

    jobs = max(1, int(os.environ.get("COMPILE_CACHE_JOBS", "4")))
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        statuses = list(pool.map(build, [source for _, source in sources]))
    if any(statuses):
        return next(s for s in statuses if s)
    if compile_only:
        shutil.copyfile(object_of(sources[0][1]), output)
        return 0
    linked = list(arguments)
    for index, source in sources:
        linked[index] = object_of(source)
    return subprocess.run([real] + linked).returncode


sys.exit(main())
