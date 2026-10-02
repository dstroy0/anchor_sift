#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Writes monolith_differences.md: the monolith's tagged build, a block at a time, held against what our compiler
# writes (monolith_emit.cpp).
#
# NVIDIA's compiler builds the tagged monolith once and its listing is the answer key. monolith_emit is linked from
# the code generator's objects, the machine file's reader and our assembler, and reads sass.krs, the machine file and
# the word web as they stand.
#
#     utils/test/src/cu/transpiler/bootstrap/monolith_emit.sh [arch]
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
HERE="$TOP/utils/test/src/cu/transpiler/bootstrap"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
CUBIN="$TOP/src/c/transpiler/cubin"
KRS_C="$TOP/src/c/types/file_defs/krs"
OUT="$TOP/build/monolith/emit"
mkdir -p "$OUT"

ARCH="${1:-}"
if [ -z "$ARCH" ]; then
    CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
    ARCH="sm_${CAP:-86}"
fi

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
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
esac

# the answer key: the tagged monolith built once, and its listing
nvcc "${HOST_FLAGS[@]}" -cubin -arch="$ARCH" -O3 -DMONOLITH_TAGGED=1 -o "$OUT/monolith_tagged.cubin" \
    "$TOP/src/cu/transpiler/bootstrap/monolith.cu" || exit 1
cuobjdump -sass -fun monolith "$OUT/monolith_tagged.cubin" > "$OUT/monolith_tagged.listing" || exit 1

OBJECTS=()
for source in "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu; do
    case "$(basename "$source")" in
        asm_printer_*.cu | codegen*.cu) continue ;;
    esac
    object="$OUT/$(basename "$source").o"
    if [ ! -f "$object" ] || [ "$source" -nt "$object" ]; then
        c++ -std=c++17 -O1 -w -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CODEGEN" -I "$CODEGEN_CU" \
            -I "$CODEGEN_CU_2" -x c++ -c "$source" -o "$object" || exit 1
    fi
    OBJECTS+=("$object")
done
for source in "$KRS_C/sass_machine.c" "$CUBIN/sass_assemble.c"; do
    object="$OUT/$(basename "$source").o"
    cc -std=c11 -O1 -w -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CUBIN" -I "$KRS_C" -c "$source" \
        -o "$object" || exit 1
    OBJECTS+=("$object")
done
c++ -std=c++17 -O1 -Wall -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CODEGEN" -I "$CODEGEN_CU" \
    -I "$CODEGEN_CU_2" -I "$CUBIN" -c "$HERE/monolith_emit.cpp" -o "$OUT/monolith_emit.o" || exit 1
c++ -o "$OUT/monolith_emit" "$OUT/monolith_emit.o" "${OBJECTS[@]}" || exit 1

cd "$TOP" || exit 1
"$OUT/monolith_emit" "build/monolith/emit/monolith_tagged.listing" all \
    "utils/test/src/cu/transpiler/bootstrap/monolith_differences.md" > "$OUT/monolith_emit.out" || exit 1
tail -1 "$OUT/monolith_emit.out"
