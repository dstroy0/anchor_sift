#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds the cell (compiler/cell), its PTX probe and its SASS probe, then runs the SASS probe: the PTX probe assembles
# each membership question's kernel, written from ptx.krs, into a cubin; nvdisasm lists each, which gives each form's
# machine code; and each operation's 128 bits are turned over one at a time and decoded, which gives its fields
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../.." && pwd)"
CELL="$TOP/src/engine/compiler/cell"
CODEGEN="$TOP/src/engine/compiler/codegen"
CUBIN="$TOP/src/engine/compiler/cubin"
source "$TOP/maint/build_stamp.sh"
build_stamp cell_sass_test

type -P nvdisasm > /dev/null || { echo "  no nvdisasm on the PATH: the CUDA toolkit's disassembler is the oracle"; exit 1; }
type -P cuobjdump > /dev/null || { echo "  no cuobjdump on the PATH: the CUDA toolkit reads the cubin's ELF"; exit 1; }

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/cell_sass_probe.exe"
        PROBE="$OUT/cell_ptx_probe.exe"
        EXTENSION=obj
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        if [ -z "$MSVC_BIN" ]; then
            echo "  no host compiler nvcc accepts on this platform was found."
            exit 1
        fi
        HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor)
        ;;
    *)
        BINARY="$OUT/cell_sass_probe"
        PROBE="$OUT/cell_ptx_probe"
        EXTENSION=o
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

ARCHES="${*:-}"
if [ -z "$ARCHES" ]; then
    CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
    ARCHES="sm_${CAP:-86}"
fi
GENCODE=()
for one in $ARCHES; do
    GENCODE+=(-gencode "arch=compute_${one#sm_},code=${one}")
done

INCLUDES=(-I "$TOP/src/engine" -I "$CELL" -I "$CUBIN")
rm -f "$BINARY" "$PROBE"
OBJECTS=()
for source in "$CELL/cell.c" "$CELL/cell_names.c" "$CUBIN/sass_machine.c" "$CUBIN/sass_assemble.c" \
              "$CUBIN/cubin_write.c" "$TEST/cell_sass_probe_main.c" "$TEST/cell_sass_probe_machine.c" \
              "$TEST/cell_sass_probe_ask.c" "$TEST/cell_sass_probe_class.c" "$TEST/cell_sass_probe_cubin.c" \
              "$TEST/cell_sass_probe_read.c" "$TEST/cell_sass_probe_check.c"; do
    object="$OUT/$(basename "$source" .c).$EXTENSION"
    rm -f "$object"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
        *)
            cc -std=c11 -O2 "${INCLUDES[@]}" -c "$source" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
nvcc "${HOST_FLAGS[@]}" -o "$BINARY" "${OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: the cell's SASS probe did not link"; exit 1; }
# the probe reads rulesets and writes forms; the code generator's assembly printer (asm_printer_*.cu) and the code
# generator on the device (codegen_device_*.cu) run on the record machine, which the probe does not link
CODEGEN_SOURCES=()
for source in "$CODEGEN"/*.cu; do
    case "$(basename "$source")" in
        asm_printer_*.cu|codegen_device_*.cu) ;;
        *) CODEGEN_SOURCES+=("$source") ;;
    esac
done
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" -I "$TOP/src/engine" -o "$PROBE" \
    "$TEST"/cell_ptx_probe_{questions,main}.cu \
    "${CODEGEN_SOURCES[@]}" -lnvrtc -lnvJitLink
[ -f "$PROBE" ] || { echo "  build failed: the PTX probe did not build"; exit 1; }

mkdir -p "$OUT/sass"
"$BINARY" "$PROBE" "$OUT/sass" "$CUBIN/machines"
STATUS=$?
echo "  cell sass test exit $STATUS"
exit "$STATUS"
