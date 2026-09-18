#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"
NAME="${DRIVER_NAME:-track_driver}"
EXTRA_DEFINES=(${DRIVER_DEFINES:-})

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/$NAME.exe"
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        if [ -z "$MSVC_BIN" ]; then
            echo "  no host compiler nvcc accepts on this platform was found."
            exit 1
        fi
        HOST_FLAGS=(-ccbin "$MSVC_BIN")
        ;;
    *)
        BINARY="$OUT/$NAME"
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
echo "  architectures: $ARCHES"

EXACT_ROOT="${ANCHOR_EXACT_ROOT:-/d/git_project/repos/owned/public/anchor_sift/src/engine/c/no_rounding}"
RESIDUAL_LIMBS="$(sed -n 's/^#define BINOMIAL_BASINS_LIMBS \([0-9]*\)u.*/\1/p' "$ROOT/engine/binomial_basins.h")"
[ -n "$RESIDUAL_LIMBS" ] || { echo "  build failed: no BINOMIAL_BASINS_LIMBS in binomial_basins.h"; exit 1; }
QUESTION_LIMBS=$((RESIDUAL_LIMBS + 1))
FITTED_LIMBS=1
while [ "$FITTED_LIMBS" -lt "$QUESTION_LIMBS" ]; do
    FITTED_LIMBS=$((FITTED_LIMBS * 2))
done
EXACT_LIMBS="${ANCHOR_EXACT_LIMBS:-$FITTED_LIMBS}"
EXACT_DIGITS=$(( (EXACT_LIMBS * 32 * 1000 - 1) / 3322 ))
if [ "$EXACT_DIGITS" -gt 1024 ]; then
    EXACT_DIGITS=1024
fi
[ -f "$EXACT_ROOT/exact_integer.h" ] || { echo "  build failed: no exact_integer.h under $EXACT_ROOT"; exit 1; }
EXACT_FLAGS=(-I "$EXACT_ROOT" "-DANCHOR_EXACT_LIMBS=${EXACT_LIMBS}u" "-DANCHOR_EXACT_DIGITS=${EXACT_DIGITS}u")
echo "  exact integer: $((EXACT_LIMBS * 32)) bits, $EXACT_DIGITS digits, for a question of $QUESTION_LIMBS limbs, from $EXACT_ROOT"

PORTABLE_OBJECTS=()
for portable in binomial_basins basin_overlap shift_agreement cfg_json max_tree; do
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) OBJECT="$OUT/${portable}_portable.obj" ;;
        *) OBJECT="$OUT/${portable}_portable.o" ;;
    esac
    rm -f "$OBJECT"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" -I "$ROOT/engine" "${EXACT_FLAGS[@]}" -c "$ROOT/engine/$portable.c" -o "$OBJECT" ;;
        *)
            cc -std=c11 -O2 -fPIC -I "$ROOT/engine" "${EXACT_FLAGS[@]}" -c "$ROOT/engine/$portable.c" -o "$OBJECT" ;;
    esac
    [ -f "$OBJECT" ] || { echo "  build failed: engine/$portable.c did not compile"; exit 1; }
    PORTABLE_OBJECTS+=("$OBJECT")
done
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) EXACT_OBJECT="$OUT/exact_integer_portable.obj" ;;
    *) EXACT_OBJECT="$OUT/exact_integer_portable.o" ;;
esac
rm -f "$EXACT_OBJECT"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${EXACT_FLAGS[@]}" -c "$EXACT_ROOT/exact_integer.c" -o "$EXACT_OBJECT" ;;
    *)
        cc -std=c11 -O2 -fPIC "${EXACT_FLAGS[@]}" -c "$EXACT_ROOT/exact_integer.c" -o "$EXACT_OBJECT" ;;
esac
[ -f "$EXACT_OBJECT" ] || { echo "  build failed: exact_integer.c did not compile"; exit 1; }
PORTABLE_OBJECTS+=("$EXACT_OBJECT")

rm -f "$BINARY"
nvcc "${HOST_FLAGS[@]}" -O2 -fmad=false "${GENCODE[@]}" "${EXTRA_DEFINES[@]}" \
    -I "$ROOT/engine" "${EXACT_FLAGS[@]}" \
    -o "$BINARY" \
    "$ROOT/engine/binomial_basins.cu" \
    "$ROOT/engine/binomial_transform.cu" \
    "$ROOT/engine/basin_overlap.cu" \
    "$ROOT/engine/shift_agreement.cu" \
    "$ROOT/engine/climb_machine.cu" \
    "$ROOT/engine/max_tree.cu" \
    "$ROOT/engine/track_driver.cu" \
    "${PORTABLE_OBJECTS[@]}"
STATUS=$?
if [ "$STATUS" -ne 0 ] || [ ! -f "$BINARY" ]; then
    echo "  build failed: nvcc exited $STATUS"
    exit 1
fi
echo "  built $BINARY"
