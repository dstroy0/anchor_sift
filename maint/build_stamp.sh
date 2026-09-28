#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

# The engine is anchor_sift's src/engine, found from this file's own place, so a build in anchor_sift and a project
# that takes anchor_sift as a submodule and sources this file read the same engine; without it the build fails here,
# before anything compiles
ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/engine"
if [ ! -f "$ENGINE/engine_config.h" ]; then
    echo "  build failed: no engine at $ENGINE (git submodule update --init anchor_sift)"
    exit 1
fi

# a build's path: engine/... is the engine's, and anything else the project's
build_path()
{
    case "$1" in
        engine/*) printf '%s\n' "$ENGINE/${1#engine/}" ;;
        *) printf '%s\n' "$TOP/$1" ;;
    esac
}

# the compile cache (maint/compile_cache.py): nvcc below compiles each source once a tree, into COMPILE_CACHE_DIR, and
# links what an earlier build of the same tree and flags compiled. The key is this project's tree and the engine's,
# taken once here; COMPILE_CACHE=0 turns it off
COMPILE_CACHE_NVCC="$(type -P nvcc 2> /dev/null)"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) COMPILE_CACHE_PYTHON="$(type -P python 2> /dev/null)" ;;
    *) COMPILE_CACHE_PYTHON="$(type -P python3 2> /dev/null)" ;;
esac
if [ "${COMPILE_CACHE:-1}" != 0 ] && [ -n "$COMPILE_CACHE_NVCC" ] && [ -n "$COMPILE_CACHE_PYTHON" ]; then
    COMPILE_CACHE_SCRIPT="$ENGINE/../../maint/compile_cache.py"
    export COMPILE_CACHE_DIR="${COMPILE_CACHE_DIR:-$TOP/build/compile_cache}"
    export COMPILE_CACHE_KEY
    COMPILE_CACHE_KEY="$("$COMPILE_CACHE_PYTHON" "$COMPILE_CACHE_SCRIPT" key "$TOP" "$ENGINE/../..")" || COMPILE_CACHE_KEY=""
    nvcc()
    {
        "$COMPILE_CACHE_PYTHON" "$COMPILE_CACHE_SCRIPT" nvcc "$COMPILE_CACHE_NVCC" "$@"
    }
fi

# the host compiler a program built on the host (CYCLE_RECORD_HOST_C=1) is compiled by: on Windows nvcc, handed
# MSVC's folder as CYCLE_HOST_CCBIN, found as the suites find it
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        if [ -z "${CYCLE_HOST_CCBIN:-}" ]; then
            CYCLE_HOST_CCBIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2> /dev/null | tail -1)"
            if [ -z "$CYCLE_HOST_CCBIN" ]; then
                CYCLE_HOST_CCBIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2> /dev/null | tail -1)"
            fi
            if [ -n "$CYCLE_HOST_CCBIN" ]; then
                CYCLE_HOST_CCBIN="$(cygpath -w "$CYCLE_HOST_CCBIN")"
            fi
        fi
        export CYCLE_HOST_CCBIN
        ;;
esac

build_stamp()
{
    local label="$1"
    if [ -n "${BUILD_OUT:-}" ]; then
        OUT="$BUILD_OUT"
        FINAL="$BUILD_OUT"
        mkdir -p "$OUT"
        return 0
    fi
    FINAL="$TOP/build"
    mkdir -p "$FINAL"
    find "$FINAL" -mindepth 1 -maxdepth 1 -type d \
        -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]_*' \
        -mmin +1440 -exec rm -rf {} +
    OUT="$FINAL/$(date +%Y%m%d_%H%M%S)_$label"
    mkdir -p "$OUT"
    echo "  build directory: $OUT"
}

build_publish()
{
    local artifact="$1"
    [ "$FINAL" = "$OUT" ] && return 0
    cp -f "$artifact" "$FINAL/" || { echo "  build failed: could not copy $artifact to $FINAL (is it running?)"; return 1; }
    echo "  published $FINAL/$(basename "$artifact")"
}
