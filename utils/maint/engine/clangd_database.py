# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The compilation database clangd reads, written to build/compile_commands.json; .clangd at the repository's root
# points clangd at it. The engine, its sims and its tests build through nvcc, whose command lines clangd cannot read,
# so each source is given here as clang parses it: a .cu as CUDA for this machine's GPU, a .c as C11, and a header as
# C where some .c file reaches it through its includes and as CUDA where only .cu files do. Every directory under the
# trees below that holds a header is on the include path, a superset of what run.sh and CMakeLists.txt name; no two
# headers share a name, which is checked, so the union resolves each include the one way the builds do. Run it again
# after a source or header is added or moved.
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
TREES = ("src", os.path.join("utils", "test"), os.path.join("utils", "bench"), "examples")
SKIPPED = {"python", "build", "node_modules", ".git"}
INCLUDE = re.compile(r'^[ \t]*#[ \t]*include[ \t]*"([^"]+)"', re.MULTILINE)
OUT = os.path.join(ROOT, "build", "compile_commands.json")


def slashed(path):
    return os.path.abspath(path).replace("\\", "/")


def sources():
    found = []
    for tree in TREES:
        for top, directories, files in os.walk(os.path.join(ROOT, tree)):
            directories[:] = sorted(name for name in directories if name not in SKIPPED)
            for name in sorted(files):
                if name.endswith((".c", ".cu", ".h")):
                    found.append(slashed(os.path.join(top, name)))
    return found


def included(path):
    with open(path, encoding="utf-8", errors="replace") as source:
        return [os.path.basename(name) for name in INCLUDE.findall(source.read())]


# the headers some .c file reaches through its includes, followed by name through the repository's own headers
def c_headers(files, by_name):
    reached = set()
    waiting = [path for path in files if path.endswith(".c")]
    while waiting:
        for name in included(waiting.pop()):
            header = by_name.get(name)
            if (header is not None) and (header not in reached):
                reached.add(header)
                waiting.append(header)
    return reached


def version_key(path):
    return [int(part) if part.isdigit() else part for part in re.split(r"[.]", os.path.basename(path))]


# CUDA from CUDA_PATH or the nvcc on the path, the GPU's architecture as run.sh reads it, and on Windows the MSVC
# toolset and Windows SDK clang's CUDA headers need, each the newest installed
def toolchain():
    cuda = os.environ.get("CUDA_PATH", "")
    if not cuda:
        nvcc = shutil.which("nvcc")
        cuda = os.path.dirname(os.path.dirname(nvcc)) if nvcc else ""
    capability = ""
    try:
        answer = subprocess.run(["nvidia-smi", "--query-gpu=compute_cap", "--format=csv,noheader"],
                                capture_output=True, text=True, timeout=30)
        lines = answer.stdout.split()
        capability = lines[0].replace(".", "") if lines else ""
    except (OSError, subprocess.SubprocessError):
        capability = ""
    host = []
    if sys.platform == "win32":
        toolsets = sorted(glob.glob("C:/Program Files (x86)/Microsoft Visual Studio/*/*/VC/Tools/MSVC/*")
                          + glob.glob("C:/Program Files/Microsoft Visual Studio/*/*/VC/Tools/MSVC/*"), key=version_key)
        kits = "C:/Program Files (x86)/Windows Kits/10"
        versions = sorted(glob.glob(kits + "/Include/10.*"), key=version_key)
        if toolsets:
            host += ["-Xmicrosoft-visualc-tools-root", toolsets[-1].replace("\\", "/")]
        if versions:
            host += ["-Xmicrosoft-windows-sdk-root", kits, "-Xmicrosoft-windows-sdk-version",
                     os.path.basename(versions[-1])]
    return cuda.replace("\\", "/"), "sm_" + (capability or "86"), host


def main():
    files = sources()
    by_name = {}
    for path in files:
        if path.endswith(".h"):
            name = os.path.basename(path)
            if name in by_name:
                print("  two headers named %s: %s and %s; the union include path cannot tell them apart"
                      % (name, by_name[name], path))
                return 1
            by_name[name] = path
    reached = c_headers(files, by_name)
    cuda, architecture, host = toolchain()
    includes = []
    for directory in sorted({os.path.dirname(path) for path in by_name.values()}):
        includes += ["-I", directory]
    cuda_flags = ["clang++", "-xcuda", "--cuda-gpu-arch=" + architecture, "-Wno-unknown-cuda-version", "-std=c++17"]
    if cuda:
        cuda_flags.insert(2, "--cuda-path=" + cuda)
    # CUDA 13 keeps cub, thrust and libcu++ under include/cccl, which nvcc puts on the path itself and clang does not
    if cuda and os.path.isdir(cuda + "/include/cccl"):
        cuda_flags += ["-isystem", cuda + "/include/cccl"]
    c_flags = ["clang", "-xc", "-std=c11"]
    entries = []
    counts = {"cuda": 0, "c": 0}
    for path in files:
        kind = "c" if (path.endswith(".c") or (path in reached)) else "cuda"
        counts[kind] += 1
        flags = c_flags if kind == "c" else cuda_flags
        entries.append({"directory": slashed(ROOT), "file": path, "arguments": flags + host + includes + ["-c", path]})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="ascii", newline="\n") as out:
        json.dump(entries, out, indent=1)
        out.write("\n")
    print("  %d entries (%d as CUDA for %s, %d as C11), %d include directories, CUDA at %s"
          % (len(entries), counts["cuda"], architecture, counts["c"], len(includes) // 2, cuda or "none found"))
    print("  written to %s" % slashed(OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
