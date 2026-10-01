#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$(cd "$TEST/../../../../../src/engine/runtime/obsignatio" && pwd)"
TOP="$(cd "$MODULE/../../.." && pwd)"
SCRIPTURA="$TOP/engine/runtime/scriptura"
# utils/maint/ is at the repository's root, one above src/
source "$(cd "$TOP/.." && pwd)/utils/maint/engine/build_stamp.sh"
build_stamp obsignatio_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/obsignatio_test.exe"
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
        BINARY="$OUT/obsignatio_test"
        EXTENSION=o
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

INCLUDES=(-I "$TOP/engine" -I "$MODULE" -I "$SCRIPTURA")

# a part with no CUDA toolchain (the Pi) builds the seal and the test as C++, and the test asks the host's questions
if ! command -v nvcc > /dev/null 2>&1; then
    rm -f "$BINARY"
    OBJECTS=()
    for source in "$SCRIPTURA"/*.c; do
        object="$OUT/$(basename "$source" .c)_test.$EXTENSION"
        rm -f "$object"
        cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$source" -o "$object"
        [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
        OBJECTS+=("$object")
    done
    c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -o "$BINARY" \
        -x c++ "$TEST"/obsignatio_test_{vectors,properties,streams,main}.cu "$MODULE"/obsignatio_{hash,seal}.cu \
        -x none "${OBJECTS[@]}"
    [ -f "$BINARY" ] || { echo "  build failed: c++ could not build the test"; exit 1; }
    "$BINARY" "$TEST/test_vectors.json"
    STATUS=$?
    echo "  obsignatio test exit $STATUS (host only: no CUDA toolchain)"
    exit "$STATUS"
fi

ARCHES="${*:-}"
if [ -z "$ARCHES" ]; then
    CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
    ARCHES="sm_${CAP:-86}"
fi
GENCODE=()
for one in $ARCHES; do
    GENCODE+=(-gencode "arch=compute_${one#sm_},code=${one}")
done

rm -f "$BINARY"
OBJECTS=()
for source in "$SCRIPTURA"/*.c; do
    object="$OUT/$(basename "$source" .c)_test.$EXTENSION"
    rm -f "$object"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
        *)
            cc -std=c11 -O2 -fPIC "${INCLUDES[@]}" -c "$source" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -o "$BINARY" \
    "$TEST"/obsignatio_test_{vectors,properties,streams,main}.cu "$MODULE"/obsignatio_{hash,seal}.cu "${OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build the test"; exit 1; }

"$BINARY" "$TEST/test_vectors.json"
STATUS=$?
echo "  obsignatio test exit $STATUS"
exit "$STATUS"
