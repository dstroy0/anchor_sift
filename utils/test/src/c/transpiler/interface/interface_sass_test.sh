#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds the interface (compiler/interface), its PTX probe and its SASS probe, then runs the SASS probe: the PTX probe assembles
# each membership question's kernel, written from ptx.krs, into a cubin; nvdisasm lists each, which gives each form's
# machine code; and each operation's 128 bits are turned over one at a time and decoded, which gives its fields
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CU="$TEST/../../../cu/transpiler/interface"
TOP="$(cd "$TEST/../../../../../.." && pwd)"
INTERFACE="$TOP/src/c/transpiler/interface"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
CUBIN="$TOP/src/c/transpiler/cubin"
source "$TOP/utils/maint/engine/build_stamp.sh"
build_stamp interface_sass_test

type -P nvdisasm > /dev/null || { echo "  no nvdisasm on the PATH: the CUDA toolkit's disassembler is the oracle"; exit 1; }
type -P cuobjdump > /dev/null || { echo "  no cuobjdump on the PATH: the CUDA toolkit reads the cubin's ELF"; exit 1; }

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/interface_sass_probe.exe"
        PROBE="$OUT/interface_ptx_probe.exe"
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
        BINARY="$OUT/interface_sass_probe"
        PROBE="$OUT/interface_ptx_probe"
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

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$INTERFACE" -I "$CUBIN")
rm -f "$BINARY" "$PROBE"
OBJECTS=()
for source in "$INTERFACE/interface.c" "$INTERFACE/interface_names.c" "$CUBIN/sass_machine.c" "$CUBIN/sass_assemble.c" \
              "$CUBIN/cubin_write.c" "$TEST/interface_sass_probe_main.c" "$TEST/interface_sass_probe_machine.c" \
              "$TEST/interface_sass_probe_ask.c" "$TEST/../../../../../../src/c/types/file_defs/ksc/interface_sass_probe_class.c" "$TEST/interface_sass_probe_cubin.c" \
              "$TEST/interface_sass_probe_read.c" "$TEST/interface_sass_probe_check.c"; do
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
[ -f "$BINARY" ] || { echo "  build failed: the interface's SASS probe did not link"; exit 1; }
# the probe reads rulesets and writes forms; the code generator's assembly printer (asm_printer_*.cu) and the code
# generator on the device (codegen*.cu) run on the record machine, which the probe does not link
CODEGEN_SOURCES=()
for source in "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu; do
    case "$(basename "$source")" in
        asm_printer_*.cu|codegen*.cu) ;;
        *) CODEGEN_SOURCES+=("$source") ;;
    esac
done
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -o "$PROBE" \
    "$TEST_CU"/interface_ptx_probe_{questions,main}.cu \
    "${CODEGEN_SOURCES[@]}" -lnvrtc -lnvJitLink
[ -f "$PROBE" ] || { echo "  build failed: the PTX probe did not build"; exit 1; }

# SASS_PATTERN names the sass folder of an earlier run: the part is asked how it loops against those cubins and the
# machine file the tree holds for the first architecture, and nothing is learned again
if [ -n "${SASS_PATTERN:-}" ]; then
    [ -f "$SASS_PATTERN/form_0.cubin" ] || { echo "  no form_0.cubin in $SASS_PATTERN"; exit 1; }
    FIRST="${ARCHES%% *}"
    "$BINARY" "$PROBE" "$SASS_PATTERN" loop "$CUBIN/machines/$FIRST"
    STATUS=$?
    echo "  interface sass loop exit $STATUS"
    exit "$STATUS"
fi
mkdir -p "$OUT/sass"
"$BINARY" "$PROBE" "$OUT/sass" "$CUBIN/machines"
STATUS=$?
echo "  interface sass test exit $STATUS"
exit "$STATUS"
