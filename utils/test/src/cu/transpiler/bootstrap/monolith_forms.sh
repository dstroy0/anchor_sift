#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Writes monolith_forms.md: every form the record programs' lanes decide asked of NVIDIA's compiler in one program, and
# each read back off its listing and its PTX beside the form sass.krs and ptx.krs give (monolith_forms.cpp). Nothing is
# run on the part: the program is built and read.
#
#     utils/test/src/cu/transpiler/bootstrap/monolith_forms.sh [apply] [arch]
#
# With apply, each form whose every question reads whole and alike is written into sass.krs and ptx.krs in place.
set -u

APPLY=""
if [ "${1:-}" = "apply" ]; then
    APPLY="apply"
    shift
fi

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
HERE="$TOP/utils/test/src/cu/transpiler/bootstrap"
RULESETS="$TOP/src/cu/transpiler/codegen/rulesets"
CYCLE="$TOP/src/c/engine/analysis/cycle"
CYCLE_CU="$TOP/src/cu/engine/analysis/cycle"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
KEYMATH="$TOP/src/c/engine/analysis/keymath"
KEYMATH_CU="$TOP/src/cu/engine/analysis/keymath"
KEY_SCHEDULE="$TOP/src/c/engine/analysis/key_schedule"
KEY_SCHEDULE_CU="$TOP/src/cu/engine/analysis/key_schedule"
NO_ROUNDING="$TOP/src/c/types/integers"
SCRIPTURA="$TOP/src/c/engine/runtime/scriptura"
OUT="$TOP/build/monolith/forms"
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
        [ -n "$MSVC_BIN" ] || { echo "  no host compiler nvcc accepts on this platform was found."; exit 1; }
        HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor)
        ;;
esac

# the tool, linked from the code generator and the record programs as sass_lane_needs is
INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/c/includes/codecs/crc" -I "$TOP/src/cu/includes/codecs/crc" -I "$CYCLE"
    -I "$CYCLE_CU" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2" -I "$KEYMATH" -I "$KEYMATH_CU" -I "$KEY_SCHEDULE"
    -I "$KEY_SCHEDULE_CU" -I "$NO_ROUNDING" -I "$SCRIPTURA" -I "$TOP/utils/test/src/c/engine/analysis/cycle")
OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c; do
    object="$OUT/$(basename "$source" .c).o"
    if [ ! -f "$object" ] || [ "$source" -nt "$object" ]; then
        cc -std=c11 -O2 -w "${INCLUDES[@]}" -c "$source" -o "$object" || exit 1
    fi
    OBJECTS+=("$object")
done
for source in "$KEYMATH_CU/keymath.cu" "$KEY_SCHEDULE_CU/key_schedule.cu" "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu; do
    case "$(basename "$source")" in
        asm_printer_*.cu | codegen*.cu) continue ;;
    esac
    object="$OUT/$(basename "$source").o"
    if [ ! -f "$object" ] || [ "$source" -nt "$object" ]; then
        c++ -std=c++17 -O2 -w "${INCLUDES[@]}" -x c++ -c "$source" -o "$object" || exit 1
    fi
    OBJECTS+=("$object")
done
# the machine file's reader and our assembler, which every SASS form read is assembled through before it is written
for source in "$TOP/src/c/types/file_defs/krs/sass_machine.c" "$TOP/src/c/transpiler/cubin/sass_assemble.c"; do
    object="$OUT/$(basename "$source").o"
    if [ ! -f "$object" ] || [ "$source" -nt "$object" ]; then
        cc -std=c11 -O2 -w -I "$TOP/src/c/engine" -I "$TOP/src/c/transpiler/cubin" -I "$TOP/src/c/types/file_defs/krs" \
            -c "$source" -o "$object" || exit 1
    fi
    OBJECTS+=("$object")
done
c++ -std=c++17 -O2 -Wall "${INCLUDES[@]}" -c "$HERE/monolith_forms.cpp" -o "$OUT/monolith_forms.o" || exit 1
c++ -o "$OUT/monolith_forms" "$OUT/monolith_forms.o" "${OBJECTS[@]}" -lpthread || exit 1

# the rulesets are named from the top of the tree, which is where the generator reads them from
cd "$TOP" || exit 1
"$OUT/monolith_forms" write "$RULESETS/c.krs" "$RULESETS/ptx.krs" "$OUT/monolith_forms.cu" "$OUT/questions.tsv" || exit 1
nvcc "${HOST_FLAGS[@]}" -cubin -arch="$ARCH" -O3 -o "$OUT/monolith_forms.cubin" "$OUT/monolith_forms.cu" || exit 1
nvcc "${HOST_FLAGS[@]}" -ptx -arch="$ARCH" -O3 -o "$OUT/monolith_forms.ptx" "$OUT/monolith_forms.cu" || exit 1
cuobjdump -sass "$OUT/monolith_forms.cubin" > "$OUT/monolith_forms.sass" || exit 1
"$OUT/monolith_forms" read "$OUT/questions.tsv" "$OUT/monolith_forms.sass" "$OUT/monolith_forms.ptx" \
    "$RULESETS/sass.krs" "$RULESETS/ptx.krs" "src/c/transpiler/cubin/machines/sm_86" "$HERE/monolith_forms.md" \
    $APPLY || exit 1
