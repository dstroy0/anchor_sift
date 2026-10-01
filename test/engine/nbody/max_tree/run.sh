#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$(cd "$TEST/../../../../src/engine/nbody/max_tree" && pwd)"
TOP="$(cd "$MODULE/../../../.." && pwd)"
source "$TOP/maint/engine/build_stamp.sh"
build_stamp max_tree_test

EXACT_ROOT="${ANCHOR_EXACT_ROOT:-$TOP/src/engine/arithmetic/no_rounding}"
RESIDUAL_LIMBS="$(sed -n 's/^#define ENGINE_RESIDUAL_LIMBS \([0-9]*\)u.*/\1/p' "$TOP/src/engine"/engine_config_*.h)"
[ -n "$RESIDUAL_LIMBS" ] || { echo "  build failed: no ENGINE_RESIDUAL_LIMBS in engine_config_*.h"; exit 1; }
FITTED_LIMBS=1
while [ "$FITTED_LIMBS" -lt $((RESIDUAL_LIMBS + 1)) ]; do
    FITTED_LIMBS=$((FITTED_LIMBS * 2))
done
EXACT_LIMBS="${ANCHOR_EXACT_LIMBS:-$FITTED_LIMBS}"
EXACT_DIGITS=$(( (EXACT_LIMBS * 32 * 1000 - 1) / 3322 ))
if [ "$EXACT_DIGITS" -gt 1024 ]; then
    EXACT_DIGITS=1024
fi
INCLUDES=(-I "$TOP/src/engine" -I "$MODULE" -I "$EXACT_ROOT"
          "-DANCHOR_EXACT_LIMBS=${EXACT_LIMBS}u" "-DANCHOR_EXACT_DIGITS=${EXACT_DIGITS}u")

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/max_tree_levels_test.exe"
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
        BINARY="$OUT/max_tree_levels_test"
        EXTENSION=o
        HOST_FLAGS=()
        ;;
esac

rm -f "$BINARY"
OBJECTS=()
for source in "$MODULE"/max_tree_{build,nodes,pairs}.c \
              "$EXACT_ROOT"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
              "$TEST"/max_tree_levels_test_{draw,agree}.c; do
    object="$OUT/$(basename "$source" .c)_test.$EXTENSION"
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
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        nvcc "${HOST_FLAGS[@]}" -o "$BINARY" "${OBJECTS[@]}" ;;
    *)
        cc -o "$BINARY" "${OBJECTS[@]}" ;;
esac
[ -f "$BINARY" ] || { echo "  build failed: the test did not link"; exit 1; }

"$BINARY"
STATUS=$?
echo "  max_tree levels test exit $STATUS"
exit "$STATUS"
